import { VercelRequest, VercelResponse } from '@vercel/node';
import { sendTelegramAlert, formatTestAlert, formatDailySummary } from '../lib/telegram-notify';
import { supabase } from '../lib/supabase';

const TELEGRAM_SECRET = process.env.TELEGRAM_SECRET || '';

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-telegram-secret');
}

/**
 * POST /api/send-alert
 * Body: { type, message?, chatId? }
 * Types: test | daily_summary | custom
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  // Verify secret
  const secret = req.headers['x-telegram-secret'] as string;
  if (!secret || secret !== TELEGRAM_SECRET) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const { type = 'custom', message, chatId } = req.body;

    let text = '';

    if (type === 'test') {
      text = formatTestAlert();

    } else if (type === 'daily_summary') {
      // Build daily summary from Supabase
      const today = new Date();
      today.setHours(0, 0, 0, 0);

      const { data: signals } = await supabase
        .from('trading_signals')
        .select('*')
        .gte('created_at', today.toISOString())
        .eq('status', 'executed');

      const closed = (signals || []).filter(s => s.result);
      const wins   = closed.filter(s => s.result === 'win').length;
      const losses = closed.filter(s => s.result === 'loss').length;
      const pips   = closed.reduce((s, t) => s + (Number(t.pips) || 0), 0);
      const pnl    = closed.reduce((s, t) => s + (Number(t.pnl_usd) || 0), 0);

      text = formatDailySummary({
        totalTrades: closed.length,
        wins,
        losses,
        winRate: closed.length > 0 ? (wins / closed.length) * 100 : 0,
        totalPips: parseFloat(pips.toFixed(2)),
        totalPnl:  parseFloat(pnl.toFixed(2))
      });

    } else if (type === 'custom' && message) {
      text = message;

    } else {
      return res.status(400).json({ error: 'Invalid type or missing message' });
    }

    const success = await sendTelegramAlert(text, chatId);

    return res.status(200).json({
      success,
      message: success ? 'Alert sent' : 'Alert failed (check TELEGRAM config)',
      type,
      preview: text.slice(0, 100) + '...'
    });

  } catch (error) {
    console.error('send-alert error:', error);
    return res.status(500).json({
      error:   'Failed to send alert',
      message: error instanceof Error ? error.message : 'Unknown'
    });
  }
}
