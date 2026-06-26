import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../lib/supabase';
import { sendTelegramAlert, formatTradeResult } from '../lib/telegram-notify';

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-telegram-secret');
}

/**
 * POST /api/close-trade
 * Body: { id, result, pips, pnl_usd, close_price }
 * Called by:
 *  - Dashboard (manual close button)
 *  - MT5 EA (automatic on TP/SL hit)
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { id, result, pips, pnl_usd, close_price } = req.body;

    // Validate
    if (!id)                                             return res.status(400).json({ error: 'Signal ID required' });
    if (!['win', 'loss', 'breakeven'].includes(result)) return res.status(400).json({ error: 'Result must be win, loss, or breakeven' });

    // Fetch existing signal
    const { data: signal, error: fetchErr } = await supabase
      .from('trading_signals')
      .select('*')
      .eq('id', id)
      .single();

    if (fetchErr || !signal) return res.status(404).json({ error: 'Signal not found' });
    if (signal.result)       return res.status(409).json({ error: 'Trade already closed', result: signal.result });

    // Update signal with result
    const { data: updated, error: updateErr } = await supabase
      .from('trading_signals')
      .update({
        result,
        pips:        Number(pips)      || 0,
        pnl_usd:     Number(pnl_usd)   || 0,
        close_price: Number(close_price) || null,
        closed_at:   new Date().toISOString()
      })
      .eq('id', id)
      .select()
      .single();

    if (updateErr) throw updateErr;

    // Send Telegram alert (fire and forget)
    const alertText = formatTradeResult({
      action:  signal.action,
      symbol:  signal.symbol,
      result,
      pips:    Number(pips)    || 0,
      pnlUsd:  Number(pnl_usd) || 0
    });
    sendTelegramAlert(alertText).catch(err => console.error('Alert error:', err));

    return res.status(200).json({ success: true, signal: updated });

  } catch (error) {
    console.error('close-trade error:', error);
    return res.status(500).json({
      error:   'Failed to close trade',
      message: error instanceof Error ? error.message : 'Unknown'
    });
  }
}
