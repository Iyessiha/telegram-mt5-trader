import { createClient, SupabaseClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

/**
 * Lazy Supabase client.
 * Ne plante PAS au chargement du module si les variables manquent —
 * renvoie plutôt une erreur claire au moment de l'appel.
 */
let _client: SupabaseClient | null = null;

export function getSupabase(): SupabaseClient {
  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error(
      `Variables Supabase manquantes — ` +
      `NEXT_PUBLIC_SUPABASE_URL: ${supabaseUrl ? 'OK' : 'MANQUANTE'}, ` +
      `SUPABASE_SERVICE_ROLE_KEY: ${supabaseServiceKey ? 'OK' : 'MANQUANTE'}`
    );
  }
  if (!_client) {
    _client = createClient(supabaseUrl, supabaseServiceKey);
  }
  return _client;
}

/** Indique si la config Supabase est présente (sans throw). */
export function supabaseConfigured(): { ok: boolean; missing: string[] } {
  const missing: string[] = [];
  if (!supabaseUrl) missing.push('NEXT_PUBLIC_SUPABASE_URL');
  if (!supabaseServiceKey) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  return { ok: missing.length === 0, missing };
}

/**
 * Proxy rétrocompatible : permet de garder `supabase.from(...)` partout.
 * Le client réel n'est créé qu'au premier accès.
 */
export const supabase: SupabaseClient = new Proxy({} as SupabaseClient, {
  get(_target, prop) {
    const client = getSupabase();
    const value = (client as any)[prop];
    return typeof value === 'function' ? value.bind(client) : value;
  }
});
