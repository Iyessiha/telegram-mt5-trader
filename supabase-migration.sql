-- =====================================================
-- MonWe Trading System - Supabase Migration
-- Run in Supabase SQL Editor (Database → SQL Editor)
-- =====================================================

-- 1. Create table (if not exists - for new projects)
CREATE TABLE IF NOT EXISTS trading_signals (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source        TEXT NOT NULL DEFAULT 'telegram'
                  CHECK (source IN ('telegram', 'api')),
  user_id       TEXT NOT NULL DEFAULT 'system',
  symbol        TEXT NOT NULL,
  action        TEXT NOT NULL CHECK (action IN ('BUY', 'SELL')),
  entry         DECIMAL(20, 8) NOT NULL,
  stop_loss     DECIMAL(20, 8) NOT NULL,
  take_profit   DECIMAL(20, 8) NOT NULL,
  volume        DECIMAL(20, 8) NOT NULL DEFAULT 1.0,
  status        TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'executed', 'failed', 'cancelled')),
  mt5_order_id  BIGINT,
  error         TEXT,
  raw_message   TEXT,

  -- Trade result (filled when trade closes)
  close_price   DECIMAL(20, 8),
  pips          DECIMAL(10, 2),
  pnl_usd       DECIMAL(10, 2),
  result        TEXT CHECK (result IN ('win', 'loss', 'breakeven')),

  -- Timestamps
  created_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  executed_at   TIMESTAMP WITH TIME ZONE,
  closed_at     TIMESTAMP WITH TIME ZONE
);

-- 2. Add new columns to existing table (if upgrading)
ALTER TABLE trading_signals
  ADD COLUMN IF NOT EXISTS close_price  DECIMAL(20, 8),
  ADD COLUMN IF NOT EXISTS pips         DECIMAL(10, 2),
  ADD COLUMN IF NOT EXISTS pnl_usd      DECIMAL(10, 2),
  ADD COLUMN IF NOT EXISTS result       TEXT CHECK (result IN ('win', 'loss', 'breakeven')),
  ADD COLUMN IF NOT EXISTS closed_at    TIMESTAMP WITH TIME ZONE;

-- 3. Indexes for performance
CREATE INDEX IF NOT EXISTS idx_signals_user_id    ON trading_signals(user_id);
CREATE INDEX IF NOT EXISTS idx_signals_status     ON trading_signals(status);
CREATE INDEX IF NOT EXISTS idx_signals_symbol     ON trading_signals(symbol);
CREATE INDEX IF NOT EXISTS idx_signals_created_at ON trading_signals(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_signals_result     ON trading_signals(result);
CREATE INDEX IF NOT EXISTS idx_signals_closed_at  ON trading_signals(closed_at);

-- 4. Verify table structure
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'trading_signals'
ORDER BY ordinal_position;

-- 5. Sample query to verify
-- SELECT COUNT(*) FROM trading_signals;
-- SELECT * FROM trading_signals ORDER BY created_at DESC LIMIT 5;
