import { VercelRequest, VercelResponse } from '@vercel/node';
import { parseSignal } from '@/lib/telegram';
import { validateSignal } from '@/lib/validation';
import { sendToMT5 } from '@/lib/mt5';
import { supabase } from '@/lib/supabase';

const TELEGRAM_SECRET = process.env.TELEGRAM_SECRET || '';

/**
 * POST /api/telegram-webhook
 * Receive signals from Telegram and execute on MT5
 */
export default async function handler(
  req: VercelRequest,
  res: VercelResponse
) {
  // Only POST allowed
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    // Verify Telegram secret
    const secret = req.headers['x-telegram-secret'] as string;
    if (!secret || secret !== TELEGRAM_SECRET) {
      console.warn('Unauthorized webhook attempt');
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { message, user_id } = req.body;

    if (!message || !user_id) {
      return res.status(400).json({ error: 'Missing message or user_id' });
    }

    console.log(`[${new Date().toISOString()}] Received signal from user ${user_id}: ${message}`);

    // Parse the signal
    const signal = parseSignal(message);
    if (!signal) {
      return res.status(400).json({ 
        error: 'Invalid signal format',
        expected: 'BUY/SELL SYMBOL ENTRY SL:value TP:value [VOL:value]',
        example: 'BUY XAUUSD 2650 SL:2640 TP:2660 VOL:1.0'
      });
    }

    // Validate the signal
    const validation = validateSignal(signal);
    if (!validation.ok) {
      return res.status(400).json({ error: validation.error });
    }

    // Store in database
    const { data: dbRecord, error: dbError } = await supabase
      .from('trading_signals')
      .insert({
        source: 'telegram',
        user_id,
        symbol: signal.symbol,
        action: signal.action,
        entry: signal.entry,
        stop_loss: signal.stopLoss,
        take_profit: signal.takeProfit,
        volume: signal.volume,
        status: 'pending',
        raw_message: message,
        created_at: new Date().toISOString()
      })
      .select()
      .single();

    if (dbError) {
      console.error('Database error:', dbError);
      return res.status(500).json({ 
        error: 'Failed to store signal',
        details: dbError.message 
      });
    }

    // Send to MT5
    const mt5Response = await sendToMT5(signal);

    if (!mt5Response.success) {
      // Mark as failed
      await supabase
        .from('trading_signals')
        .update({ 
          status: 'failed', 
          error: mt5Response.error 
        })
        .eq('id', dbRecord.id);

      console.error('MT5 execution failed:', mt5Response.error);
      return res.status(500).json({ 
        error: 'Failed to execute on MT5',
        details: mt5Response.error 
      });
    }

    // Mark as executed
    await supabase
      .from('trading_signals')
      .update({ 
        status: 'executed',
        mt5_order_id: mt5Response.orderId,
        executed_at: new Date().toISOString()
      })
      .eq('id', dbRecord.id);

    console.log(`[${new Date().toISOString()}] Signal executed successfully. Order ID: ${mt5Response.orderId}`);

    return res.status(200).json({
      success: true,
      message: 'Signal executed successfully',
      signal: {
        id: dbRecord.id,
        ...signal,
        orderId: mt5Response.orderId
      }
    });

  } catch (error) {
    console.error('Webhook error:', error);
    return res.status(500).json({ 
      error: 'Internal server error',
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
}
