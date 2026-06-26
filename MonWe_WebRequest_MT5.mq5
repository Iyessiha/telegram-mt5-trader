//+------------------------------------------------------------------+
//|                              MonWe_WebRequest_MT5.mq5             |
//|                              MonWe Infinity LLC                   |
//|        Récupère les signaux depuis Vercel via WebRequest         |
//+------------------------------------------------------------------+
#property copyright "MonWe Infinity LLC"
#property link      "https://telegram-mt5-trader.vercel.app"
#property version   "1.00"
#property description "Récupère les signaux validés depuis l'API Vercel et les exécute sur MT5"

#include <Trade\Trade.mqh>
CTrade trade;

//--- Paramètres d'entrée
enum ENUM_ORDER_MODE_X
{
   ORDER_MODE_AUTO   = 0,  // AUTO (déduit limite/stop/marché selon l'entrée)
   ORDER_MODE_MARKET = 1,  // MARCHÉ (exécution immédiate au prix actuel)
   ORDER_MODE_PENDING= 2   // EN ATTENTE (toujours limite/stop au prix d'entrée)
};

input string  InpApiUrl      = "https://telegram-mt5-trader.vercel.app"; // URL de base Vercel
input string  InpSecret      = "VOTRE_SECRET_ICI";  // TELEGRAM_SECRET (identique à Vercel)
input int     InpPollSeconds = 5;                   // Fréquence de vérification (secondes)
input double  InpMaxVolume   = 1.0;                 // Volume max autorisé (sécurité)
input int     InpSlippage    = 30;                  // Slippage max (points)
input int     InpMagic       = 20260626;            // Magic number
input string  InpSymbolPrefix = "";                 // Préfixe symbole broker (souvent vide)
input string  InpSymbolSuffix = "c";                // Suffixe par défaut (Exness = "c")
input string  InpSymbolMap    = "";                 // Mapping spécifique: SIGNAL=BROKER,... (ex: US30=US30,BTCUSD=BTCUSD)
input bool    InpAutoResolveSymbol = true;          // Si introuvable, chercher le bon nom automatiquement
input string  InpAllowedSymbols = "";               // Symboles autorisés (vide = TOUS). Ex: XAUUSD,BTCUSD
input bool    InpVerbose     = true;                // Journaux détaillés

//--- Type d'ordre (marché / limite / stop)
input ENUM_ORDER_MODE_X InpOrderMode = ORDER_MODE_AUTO; // Mode d'ordre
input double  InpEntryTolerance = 50;               // Tolérance (points): entrée≈marché → MARCHÉ
input int     InpPendingExpiryMin = 0;              // Expiration ordre en attente (min, 0=GTC)

//--- Gestion automatique du SL (Break-Even & Trailing)
input bool    InpUseBreakEven = true;               // Activer le Break-Even auto
input double  InpBE_TriggerPips = 100;              // BE: profit (en points) avant de bouger le SL
input double  InpBE_LockPips    = 10;               // BE: points de profit verrouillés (SL = entrée + X)
input bool    InpUseTrailing   = true;              // Activer le Trailing Stop auto
input double  InpTrail_StartPips = 150;             // Trailing: profit (points) avant de démarrer
input double  InpTrail_DistPips  = 100;             // Trailing: distance du SL au prix (points)
input double  InpTrail_StepPips  = 20;              // Trailing: pas minimum de déplacement (points)

//--- Variables globales
datetime g_lastPoll = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);

   Print("=== MonWe WebRequest EA (MT5) démarré ===");
   Print("API: ", InpApiUrl);
   Print("Polling: toutes les ", InpPollSeconds, "s");

   // Vérifier que WebRequest est autorisé
   Print("⚠ IMPORTANT: Ajoutez cette URL dans:");
   Print("   Outils → Options → Expert Advisors → Autoriser WebRequest pour:");
   Print("   ", InpApiUrl);

   EventSetTimer(InpPollSeconds);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("EA arrêté. Raison: ", reason);
}

//+------------------------------------------------------------------+
void OnTimer()
{
   PollSignals();
   ManageOpenPositions();   // Break-Even + Trailing Stop auto
}

