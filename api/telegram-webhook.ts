import { VercelRequest, VercelResponse } from '@vercel/node';
import { parseSignal } from '@/lib/telegram';
import { validateSignal } from '@/lib/validation';
import { sendToMT5 } from '@/lib/mt5';
import { supabase } from '@/lib/supabase';
import { sendTelegramAlert, formatSignalExecuted } from '@/lib/telegram-notify';

const TELEGRAM_SECRET = process.env.TELEGRAM_SECRET || '';

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-telegram-secret');
}

/**
 * POST /api/telegram-webhook
 * 1. Parse signal  2. Validate  3. Store in DB
 * 4. Execute on MT5  5. Send Telegram confirmation
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST')   return res.status(405).json({ error: 'Method not allowed' });

  try {
    // Auth
    const secret = req.headers['x-telegram-secret'] as string;
    if (!secret || secret !== TELEGRAM_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { message, user_id } = req.body;
    if (!message || !user_id) {
      return res.status(400).json({ error: 'Missing message or user_id' });
    }

    console.log(`[${new Date().toISOString()}] Signal from ${user_id}: ${message}`);

    // Parse
    const signal = parseSignal(message);
    if (!signal) {
      return res.status(400).json({
        error:    'Invalid signal format',
        expected: 'BUY/SELL SYMBOL ENTRY SL:value TP:value [VOL:value]',
        example:  'SELL XAUUSD 4024.5 SL:4031 TP:4025 VOL:1.0'
      });
    }

    // Validate
    const validation = validateSignal(signal);
    if (!validation.ok) {
      return res.status(400).json({ error: validation.error });
    }

    // Store → status: pending
    const { data: dbRecord, error: dbError } = await supabase
      .from('trading_signals')
      .insert({
        source:       'telegram',
        user_id,
        symbol:       signal.symbol,
        action:       signal.action,
        entry:        signal.entry,
        stop_loss:    signal.stopLoss,
        take_profit:  signal.takeProfit,
        volume:       signal.volume,
        status:       'pending',
        raw_message:  message,
        created_at:   new Date().toISOString()
      })
      .select()
      .single();

    if (dbError) {
      return res.status(500).json({ error: 'Database error', details: dbError.message });
    }

    // Execute on MT5
    const mt5 = await sendToMT5(signal);

    if (!mt5.success) {
      await supabase
        .from('trading_signals')
        .update({ status: 'failed', error: mt5.error })
        .eq('id', dbRecord.id);

      return res.status(500).json({ error: 'MT5 execution failed', details: mt5.error });
    }

    // Update → status: executed
    await supabase
      .from('trading_signals')
      .update({
        status:       'executed',
        mt5_order_id: mt5.orderId,
        executed_at:  new Date().toISOString()
      })
      .eq('id', dbRecord.id);

    // Telegram confirmation (fire & forget)
    const alertText = formatSignalExecuted({
      action:     signal.action,
      symbol:     signal.symbol,
      entry:      signal.entry,
      stopLoss:   signal.stopLoss,
      takeProfit: signal.takeProfit,
      volume:     signal.volume,
      orderId:    mt5.orderId
    });
    sendTelegramAlert(alertText).catch(e => console.error('Alert err:', e));

    console.log(`[${new Date().toISOString()}] Executed. Order: ${mt5.orderId}`);

    return res.status(200).json({
      success: true,
      message: 'Signal executed',
      signal:  { id: dbRecord.id, ...signal, orderId: mt5.orderId }
    });

  } catch (error) {
    console.error('Webhook error:', error);
    return res.status(500).json({
      error:   'Internal server error',
      message: error instanceof Error ? error.message : 'Unknown'
    });
  }
}
