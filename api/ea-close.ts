import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../lib/supabase';

const EA_KEY = process.env.TELEGRAM_SECRET || '';

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-ea-key');
}

/**
 * POST /api/ea-close
 * Body: { key, account, ticket, close_price, profit, pips? }
 *
 * Reçu quand un EA détecte la fermeture d'une position qu'il a ouverte.
 * - Met à jour la ligne signal_executions correspondante (account + ticket)
 * - Met à jour trading_signals (par mt5_order_id = ticket) pour la page Performance
 *
 * result déduit du profit: >0 win, <0 loss, =0 breakeven.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).send('METHOD_NOT_ALLOWED');

  const key = (req.body && req.body.key) || (req.headers['x-ea-key'] as string);
  if (!key || key !== EA_KEY) return res.status(401).send('UNAUTHORIZED');

  try {
    const { account, ticket, close_price, profit, pips } = req.body || {};
    if (!ticket) return res.status(400).send('MISSING_TICKET');

    const ticketNum = Number(ticket);
    const profitNum = profit !== undefined && profit !== null ? Number(profit) : null;
    const closePriceNum = close_price !== undefined && close_price !== null ? Number(close_price) : null;
    const pipsNum = pips !== undefined && pips !== null ? Number(pips) : null;

    const result =
      profitNum === null ? null :
      profitNum > 0 ? 'win' :
      profitNum < 0 ? 'loss' : 'breakeven';

    const closedAt = new Date().toISOString();

    // 1) Mettre à jour la ligne d'exécution de CE compte (par account + ticket)
    if (account) {
      const { error: execErr } = await supabase
        .from('signal_executions')
        .update({
          status: 'closed',
          close_price: closePriceNum,
          profit: profitNum,
          pips: pipsNum,
          result,
          closed_at: closedAt,
        })
        .eq('account_id', String(account))
        .eq('ticket', ticketNum);

      if (execErr) console.error('ea-close exec update error:', execErr);
    }

    // 2) Mettre à jour le signal global (page Performance) si pas déjà fermé
    const { data: sig } = await supabase
      .from('trading_signals')
      .select('id, status')
      .eq('mt5_order_id', ticketNum)
      .maybeSingle();

    if (sig && sig.status !== 'closed') {
      const { error: sigErr } = await supabase
        .from('trading_signals')
        .update({
          status: 'closed',
          close_price: closePriceNum,
          pnl_usd: profitNum,
          pips: pipsNum,
          result,
          closed_at: closedAt,
        })
        .eq('id', sig.id);

      if (sigErr) console.error('ea-close signal update error:', sigErr);
    }

    return res.status(200).send('OK');
  } catch (e) {
    console.error('ea-close exception:', e);
    return res.status(500).send('ERROR');
  }
}
