import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../lib/supabase';

const EA_KEY = process.env.TELEGRAM_SECRET || '';

// Fenêtre de fraîcheur : un EA ne récupère que les signaux récents.
// Évite qu'un nouveau compte (ou un compte rallumé) rejoue tout l'historique.
const FRESH_MINUTES = Number(process.env.EA_FRESH_MINUTES || '15');

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-ea-key');
}

/**
 * Endpoint pour les Expert Advisors (MT4/MT5) — COPY-TRADING MULTI-COMPTES.
 *
 * Chaque EA s'identifie par son numéro de compte (?account=).
 * Un même signal est livré à CHAQUE compte une seule fois.
 *
 * GET  /api/ea-poll?key=SECRET&account=12345&platform=mt5
 *   -> signaux validés récents pas encore exécutés PAR CE COMPTE
 *      Format texte, une ligne par signal :
 *        ID;ACTION;SYMBOL;ENTRY;VOLUME;SL;TP
 *
 * POST /api/ea-poll  { key, id, ticket, account, platform }
 *   -> enregistre l'exécution du signal pour CE compte (table signal_executions)
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();

  // Auth
  const key = (req.query.key as string) || (req.headers['x-ea-key'] as string) || (req.body && req.body.key);
  if (!key || key !== EA_KEY) {
    return res.status(401).send('UNAUTHORIZED');
  }

  // ---- GET : signaux à exécuter pour CE compte ----
  if (req.method === 'GET') {
    try {
      const account = (req.query.account as string) || '';
      const platform = (req.query.platform as string) || 'all';

      const sinceIso = new Date(Date.now() - FRESH_MINUTES * 60000).toISOString();

      const { data: signals, error } = await supabase
        .from('trading_signals')
        .select('*')
        .eq('status', 'executed')
        .gte('created_at', sinceIso)
        .order('created_at', { ascending: true })
        .limit(20);

      if (error) {
        console.error('ea-poll GET error:', error);
        return res.status(500).send('ERROR');
      }
      if (!signals || signals.length === 0) {
        return res.status(200).send('NONE');
      }

      let pending = signals;

      if (account) {
        const ids = signals.map(s => s.id);
        const { data: execs, error: execErr } = await supabase
          .from('signal_executions')
          .select('signal_id')
          .eq('account_id', account)
          .in('signal_id', ids);

        if (execErr) {
          console.error('ea-poll exec lookup error:', execErr);
          return res.status(500).send('ERROR');
        }

        const done = new Set((execs || []).map(e => e.signal_id));
        pending = signals.filter(s => !done.has(s.id));
      }

      if (pending.length === 0) {
        return res.status(200).send('NONE');
      }

      const lines = pending.map(s =>
        `${s.id};${s.action};${s.symbol};${s.entry};${s.volume};${s.stop_loss};${s.take_profit}`
      );

      void platform;
      return res.status(200).send(lines.join('\n'));
    } catch (e) {
      console.error('ea-poll GET exception:', e);
      return res.status(500).send('ERROR');
    }
  }

  // ---- POST : confirmation d'exécution pour CE compte ----
  if (req.method === 'POST') {
    try {
      const { id, ticket, account, platform } = req.body || {};
      if (!id) return res.status(400).send('MISSING_ID');

      if (account) {
        const { error: insErr } = await supabase
          .from('signal_executions')
          .upsert(
            {
              signal_id: id,
              account_id: String(account),
              ticket: ticket ? Number(ticket) : null,
              platform: platform ? String(platform) : null,
            },
            { onConflict: 'signal_id,account_id', ignoreDuplicates: true }
          );

        if (insErr) {
          console.error('ea-poll POST exec error:', insErr);
          return res.status(500).send('ERROR');
        }
      }

      const { data: sig } = await supabase
        .from('trading_signals')
        .select('mt5_order_id')
        .eq('id', id)
        .single();

      if (sig && (sig.mt5_order_id === null || sig.mt5_order_id === undefined)) {
        await supabase
          .from('trading_signals')
          .update({ mt5_order_id: ticket ? Number(ticket) : 0 })
          .eq('id', id);
      }

      return res.status(200).send('OK');
    } catch (e) {
      console.error('ea-poll POST exception:', e);
      return res.status(500).send('ERROR');
    }
  }

  return res.status(405).send('METHOD_NOT_ALLOWED');
}
