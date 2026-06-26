import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../lib/supabase';

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-telegram-secret');
}

const empty = {
  totalSignals: 0,
  executedTrades: 0,
  closedTrades: 0,
  wins: 0,
  losses: 0,
  breakeven: 0,
  winRate: 0,
  totalPips: 0,
  totalPnl: 0,
  avgPips: 0,
  profitFactor: 0,
  grossProfit: 0,
  grossLoss: 0,
  bestTrade: null,
  worstTrade: null,
  pendingTrades: 0,
  monthlyData: [],
  symbolData: [],
  pnlTimeline: []
};

/**
 * GET /api/pnl-stats
 * Returns comprehensive trading statistics
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);

  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const { data: signals, error } = await supabase
      .from('trading_signals')
      .select('*')
      .order('created_at', { ascending: true });

    if (error) throw error;
    if (!signals || signals.length === 0) {
      return res.status(200).json(empty);
    }

    const executed = signals.filter(s => s.status === 'executed');
    const closed   = executed.filter(s => s.result);
    const wins     = closed.filter(s => s.result === 'win');
    const losses   = closed.filter(s => s.result === 'loss');
    const be       = closed.filter(s => s.result === 'breakeven');
    const pending  = executed.filter(s => !s.result);

    const winRate     = closed.length > 0 ? (wins.length / closed.length) * 100 : 0;
    const totalPips   = closed.reduce((s, t) => s + (Number(t.pips) || 0), 0);
    const totalPnl    = closed.reduce((s, t) => s + (Number(t.pnl_usd) || 0), 0);
    const grossProfit = wins.reduce((s, t) => s + (Number(t.pnl_usd) || 0), 0);
    const grossLoss   = Math.abs(losses.reduce((s, t) => s + (Number(t.pnl_usd) || 0), 0));
    const profitFactor = grossLoss > 0 ? grossProfit / grossLoss : grossProfit > 0 ? 999 : 0;
    const avgPips     = closed.length > 0 ? totalPips / closed.length : 0;

    const bestTrade  = closed.length > 0 ? closed.reduce((b, t) => (Number(t.pips) || 0) > (Number(b.pips) || 0) ? t : b) : null;
    const worstTrade = closed.length > 0 ? closed.reduce((w, t) => (Number(t.pips) || 0) < (Number(w.pips) || 0) ? t : w) : null;

    // Monthly breakdown
    const monthlyMap: Record<string, { month: string; trades: number; wins: number; pips: number; pnl: number }> = {};
    closed.forEach(s => {
      const d   = new Date(s.created_at);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      if (!monthlyMap[key]) monthlyMap[key] = { month: key, trades: 0, wins: 0, pips: 0, pnl: 0 };
      monthlyMap[key].trades++;
      if (s.result === 'win') monthlyMap[key].wins++;
      monthlyMap[key].pips += Number(s.pips) || 0;
      monthlyMap[key].pnl  += Number(s.pnl_usd) || 0;
    });
    const monthlyData = Object.values(monthlyMap).map(m => ({
      ...m,
      winRate: m.trades > 0 ? (m.wins / m.trades) * 100 : 0
    }));

    // Symbol breakdown
    const symMap: Record<string, { symbol: string; trades: number; wins: number; pips: number }> = {};
    closed.forEach(s => {
      if (!symMap[s.symbol]) symMap[s.symbol] = { symbol: s.symbol, trades: 0, wins: 0, pips: 0 };
      symMap[s.symbol].trades++;
      if (s.result === 'win') symMap[s.symbol].wins++;
      symMap[s.symbol].pips += Number(s.pips) || 0;
    });
    const symbolData = Object.values(symMap).map(m => ({
      ...m,
      winRate: m.trades > 0 ? (m.wins / m.trades) * 100 : 0
    }));

    // Cumulative PnL timeline
    let cum = 0;
    const pnlTimeline = closed.map(s => {
      cum += Number(s.pnl_usd) || 0;
      return {
        date:   s.closed_at || s.executed_at || s.created_at,
        cumPnl: parseFloat(cum.toFixed(2)),
        pips:   Number(s.pips) || 0,
        symbol: s.symbol,
        action: s.action,
        result: s.result
      };
    });

    return res.status(200).json({
      totalSignals:  signals.length,
      executedTrades: executed.length,
      closedTrades:  closed.length,
      wins:          wins.length,
      losses:        losses.length,
      breakeven:     be.length,
      pendingTrades: pending.length,
      winRate:       parseFloat(winRate.toFixed(2)),
      totalPips:     parseFloat(totalPips.toFixed(2)),
      totalPnl:      parseFloat(totalPnl.toFixed(2)),
      avgPips:       parseFloat(avgPips.toFixed(2)),
      profitFactor:  parseFloat(profitFactor.toFixed(2)),
      grossProfit:   parseFloat(grossProfit.toFixed(2)),
      grossLoss:     parseFloat(grossLoss.toFixed(2)),
      bestTrade,
      worstTrade,
      monthlyData,
      symbolData,
      pnlTimeline
    });

  } catch (error) {
    console.error('pnl-stats error:', error);
    return res.status(500).json({
      error:   'Failed to fetch PnL stats',
      message: error instanceof Error ? error.message : 'Unknown'
    });
  }
}
