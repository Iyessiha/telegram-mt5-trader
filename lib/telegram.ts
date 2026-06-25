import { TradeSignal } from '@/types/index';

/**
 * Parse Telegram message into trade signal
 * Format: "BUY XAUUSD 2650 SL:2640 TP:2660 VOL:1.0"
 */
export function parseSignal(message: string): TradeSignal | null {
  try {
    const cleaned = message.trim().toUpperCase();
    
    // Regex pour parser: ACTION SYMBOL ENTRY SL:VALUE TP:VALUE [VOL:VALUE]
    const regex = /^(BUY|SELL)\s+([A-Z]+)\s+([\d.]+)\s+SL:([\d.]+)\s+TP:([\d.]+)(?:\s+VOL:([\d.]+))?/;
    
    const match = cleaned.match(regex);
    if (!match) {
      console.log('Signal parse failed for:', message);
      return null;
    }

    const signal: TradeSignal = {
      action: match[1] as 'BUY' | 'SELL',
      symbol: match[2],
      entry: parseFloat(match[3]),
      stopLoss: parseFloat(match[4]),
      takeProfit: parseFloat(match[5]),
      volume: match[6] ? parseFloat(match[6]) : 1.0
    };

    return signal;
  } catch (error) {
    console.error('Error parsing signal:', error);
    return null;
  }
}

/**
 * Format signal for display
 */
export function formatSignal(signal: TradeSignal): string {
  return `${signal.action} ${signal.symbol} @ ${signal.entry} (SL: ${signal.stopLoss}, TP: ${signal.takeProfit}, Vol: ${signal.volume})`;
}
