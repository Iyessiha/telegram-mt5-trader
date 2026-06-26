import axios from 'axios';

const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || '';
const CHAT_ID = process.env.TELEGRAM_CHAT_ID || '';

/**
 * Send a Telegram message
 */
export async function sendTelegramAlert(text: string, chatId?: string): Promise<boolean> {
  if (!BOT_TOKEN) {
    console.warn('[Telegram] BOT_TOKEN not configured');
    return false;
  }

  const target = chatId || CHAT_ID;
  if (!target) {
    console.warn('[Telegram] CHAT_ID not configured');
    return false;
  }

  try {
    await axios.post(
      `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`,
      { chat_id: target, text, parse_mode: 'HTML' },
      { timeout: 5000 }
    );
    return true;
  } catch (error) {
    console.error('[Telegram] Send error:', error);
    return false;
  }
}

/**
 * Alert: Signal executed on MT5
 */
export function formatSignalExecuted(data: {
  action: string;
  symbol: string;
  entry: number;
  stopLoss: number;
  takeProfit: number;
  volume: number;
  orderId?: number;
}): string {
  const emoji = data.action === 'BUY' ? '🟢' : '🔴';
  const risk = Math.abs(data.entry - data.stopLoss);
  const reward = Math.abs(data.takeProfit - data.entry);
  const rr = risk > 0 ? (reward / risk).toFixed(2) : '0';

  return `${emoji} <b>SIGNAL EXÉCUTÉ</b>

📈 <b>${data.action} ${data.symbol}</b>
💰 Entrée: <code>${data.entry}</code>
🛑 SL: <code>${data.stopLoss}</code>
🎯 TP: <code>${data.takeProfit}</code>
📦 Volume: <b>${data.volume}</b>
📊 Risk/Reward: <b>${rr}:1</b>
🔖 Ordre: #${data.orderId || 'pending'}

⏰ ${new Date().toLocaleString('fr-FR')}
🤖 <i>MonWe Trading Bot</i>`;
}

/**
 * Alert: Trade closed with result
 */
export function formatTradeResult(data: {
  action: string;
  symbol: string;
  result: 'win' | 'loss' | 'breakeven';
  pips: number;
  pnlUsd: number;
}): string {
  const icons: Record<string, string> = { win: '🏆', loss: '❌', breakeven: '⚖️' };
  const labels: Record<string, string> = { win: 'GAGNÉ ✅', loss: 'PERDU ❌', breakeven: 'BREAK EVEN ⚖️' };
  const sign = data.pips >= 0 ? '+' : '';

  return `${icons[data.result]} <b>TRADE ${labels[data.result]}</b>

📈 ${data.action} <b>${data.symbol}</b>
📊 <b>${sign}${data.pips} PIPS</b>
💵 <b>${sign}${data.pnlUsd.toFixed(2)} USD</b>

⏰ ${new Date().toLocaleString('fr-FR')}
🤖 <i>MonWe Trading Bot</i>`;
}

/**
 * Alert: Daily summary
 */
export function formatDailySummary(stats: {
  totalTrades: number;
  wins: number;
  losses: number;
  winRate: number;
  totalPips: number;
  totalPnl: number;
}): string {
  const trend = stats.totalPnl >= 0 ? '📈' : '📉';
  const pSign = stats.totalPips >= 0 ? '+' : '';
  const uSign = stats.totalPnl >= 0 ? '+' : '';

  return `${trend} <b>BILAN DU JOUR</b>

📊 Trades: <b>${stats.totalTrades}</b>  (${stats.wins}✅ / ${stats.losses}❌)
🎯 Win Rate: <b>${stats.winRate.toFixed(0)}%</b>
📈 Pips: <b>${pSign}${stats.totalPips}</b>
💵 P&amp;L: <b>${uSign}${stats.totalPnl.toFixed(2)} USD</b>

⏰ ${new Date().toLocaleString('fr-FR')}
🤖 <i>MonWe Trading Bot</i>`;
}

/**
 * Alert: Connection test
 */
export function formatTestAlert(): string {
  return `✅ <b>Test de Connexion Réussi</b>

🟢 Bot Telegram: <b>Actif</b>
🟢 Vercel: <b>Actif</b>
🟢 Alertes: <b>Configurées</b>

⏰ ${new Date().toLocaleString('fr-FR')}
🤖 <i>MonWe Trading Bot</i>`;
}
