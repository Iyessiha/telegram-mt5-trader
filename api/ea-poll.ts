import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabase } from '../lib/supabase';

const EA_KEY = process.env.TELEGRAM_SECRET || '';

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-ea-key');
}

/**
 * Endpoint pour les Expert Advisors (MT4/MT5).
 *
 * GET  /api/ea-poll?key=SECRET
 *   → renvoie les signaux 'executed' non encore récupérés par l'EA,
 *     au format texte simple, une ligne par signal :
 *     ID;ACTION;SYMBOL;ENTRY;VOLUME;SL;TP
 *   (l'EA les exécute puis confirme via POST)
 *
 * POST /api/ea-poll  { key, id, ticket }
 *   → marque le signal comme récupéré par l'EA + enregistre le ticket MT4/MT5
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();

  // Auth (par query ?key= ou header x-ea-key — MQL gère mal les headers custom)
  const key = (req.query.key as string) || (req.headers['x-ea-key'] as string) || (req.body && req.body.key);
  if (!key || key !== EA_KEY) {
    return res.status(401).send('UNAUTHORIZED');
  }

  // ---- GET : récupérer les signaux en attente d'exécution par l'EA ----
  if (req.method === 'GET') {
    try {
      const platform = (req.query.platform as string) || 'all'; // mt4 | mt5 | all

      const { data, error } = await supabase
        .from('trading_signals')
        .select('*')
        .eq('status', 'executed')          // validés via dashboard
        .is('mt5_order_id', null)          // pas encore pris par un EA
        .order('created_at', { ascending: true })
        .limit(10);

      if (error) {
        console.error('ea-poll GET error:', error);
        return res.status(500).send('ERROR');
      }

      if (!data || data.length === 0) {
        return res.status(200).send('NONE');
      }

      // Format texte : une ligne par signal, séparés par \n
      // ID;ACTION;SYMBOL;ENTRY;VOLUME;SL;TP
      const lines = data.map(s =>
        `${s.id};${s.action};${s.symbol};${s.entry};${s.volume};${s.stop_loss};${s.take_profit}`
      );

      void platform; // réservé pour filtrage futur par plateforme
      return res.status(200).send(lines.join('\n'));
    } catch (e) {
      console.error('ea-poll GET exception:', e);
      return res.status(500).send('ERROR');
    }
  }

  // ---- POST : l'EA confirme l'exécution avec son numéro de ticket ----
  if (req.method === 'POST') {
    try {
      const { id, ticket } = req.body || {};
      if (!id) return res.status(400).send('MISSING_ID');

      const { error } = await supabase
        .from('trading_signals')
        .update({ mt5_order_id: ticket ? Number(ticket) : 0 })
        .eq('id', id);

      if (error) {
        console.error('ea-poll POST error:', error);
        return res.status(500).send('ERROR');
      }
      return res.status(200).send('OK');
    } catch (e) {
      console.error('ea-poll POST exception:', e);
      return res.status(500).send('ERROR');
    }
  }

  return res.status(405).send('METHOD_NOT_ALLOWED');
}
