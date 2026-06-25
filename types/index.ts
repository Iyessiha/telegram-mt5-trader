export interface TradeSignal {
  action: 'BUY' | 'SELL';
  symbol: string;
  entry: number;
  stopLoss: number;
  takeProfit: number;
  volume: number;
}

export interface MT5Response {
  success: boolean;
  orderId?: number;
  error?: string;
}

export interface ValidationResult {
  ok: boolean;
  error?: string;
}

export interface SignalRecord {
  id: string;
  source: 'telegram' | 'api';
  user_id: string;
  symbol: string;
  action: 'BUY' | 'SELL';
  entry: number;
  stop_loss: number;
  take_profit: number;
  volume: number;
  status: 'pending' | 'executed' | 'failed' | 'cancelled';
  mt5_order_id?: number;
  error?: string;
  raw_message: string;
  created_at: string;
  executed_at?: string;
}
