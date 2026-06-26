import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../lib/supabase';

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-telegram-secret');
}

/**
 * GET /api/account-stats
 * Renvoie les performances regroupées PAR COMPTE (multi-comptes / copy-trading).
 *
 * Optionnel: ?account=12345  -> stats d'un seul compte (avec historique des trades).
 *
 * Source: table signal_executions (une ligne par compte par signal).
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();

  // POST: nommer un compte  { key, account, label }
  if (req.method === 'POST') {
    const key = (req.body && req.body.key) || (req.headers['x-telegram-secret'] as string);
    if (!key || key !== (process.env.TELEGRAM_SECRET || '')) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const { account, label } = req.body || {};
    if (!account) return res.status(400).json({ error: 'Missing account' });
    const { error } = await supabase
      .from('account_labels')
      .upsert({ account_id: String(account), label: label || null }, { onConflict: 'account_id' });
    if (error) return res.status(500).json({ error: error.message });
    return res.status(200).json({ ok: true });
  }

  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });

  try {
    const accountFilter = (req.query.account as string) || null;

    // Récupérer les exécutions (+ infos du signal lié)
    let query = supabase
      .from('signal_executions')
      .select('account_id, account_label, ticket, platform, status, result, profit, pips, close_price, closed_at, created_at, signal_id, trading_signals(symbol, action, entry)')
      .order('created_at', { ascending: true });

    if (accountFilter) query = query.eq('account_id', accountFilter);

    const { data: execs, error } = await query;
    if (error) throw error;

    // Libellés de comptes
    const { data: labels } = await supabase.from('account_labels').select('account_id, label');
    const labelMap: Record<string, string> = {};
    (labels || []).forEach(l => { labelMap[l.account_id] = l.label; });

    // Regrouper par compte
    const byAccount: Record<string, any> = {};
    (execs || []).forEach(e => {
      const acc = e.account_id || 'inconnu';
      if (!byAccount[acc]) {
        byAccount[acc] = {
          accountId: acc,
          label: labelMap[acc] || e.account_label || null,
          platform: e.platform || null,
          totalTrades: 0,
          openTrades: 0,
          closedTrades: 0,
          wins: 0,
          losses: 0,
          breakeven: 0,
          totalPnl: 0,
          grossProfit: 0,
          grossLoss: 0,
          lastActivity: null,
          trades: [] as any[],
        };
      }
      const a = byAccount[acc];
      a.totalTrades++;

      const isClosed = e.status === 'closed' || e.result;
      if (isClosed) {
        a.closedTrades++;
        const p = Number(e.profit) || 0;
        a.totalPnl += p;
        if (e.result === 'win') { a.wins++; a.grossProfit += p; }
        else if (e.result === 'loss') { a.losses++; a.grossLoss += Math.abs(p); }
        else if (e.result === 'breakeven') { a.breakeven++; }
      } else {
        a.openTrades++;
      }

      const when = e.closed_at || e.created_at;
      if (!a.lastActivity || (when && when > a.lastActivity)) a.lastActivity = when;

      // Détail des trades (utile pour la vue d'un seul compte)
      const sig: any = e.trading_signals || {};
      a.trades.push({
        ticket: e.ticket,
        symbol: sig.symbol || null,
        action: sig.action || null,
        entry: sig.entry != null ? Number(sig.entry) : null,
        closePrice: e.close_price != null ? Number(e.close_price) : null,
        profit: e.profit != null ? Number(e.profit) : null,
        result: e.result || null,
        status: e.status || (e.result ? 'closed' : 'open'),
        closedAt: e.closed_at,
        createdAt: e.created_at,
      });
    });

    // Finaliser (winRate, profitFactor)
    const accounts = Object.values(byAccount).map((a: any) => {
      a.totalPnl = parseFloat(a.totalPnl.toFixed(2));
      a.grossProfit = parseFloat(a.grossProfit.toFixed(2));
      a.grossLoss = parseFloat(a.grossLoss.toFixed(2));
      a.winRate = a.closedTrades > 0 ? parseFloat(((a.wins / a.closedTrades) * 100).toFixed(2)) : 0;
      a.profitFactor = a.grossLoss > 0 ? parseFloat((a.grossProfit / a.grossLoss).toFixed(2))
                       : a.grossProfit > 0 ? 999 : 0;
      // Pour la vue "tous les comptes", on n'envoie pas le détail des trades (allège)
      if (!accountFilter) delete a.trades;
      return a;
    });

    // Trier par P&L décroissant
    accounts.sort((x: any, y: any) => y.totalPnl - x.totalPnl);

    return res.status(200).json({
      accountsCount: accounts.length,
      accounts,
    });
  } catch (error) {
    console.error('account-stats error:', error);
    return res.status(500).json({
      error: 'Failed to fetch account stats',
      message: error instanceof Error ? error.message : 'Unknown',
    });
  }
}