//+------------------------------------------------------------------+
//| Interroge l'API Vercel pour les signaux en attente              |
//+------------------------------------------------------------------+
void PollSignals()
{
   string url = InpApiUrl + "/api/ea-poll?key=" + InpSecret + "&platform=mt5"
                + "&account=" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));

   char   post[];
   char   result[];
   string headers;
   string resultHeaders;
   int    timeout = 5000;

   ResetLastError();
   int code = WebRequest("GET", url, NULL, NULL, timeout, post, 0, result, resultHeaders);

   if(code == -1)
   {
      int err = GetLastError();
      if(err == 4060)
      {
         Print("❌ ERREUR: URL non autorisée. Ajoutez dans Outils → Options → Expert Advisors:");
         Print("   ", InpApiUrl);
      }
      else
      {
         Print("❌ WebRequest échoué. Code erreur: ", err);
      }
      return;
   }

   if(code != 200)
   {
      if(InpVerbose) Print("Réponse HTTP: ", code);
      return;
   }

   string response = CharArrayToString(result);
   StringTrimRight(response);
   StringTrimLeft(response);

   if(response == "NONE" || response == "")
   {
      // Aucun signal en attente — normal
      return;
   }

   if(response == "UNAUTHORIZED")
   {
      Print("❌ Secret invalide. Vérifiez InpSecret = TELEGRAM_SECRET");
      return;
   }

   // Traiter chaque ligne (un signal par ligne)
   string lines[];
   int n = StringSplit(response, '\n', lines);
   for(int i = 0; i < n; i++)
   {
      string line = lines[i];
      StringTrimRight(line);
      StringTrimLeft(line);
      if(StringLen(line) > 0)
         ProcessSignal(line);
   }
}

