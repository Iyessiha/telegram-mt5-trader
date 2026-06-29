import { TradeSignal, ValidationResult } from '../types/index';

const ALLOWED_SYMBOLS = [
  // Forex majeurs
  'EURUSD', 'GBPUSD', 'USDJPY', 'AUDUSD', 'NZDUSD', 'USDCAD', 'USDCHF',
  'EURGBP', 'EURJPY', 'GBPJPY', 'EURCHF', 'AUDJPY', 'CADJPY', 'CHFJPY', 'EURCAD', 'EURAUD', 'GBPAUD', 'GBPCAD',
  // Métaux
  'XAUUSD', 'XAGUSD', 'XPTUSD', 'XPDUSD',
  // Crypto
  'BTCUSD', 'ETHUSD', 'LTCUSD', 'XRPUSD', 'BCHUSD', 'ADAUSD', 'SOLUSD', 'DOGEUSD', 'BNBUSD',
  // Indices
  'US30', 'US500', 'USTEC', 'NAS100', 'SPX500', 'DJI30', 'NDX100',
  'GER40', 'DE40', 'UK100', 'FRA40', 'EU50', 'ESP35', 'JP225', 'AUS200', 'HK50', 'US2000',
  // Énergie
  'USOIL', 'UKOIL', 'WTI', 'BRENT', 'XBRUSD', 'XTIUSD',
];
const MAX_VOLUME = 10;
const MIN_VOLUME = 0.01;

export function validateSignal(signal: TradeSignal): ValidationResult {
  try {
    // Check required fields
    if (!signal.symbol || signal.entry === undefined || signal.stopLoss === undefined || signal.takeProfit === undefined) {
      return { ok: false, error: 'Missing required fields' };
    }

    // Check action
    if (!['BUY', 'SELL'].includes(signal.action)) {
      return { ok: false, error: 'Invalid action (BUY or SELL)' };
    }

    // Check symbol is allowed (liste connue OU format de ticker valide)
    const sym = String(signal.symbol).toUpperCase();
    const isKnown = ALLOWED_SYMBOLS.includes(sym);
    const looksLikeTicker = /^[A-Z0-9]{3,12}$/.test(sym);
    if (!isKnown && !looksLikeTicker) {
      return { ok: false, error: `Symbole invalide: "${signal.symbol}"` };
    }

    // Check entry price is positive
    // Exception: entry=0 = signal rapide (exécution au prix marché)
    const isQuick = signal.entry === 0;
    if (isQuick) {
      return { ok: true };   // SL/TP sont en pips, l'EA les calcule — pas de validation de niveaux
    }
    if (signal.entry <= 0) {
      return { ok: false, error: 'Entry price must be positive' };
    }

    // Check stop loss is different from entry
    if (signal.stopLoss === signal.entry) {
      return { ok: false, error: 'Stop loss cannot be at entry price' };
    }

    // Check take profit is different from entry
    if (signal.takeProfit === signal.entry) {
      return { ok: false, error: 'Take profit cannot be at entry price' };
    }

    // For BUY orders: TP should be above entry, SL below
    if (signal.action === 'BUY') {
      if (signal.takeProfit <= signal.entry) {
        return { ok: false, error: 'For BUY: take profit must be above entry' };
      }
      if (signal.stopLoss >= signal.entry) {
        return { ok: false, error: 'For BUY: stop loss must be below entry' };
      }
    }

    // For SELL orders: TP should be below entry, SL above
    if (signal.action === 'SELL') {
      if (signal.takeProfit >= signal.entry) {
        return { ok: false, error: 'For SELL: take profit must be below entry' };
      }
      if (signal.stopLoss <= signal.entry) {
        return { ok: false, error: 'For SELL: stop loss must be above entry' };
      }
    }

    // Calculate risk and reward
    // Reward basé sur le TP le plus ÉLOIGNÉ (multi-TP: on vise la cible lointaine)
    const risk = Math.abs(signal.entry - signal.stopLoss);
    const tpList: number[] = (Array.isArray((signal as any).takeProfits) && (signal as any).takeProfits.length)
      ? (signal as any).takeProfits
      : [signal.takeProfit];
    const farthestTp = tpList.reduce((far, tp) =>
      Math.abs(tp - signal.entry) > Math.abs(far - signal.entry) ? tp : far
    , tpList[0]);
    const reward = Math.abs(farthestTp - signal.entry);

    if (risk === 0) {
      return { ok: false, error: 'Stop loss must be different from entry' };
    }

    // Ratio risque/récompense minimum 1:1
    const ratio = reward / risk;
    if (ratio < 1.0) {
      return { ok: false, error: `Risk/reward ratio too low (${ratio.toFixed(2)}:1, minimum 1:1)` };
    }

    // Check volume
    if (signal.volume < MIN_VOLUME) {
      return { ok: false, error: `Volume must be at least ${MIN_VOLUME}` };
    }

    if (signal.volume > MAX_VOLUME) {
      return { ok: false, error: `Volume exceeds maximum ${MAX_VOLUME}` };
    }

    return { ok: true };
  } catch (error) {
    return { 
      ok: false, 
      error: error instanceof Error ? error.message : 'Unknown validation error' 
    };
  }
}

export function calculateRiskReward(signal: TradeSignal): { risk: number; reward: number; ratio: number } {
  const risk = Math.abs(signal.entry - signal.stopLoss);
  const reward = Math.abs(signal.takeProfit - signal.entry);
  const ratio = risk > 0 ? reward / risk : 0;

  return { risk, reward, ratio };
}
