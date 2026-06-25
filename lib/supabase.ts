import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  throw new Error('Missing Supabase environment variables');
}

export const supabase = createClient(supabaseUrl, supabaseServiceKey);

/**
 * Create signals table if it doesn't exist
 */
export async function ensureTablesExist() {
  try {
    // Check if table exists
    const { data, error } = await supabase
      .from('trading_signals')
      .select('id')
      .limit(0);

    if (error && error.code === 'PGRST116') {
      console.log('Creating trading_signals table...');
      
      // Table doesn't exist, create it
      await supabase.rpc('create_signals_table');
    }
  } catch (error) {
    console.error('Error ensuring tables exist:', error);
  }
}

// Create table function (execute via SQL)
export const CREATE_SIGNALS_TABLE_SQL = `
CREATE TABLE IF NOT EXISTS trading_signals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL CHECK (source IN ('telegram', 'api')),
  user_id TEXT NOT NULL,
  symbol TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('BUY', 'SELL')),
  entry DECIMAL(20, 8) NOT NULL,
  stop_loss DECIMAL(20, 8) NOT NULL,
  take_profit DECIMAL(20, 8) NOT NULL,
  volume DECIMAL(20, 8) NOT NULL DEFAULT 1.0,
  status TEXT NOT NULL CHECK (status IN ('pending', 'executed', 'failed', 'cancelled')) DEFAULT 'pending',
  mt5_order_id BIGINT,
  error TEXT,
  raw_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  executed_at TIMESTAMP WITH TIME ZONE,
  CREATED INDEX idx_trading_signals_user_id ON trading_signals(user_id),
  CREATED INDEX idx_trading_signals_status ON trading_signals(status),
  CREATED INDEX idx_trading_signals_created_at ON trading_signals(created_at DESC)
);
`;