//+------------------------------------------------------------------+
//| Traite un signal : ID;ACTION;SYMBOL;ENTRY;VOLUME;SL;TP          |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Vérifie si le symbole (brut, ex: XAUUSD) est dans la liste       |
//| autorisée. Tolère les variantes Gold/BTC.                        |
//+------------------------------------------------------------------+
bool IsSymbolAllowed(string rawSymbol)
{
   string up = rawSymbol;
   StringToUpper(up);

   string allowed[];
   int n = StringSplit(InpAllowedSymbols, ',', allowed);
   for(int i = 0; i < n; i++)
   {
      string a = allowed[i];
      StringTrimRight(a);
      StringTrimLeft(a);
      StringToUpper(a);
      if(StringLen(a) == 0) continue;

      // Correspondance exacte
      if(up == a) return true;

      // Tolérance familles: "XAU" couvre XAUUSD/GOLD, "BTC" couvre BTCUSD/BITCOIN
      if(a == "XAUUSD" || a == "GOLD" || a == "XAU")
         if(StringFind(up, "XAU") >= 0 || StringFind(up, "GOLD") >= 0) return true;
      if(a == "BTCUSD" || a == "BTC" || a == "BITCOIN")
         if(StringFind(up, "BTC") >= 0 || StringFind(up, "BITCOIN") >= 0) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Résout le nom du symbole chez le broker                          |
//| Priorité: 1) mapping explicite  2) préfixe/suffixe  3) auto      |
//+------------------------------------------------------------------+
bool SymbolExistsBroker(string s)
{
   if(StringLen(s) == 0) return false;
   if(SymbolSelect(s, true)) return true;
   // SymbolSelect peut réussir même si déjà visible; vérifier via SymbolInfoInteger
   long sel = 0;
   if(SymbolInfoInteger(s, SYMBOL_SELECT, sel)) return true;
   return false;
}

string ResolveBrokerSymbol(string raw)
{
   string up = raw;
   StringToUpper(up);

   // ---- 1) Mapping explicite "SIGNAL=BROKER,SIGNAL=BROKER" ----
   if(StringLen(InpSymbolMap) > 0)
   {
      string pairs[];
      int n = StringSplit(InpSymbolMap, ',', pairs);
      for(int i = 0; i < n; i++)
      {
         string kv[];
         if(StringSplit(pairs[i], '=', kv) == 2)
         {
            string k = kv[0]; StringTrimLeft(k); StringTrimRight(k); StringToUpper(k);
            string v = kv[1]; StringTrimLeft(v); StringTrimRight(v);
            if(k == up)
            {
               if(InpVerbose) Print("🔗 Mapping: ", raw, " → ", v);
               return v;  // nom broker explicite, tel quel
            }
         }
      }
   }

   // ---- 2) Préfixe + symbole + suffixe (comportement par défaut) ----
   string candidate = InpSymbolPrefix + raw + InpSymbolSuffix;
   if(SymbolExistsBroker(candidate))
      return candidate;

   // ---- 3) Résolution automatique si introuvable ----
   if(InpAutoResolveSymbol)
   {
      // a) tel quel, sans préfixe/suffixe
      if(SymbolExistsBroker(raw)) { if(InpVerbose) Print("🔍 Résolu sans suffixe: ", raw); return raw; }

      // b) variantes de suffixes courants
      string suffixes[] = {"", "c", "m", "z", ".r", "_raw", "pro", "#"};
      for(int i = 0; i < ArraySize(suffixes); i++)
      {
         string t = InpSymbolPrefix + raw + suffixes[i];
         if(SymbolExistsBroker(t)) { if(InpVerbose) Print("🔍 Résolu (suffixe '", suffixes[i], "'): ", t); return t; }
      }

      // c) scan complet de la liste des symboles du broker (commence par 'raw')
      int total = SymbolsTotal(false);
      for(int i = 0; i < total; i++)
      {
         string name = SymbolName(i, false);
         string nu = name; StringToUpper(nu);
         if(StringFind(nu, up) == 0)  // commence par le symbole brut
         {
            if(InpVerbose) Print("🔍 Résolu par scan: ", raw, " → ", name);
            return name;
         }
      }
   }

   // Aucune correspondance: renvoyer le candidat préfixe/suffixe (échouera proprement plus loin)
   if(InpVerbose) Print("⚠ Symbole non résolu pour ", raw, " — tentative avec ", candidate);
   return candidate;
}

//+------------------------------------------------------------------+
void ProcessSignal(string line)
{
   string p[];
   int cnt = StringSplit(line, ';', p);
   if(cnt < 7)
   {
      Print("Signal mal formé: ", line);
      return;
   }

   string sigId  = p[0];
   string action = p[1];
   string symbol = p[2];   // symbole brut du signal (ex: XAUUSD)
   double entry  = StringToDouble(p[3]);
   double volume = StringToDouble(p[4]);
   double sl     = StringToDouble(p[5]);
   double tp     = StringToDouble(p[6]);

   // ---- FILTRE: seuls les symboles autorisés passent ----
   if(StringLen(InpAllowedSymbols) > 0 && !IsSymbolAllowed(symbol))
   {
      if(InpVerbose)
         Print("⛔ Symbole non autorisé: ", symbol, " (autorisés: ", InpAllowedSymbols, ")");
      // On confirme pour ne pas re-traiter en boucle
      ConfirmExecution(sigId, 0);
      return;
   }

   // Adapter le symbole au broker (mapping spécifique > suffixe > résolution auto)
   symbol = ResolveBrokerSymbol(symbol);

   // Sécurité volume
   if(volume > InpMaxVolume)
   {
      Print("⚠ Volume ", volume, " > max ", InpMaxVolume, " — plafonné");
      volume = InpMaxVolume;
   }

   if(InpVerbose)
      PrintFormat("📥 Signal: %s %s @ %.5f (SL:%.5f TP:%.5f Vol:%.2f)",
                  action, symbol, entry, sl, tp, volume);

   // Vérifier que le symbole existe
   if(!SymbolSelect(symbol, true))
   {
      Print("❌ Symbole introuvable: ", symbol);
      ConfirmExecution(sigId, 0);
      return;
   }

   // --- Normalisation et validation des stops (évite l'erreur 10016) ---
   int    digits   = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point    = SymbolInfoDouble(symbol, SYMBOL_POINT);
   long   stopsLvl = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long   freezeLvl= SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist  = (double)(MathMax(stopsLvl, freezeLvl)) * point;
   if(minDist <= 0) minDist = 10 * point;  // marge de sécurité si broker renvoie 0

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double mktPrice = (action == "BUY") ? ask : bid;

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);
   entry = NormalizeDouble(entry, digits);

   // ============================================================
   // DÉCISION: ordre au MARCHÉ ou EN ATTENTE (limite/stop) ?
   // ============================================================
   bool useMarket;
   if(InpOrderMode == ORDER_MODE_MARKET)       useMarket = true;
   else if(InpOrderMode == ORDER_MODE_PENDING) useMarket = false;
   else // AUTO
   {
      double dist = MathAbs(entry - mktPrice);
      // entrée absente/nulle, ou très proche du marché → exécution immédiate
      useMarket = (entry <= 0) || (dist <= InpEntryTolerance * point);
   }

   // Un ordre en attente trop proche du marché serait rejeté → bascule marché
   if(!useMarket && MathAbs(entry - mktPrice) < minDist)
   {
      if(InpVerbose) Print("ℹ Entrée trop proche du marché → exécution au marché");
      useMarket = true;
   }

   // ============================================================
   // CAS 1 : ORDRE AU MARCHÉ
   // ============================================================
   if(useMarket)
   {
   // Vérifier la cohérence du sens ET la distance minimale, par rapport au PRIX RÉEL
   bool stopsValid = true;
   string why = "";

   if(action == "BUY")
   {
      // BUY: SL en dessous, TP au dessus du prix marché
      if(sl > 0 && sl >= mktPrice)              { stopsValid=false; why="SL BUY au-dessus du prix"; }
      if(tp > 0 && tp <= mktPrice)              { stopsValid=false; why="TP BUY en-dessous du prix"; }
      if(sl > 0 && (mktPrice - sl) < minDist)   { stopsValid=false; why="SL trop proche"; }
      if(tp > 0 && (tp - mktPrice) < minDist)   { stopsValid=false; why="TP trop proche"; }
   }
   else // SELL
   {
      // SELL: SL au dessus, TP en dessous du prix marché
      if(sl > 0 && sl <= mktPrice)              { stopsValid=false; why="SL SELL en-dessous du prix"; }
      if(tp > 0 && tp >= mktPrice)              { stopsValid=false; why="TP SELL au-dessus du prix"; }
      if(sl > 0 && (sl - mktPrice) < minDist)   { stopsValid=false; why="SL trop proche"; }
      if(tp > 0 && (mktPrice - tp) < minDist)   { stopsValid=false; why="TP trop proche"; }
   }

   // Si les stops sont invalides : ouvrir SANS SL/TP puis les poser ensuite (si possible)
   bool deferStops = false;
   if(!stopsValid)
   {
      Print("⚠ Stops invalides (", why, ") — prix marché ", DoubleToString(mktPrice, digits),
            " | min dist ", DoubleToString(minDist, digits),
            ". Ouverture sans SL/TP puis pose différée.");
      deferStops = true;
   }

   // Exécuter au marché
   bool ok = false;
   double useSl = deferStops ? 0.0 : sl;
   double useTp = deferStops ? 0.0 : tp;

   if(action == "BUY")
      ok = trade.Buy(volume, symbol, 0.0, useSl, useTp, "MonWe|" + sigId);
   else if(action == "SELL")
      ok = trade.Sell(volume, symbol, 0.0, useSl, useTp, "MonWe|" + sigId);
   else
   {
      Print("❌ Action inconnue: ", action);
      ConfirmExecution(sigId, 0);
      return;
   }

   if(ok)
   {
      ulong ticket = trade.ResultOrder();
      PrintFormat("✅ Exécuté MARCHÉ: %s %s — Ticket #%d", action, symbol, ticket);
      // Poser les stops après coup si on les avait différés (et qu'ils sont valides en valeur)
      if(deferStops && (sl > 0 || tp > 0))
      {
         if(PositionSelectByTicket(ticket))
         {
            // Re-vérifier la distance avec le prix courant avant de poser
            double curPrice = (action == "BUY") ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(symbol, SYMBOL_ASK);
            double psl = sl, ptp = tp;
            if(action == "BUY")
            {
               if(psl > 0 && (curPrice - psl) < minDist) psl = 0;
               if(ptp > 0 && (ptp - curPrice) < minDist) ptp = 0;
            }
            else
            {
               if(psl > 0 && (psl - curPrice) < minDist) psl = 0;
               if(ptp > 0 && (curPrice - ptp) < minDist) ptp = 0;
            }
            if(psl > 0 || ptp > 0)
            {
               if(trade.PositionModify(ticket, psl, ptp))
                  PrintFormat("  ↳ Stops posés: SL %.5f TP %.5f", psl, ptp);
               else
                  PrintFormat("  ↳ ⚠ Stops non posés (code %d) — position ouverte sans protection complète",
                              trade.ResultRetcode());
            }
            else
            {
               Print("  ↳ ⚠ Stops toujours trop proches — position laissée sans SL/TP. Surveille manuellement.");
            }
         }
      }
      ConfirmExecution(sigId, ticket);
   }
   else
   {
      PrintFormat("❌ Échec MARCHÉ: %s — Code: %d (%s)",
                  symbol, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      ConfirmExecution(sigId, 0);
   }
   return;
   } // fin CAS 1 (marché)

   // ============================================================
   // CAS 2 : ORDRE EN ATTENTE (limite / stop)
   // ============================================================
   // Déterminer le type selon le sens et la position de l'entrée
   ENUM_ORDER_TYPE otype;
   string otypeName;
   if(action == "BUY")
   {
      if(entry < mktPrice) { otype = ORDER_TYPE_BUY_LIMIT; otypeName = "BUY LIMIT"; }
      else                 { otype = ORDER_TYPE_BUY_STOP;  otypeName = "BUY STOP";  }
   }
   else // SELL
   {
      if(entry > mktPrice) { otype = ORDER_TYPE_SELL_LIMIT; otypeName = "SELL LIMIT"; }
      else                 { otype = ORDER_TYPE_SELL_STOP;  otypeName = "SELL STOP";  }
   }

   // Valider SL/TP par rapport à l'ENTRÉE (pas au marché)
   double pSl = sl, pTp = tp;
   if(action == "BUY")
   {
      if(pSl > 0 && (pSl >= entry || (entry - pSl) < minDist)) { Print("⚠ SL pending invalide → retiré"); pSl = 0; }
      if(pTp > 0 && (pTp <= entry || (pTp - entry) < minDist)) { Print("⚠ TP pending invalide → retiré"); pTp = 0; }
   }
   else
   {
      if(pSl > 0 && (pSl <= entry || (pSl - entry) < minDist)) { Print("⚠ SL pending invalide → retiré"); pSl = 0; }
      if(pTp > 0 && (pTp >= entry || (entry - pTp) < minDist)) { Print("⚠ TP pending invalide → retiré"); pTp = 0; }
   }

   // Expiration éventuelle
   ENUM_ORDER_TYPE_TIME tt = ORDER_TIME_GTC;
   datetime expiry = 0;
   if(InpPendingExpiryMin > 0)
   {
      tt = ORDER_TIME_SPECIFIED;
      expiry = TimeCurrent() + InpPendingExpiryMin * 60;
   }

   if(InpVerbose)
      PrintFormat("📌 Ordre %s @ %.5f (SL:%.5f TP:%.5f) marché:%.5f",
                  otypeName, entry, pSl, pTp, mktPrice);

   bool ok = false;
   string cmt = "MonWe|" + sigId;
   switch(otype)
   {
      case ORDER_TYPE_BUY_LIMIT:  ok = trade.BuyLimit (volume, entry, symbol, pSl, pTp, tt, expiry, cmt); break;
      case ORDER_TYPE_BUY_STOP:   ok = trade.BuyStop  (volume, entry, symbol, pSl, pTp, tt, expiry, cmt); break;
      case ORDER_TYPE_SELL_LIMIT: ok = trade.SellLimit(volume, entry, symbol, pSl, pTp, tt, expiry, cmt); break;
      case ORDER_TYPE_SELL_STOP:  ok = trade.SellStop (volume, entry, symbol, pSl, pTp, tt, expiry, cmt); break;
   }

   if(ok)
   {
      ulong ticket = trade.ResultOrder();
      PrintFormat("✅ Ordre placé: %s %s @ %.5f — Ticket #%d", otypeName, symbol, entry, ticket);
      ConfirmExecution(sigId, ticket, "pending");
   }
   else
   {
      PrintFormat("❌ Échec ordre %s: Code: %d (%s)",
                  otypeName, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      ConfirmExecution(sigId, 0);
   }
}

//+------------------------------------------------------------------+
//| Confirme l'exécution à l'API (POST)                             |
//+------------------------------------------------------------------+
void ConfirmExecution(string sigId, ulong ticket, string state="open")
{
   string url = InpApiUrl + "/api/ea-poll";
   string json = "{\"key\":\"" + InpSecret + "\",\"id\":\"" + sigId +
                 "\",\"ticket\":" + IntegerToString((long)ticket) +
                 ",\"account\":\"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\"" +
                 ",\"platform\":\"mt5\"" +
                 ",\"state\":\"" + state + "\"}";

   char   post[];
   char   result[];
   string resultHeaders;
   StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, StringLen(json)); // sans le \0 final

   string headers = "Content-Type: application/json\r\n";

   ResetLastError();
   int code = WebRequest("POST", url, headers, 5000, post, result, resultHeaders);

   if(code == 200)
   {
      if(InpVerbose) Print("✓ Confirmation envoyée (", state, ") pour signal ", sigId);
   }
   else
   {
      Print("⚠ Confirmation échouée (code ", code, ", err ", GetLastError(), ")");
   }
}

//+------------------------------------------------------------------+
//| Signale un changement d'état d'ordre (filled/cancelled) par ticket|
//+------------------------------------------------------------------+
void ReportOrderState(ulong ticket, string state)
{
   string url = InpApiUrl + "/api/ea-poll";
   string json = "{\"key\":\"" + InpSecret + "\"" +
                 ",\"account\":\"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\"" +
                 ",\"ticket\":" + IntegerToString((long)ticket) +
                 ",\"state\":\"" + state + "\"}";

   char   post[];
   char   result[];
   string resultHeaders;
   StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, StringLen(json));

   string headers = "Content-Type: application/json\r\n";
   ResetLastError();
   int code = WebRequest("POST", url, headers, 5000, post, result, resultHeaders);
   if(code == 200)
   {
      if(InpVerbose) Print("✓ État ordre #", ticket, " → ", state);
   }
   else
   {
      Print("⚠ Report état échoué (code ", code, ", err ", GetLastError(), ")");
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Gestion auto des positions ouvertes : Break-Even + Trailing      |
//| Appelée à chaque tick du timer. Ne touche que nos positions.     |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!InpUseBreakEven && !InpUseTrailing) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      // Uniquement nos positions (magic number)
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      string sym   = PositionGetString(POSITION_SYMBOL);
      long   type  = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);

      int    digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double point  = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0) continue;
      long   stopsLvl = SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist  = (double)stopsLvl * point;
      if(minDist <= 0) minDist = 10 * point;

      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

      // Prix "courant" du point de vue de la clôture de la position
      double curPrice = (type == POSITION_TYPE_BUY) ? bid : ask;

      // Profit actuel en points (positif si en gain)
      double profitPts = (type == POSITION_TYPE_BUY)
                         ? (curPrice - open) / point
                         : (open - curPrice) / point;

      double newSL = curSL;  // on part du SL existant

      // ---------- BREAK-EVEN ----------
      if(InpUseBreakEven && profitPts >= InpBE_TriggerPips)
      {
         double beSL = (type == POSITION_TYPE_BUY)
                       ? open + InpBE_LockPips * point
                       : open - InpBE_LockPips * point;
         beSL = NormalizeDouble(beSL, digits);

         // N'avancer le SL que dans le bon sens (jamais reculer)
         if(type == POSITION_TYPE_BUY)
         { if(beSL > newSL || curSL == 0) newSL = beSL; }
         else
         { if(beSL < newSL || curSL == 0) newSL = beSL; }
      }

      // ---------- TRAILING STOP ----------
      if(InpUseTrailing && profitPts >= InpTrail_StartPips)
      {
         double trailSL = (type == POSITION_TYPE_BUY)
                          ? curPrice - InpTrail_DistPips * point
                          : curPrice + InpTrail_DistPips * point;
         trailSL = NormalizeDouble(trailSL, digits);

         // Ne déplacer que si gain de InpTrail_StepPips minimum, et toujours dans le bon sens
         if(type == POSITION_TYPE_BUY)
         {
            if(trailSL > newSL + InpTrail_StepPips * point || newSL == 0)
               newSL = trailSL;
         }
         else
         {
            if(trailSL < newSL - InpTrail_StepPips * point || newSL == 0)
               newSL = trailSL;
         }
      }

      // ---------- APPLIQUER si changement valide ----------
      if(newSL != curSL && newSL > 0)
      {
         // Respecter la distance minimale du broker
         bool distOk = (type == POSITION_TYPE_BUY)
                       ? (curPrice - newSL) >= minDist
                       : (newSL - curPrice) >= minDist;
         if(distOk)
         {
            if(trade.PositionModify(ticket, newSL, curTP))
            {
               if(InpVerbose)
                  PrintFormat("🔧 SL ajusté #%d %s: %.5f → %.5f (profit %.0f pts)",
                              ticket, sym, curSL, newSL, profitPts);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Détection automatique des fermetures de position                |
//| Se déclenche quand une position se ferme (TP, SL ou manuel)     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   // --- Annulation / expiration d'un ordre en attente ---
   if(trans.type == TRADE_TRANSACTION_ORDER_DELETE)
   {
      ulong ord = trans.order;
      if(ord > 0 && HistoryOrderSelect(ord))
      {
         long omagic = HistoryOrderGetInteger(ord, ORDER_MAGIC);
         long ostate = HistoryOrderGetInteger(ord, ORDER_STATE);
         if(omagic == InpMagic &&
            (ostate == ORDER_STATE_CANCELED || ostate == ORDER_STATE_EXPIRED || ostate == ORDER_STATE_REJECTED))
         {
            ReportOrderState(ord, "cancelled");
         }
      }
      return;
   }

   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket <= 0) return;
   if(!HistoryDealSelect(dealTicket)) return;

   long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(magic != InpMagic) return;

   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);

   // --- Entrée en position (ordre exécuté OU pending déclenché) ---
   if(entry == DEAL_ENTRY_IN)
   {
      ulong posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      // Passe la ligne d'exécution de "pending" à "open" (les marchés sont déjà "open")
      ReportOrderState(posId, "filled");
      return;
   }

   // --- Sortie de position (clôture) ---
   if(entry == DEAL_ENTRY_OUT)
   {
      ulong  posId  = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      double price  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap   = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double comm   = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double net    = profit + swap + comm;
      ReportClose(posId, price, net);
   }
}

//+------------------------------------------------------------------+
//| Envoie la fermeture à l'API (POST /api/ea-close)                |
//+------------------------------------------------------------------+
void ReportClose(ulong ticket, double closePrice, double profit)
{
   string url = InpApiUrl + "/api/ea-close";
   string json = "{\"key\":\"" + InpSecret + "\""
               + ",\"account\":\"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\""
               + ",\"ticket\":" + IntegerToString((long)ticket)
               + ",\"close_price\":" + DoubleToString(closePrice, 5)
               + ",\"profit\":" + DoubleToString(profit, 2) + "}";

   char   post[];
   char   res[];
   string resHeaders;
   StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, StringLen(json));

   string headers = "Content-Type: application/json\r\n";

   ResetLastError();
   int code = WebRequest("POST", url, headers, 5000, post, res, resHeaders);
   if(code == 200)
   {
      if(InpVerbose) PrintFormat("✓ Fermeture signalée: ticket #%d profit %.2f", ticket, profit);
   }
   else
   {
      Print("⚠ Report fermeture échoué (code ", code, ", err ", GetLastError(), ")");
   }
}
//+------------------------------------------------------------------+
