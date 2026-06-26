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
input string  InpApiUrl      = "https://telegram-mt5-trader.vercel.app"; // URL de base Vercel
input string  InpSecret      = "VOTRE_SECRET_ICI";  // TELEGRAM_SECRET (identique à Vercel)
input int     InpPollSeconds = 5;                   // Fréquence de vérification (secondes)
input double  InpMaxVolume   = 1.0;                 // Volume max autorisé (sécurité)
input int     InpSlippage    = 30;                  // Slippage max (points)
input int     InpMagic       = 20260626;            // Magic number
input string  InpSymbolPrefix = "";                 // Préfixe symbole broker (souvent vide)
input string  InpSymbolSuffix = "c";                // Suffixe symbole broker (Exness = "c")
input string  InpAllowedSymbols = "";               // Symboles autorisés (vide = TOUS). Ex: XAUUSD,BTCUSD
input bool    InpVerbose     = true;                // Journaux détaillés

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

   // Adapter le symbole au broker (Exness: XAUUSD -> XAUUSDc)
   symbol = InpSymbolPrefix + symbol + InpSymbolSuffix;

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
      return;
   }

   // Exécuter au marché
   bool ok = false;
   if(action == "BUY")
      ok = trade.Buy(volume, symbol, 0.0, sl, tp, "MonWe|" + sigId);
   else if(action == "SELL")
      ok = trade.Sell(volume, symbol, 0.0, sl, tp, "MonWe|" + sigId);
   else
   {
      Print("❌ Action inconnue: ", action);
      return;
   }

   if(ok)
   {
      ulong ticket = trade.ResultOrder();
      PrintFormat("✅ Exécuté: %s %s — Ticket #%d", action, symbol, ticket);
      ConfirmExecution(sigId, ticket);
   }
   else
   {
      PrintFormat("❌ Échec: %s — Code: %d (%s)",
                  symbol, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      // On confirme quand même pour ne pas re-traiter en boucle
      ConfirmExecution(sigId, 0);
   }
}

//+------------------------------------------------------------------+
//| Confirme l'exécution à l'API (POST)                             |
//+------------------------------------------------------------------+
void ConfirmExecution(string sigId, ulong ticket)
{
   string url = InpApiUrl + "/api/ea-poll";
   string json = "{\"key\":\"" + InpSecret + "\",\"id\":\"" + sigId +
                 "\",\"ticket\":" + IntegerToString((long)ticket) +
                 ",\"account\":\"" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\"" +
                 ",\"platform\":\"mt5\"}";

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
      if(InpVerbose) Print("✓ Confirmation envoyée pour signal ", sigId);
   }
   else
   {
      Print("⚠ Confirmation échouée (code ", code, ", err ", GetLastError(), ")");
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Détection automatique des fermetures de position                |
//| Se déclenche quand une position se ferme (TP, SL ou manuel)     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket <= 0) return;
   if(!HistoryDealSelect(dealTicket)) return;

   // Uniquement les sorties de position (clôtures)
   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT) return;

   // Uniquement nos trades (magic number)
   long magic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(magic != InpMagic) return;

   ulong  posId  = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   double price  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double swap   = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double comm   = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double net    = profit + swap + comm;

   ReportClose(posId, price, net);
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
