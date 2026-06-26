import { VercelRequest, VercelResponse } from '@vercel/node';
import { supabaseConfigured, getSupabase } from '../lib/supabase';

function cors(res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type,x-telegram-secret');
}

/**
 * GET /api/health
 * Vérifie l'état du système — ne plante jamais, renvoie toujours un JSON.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();

  const health: any = {
    timestamp: new Date().toISOString(),
    status: 'OK',
    env: {
      TELEGRAM_BOT_TOKEN:        process.env.TELEGRAM_BOT_TOKEN ? 'OK' : 'MANQUANTE',
      TELEGRAM_SECRET:           process.env.TELEGRAM_SECRET ? 'OK' : 'MANQUANTE',
      TELEGRAM_CHAT_ID:          process.env.TELEGRAM_CHAT_ID ? 'OK' : 'MANQUANTE',
      NEXT_PUBLIC_SUPABASE_URL:  process.env.NEXT_PUBLIC_SUPABASE_URL ? 'OK' : 'MANQUANTE',
      SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY ? 'OK' : 'MANQUANTE'
    },
    services: { supabase: 'unknown' }
  };

  // Test Supabase
  const cfg = supabaseConfigured();
  if (!cfg.ok) {
    health.services.supabase = 'NON_CONFIGURÉ';
    health.supabaseMissing = cfg.missing;
  } else {
    try {
      const sb = getSupabase();
      const { error } = await sb.from('trading_signals').select('id').limit(1);
      if (error) {
        health.services.supabase = 'ERREUR';
        health.supabaseError = error.message;
        if (error.message.includes('does not exist') || error.code === 'PGRST205') {
          health.hint = "La table 'trading_signals' n'existe pas — lance supabase-migration.sql";
        }
      } else {
        health.services.supabase = 'OK';
      }
    } catch (e) {
      health.services.supabase = 'ERREUR';
      health.supabaseError = e instanceof Error ? e.message : 'Inconnue';
    }
  }

  // Statut global
  const allEnvOk = Object.values(health.env).every(v => v === 'OK');
  const supaOk = health.services.supabase === 'OK';
  health.status = (allEnvOk && supaOk) ? 'OK' : 'DÉGRADÉ';

  return res.status(200).json(health);
}
