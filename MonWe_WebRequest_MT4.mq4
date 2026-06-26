//+------------------------------------------------------------------+
//|                              MonWe_WebRequest_MT4.mq4             |
//|                              MonWe Infinity LLC                   |
//|        Récupère les signaux depuis Vercel via WebRequest         |
//+------------------------------------------------------------------+
#property copyright "MonWe Infinity LLC"
#property link      "https://telegram-mt5-trader.vercel.app"
#property version   "1.00"
#property strict
#property description "Récupère les signaux validés depuis l'API Vercel et les exécute sur MT4"

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

//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== MonWe WebRequest EA (MT4) démarré ===");
   Print("API: ", InpApiUrl);
   Print("Polling: toutes les ", InpPollSeconds, "s");
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
   CheckClosedTrades();
}

//+------------------------------------------------------------------+
//| Interroge l'API Vercel pour les signaux en attente              |
//+------------------------------------------------------------------+
void PollSignals()
{
   string url = InpApiUrl + "/api/ea-poll?key=" + InpSecret + "&platform=mt4"
                + "&account=" + IntegerToString(AccountNumber());

   char   post[];
   char   result[];
   string resultHeaders;
   int    timeout = 5000;

   ResetLastError();
   int code = WebRequest("GET", url, "", "", timeout, post, 0, result, resultHeaders);

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
      return;

   if(response == "UNAUTHORIZED")
   {
      Print("❌ Secret invalide. Vérifiez InpSecret = TELEGRAM_SECRET");
      return;
   }

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
//| Vérifie si le symbole (brut) est dans la liste autorisée         |
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

      if(up == a) return true;
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
      ConfirmExecution(sigId, 0);
      return;
   }

   // Adapter le symbole au broker (Exness: XAUUSD -> XAUUSDc)
   symbol = InpSymbolPrefix + symbol + InpSymbolSuffix;

   if(volume > InpMaxVolume)
   {
      Print("⚠ Volume ", volume, " > max ", InpMaxVolume, " — plafonné");
      volume = InpMaxVolume;
   }

   if(InpVerbose)
      PrintFormat("📥 Signal: %s %s @ %.5f (SL:%.5f TP:%.5f Vol:%.2f)",
                  action, symbol, entry, sl, tp, volume);

   // Normaliser le volume aux contraintes du broker
   double minLot  = MarketInfo(symbol, MODE_MINLOT);
   double maxLot  = MarketInfo(symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
   if(volume < minLot) volume = minLot;
   if(volume > maxLot) volume = maxLot;
   if(lotStep > 0) volume = MathRound(volume / lotStep) * lotStep;

   int    digits = (int)MarketInfo(symbol, MODE_DIGITS);
   double price  = 0;
   int    type   = -1;

   if(action == "BUY")
   {
      type  = OP_BUY;
      price = MarketInfo(symbol, MODE_ASK);
   }
   else if(action == "SELL")
   {
      type  = OP_SELL;
      price = MarketInfo(symbol, MODE_BID);
   }
   else
   {
      Print("❌ Action inconnue: ", action);
      return;
   }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   int ticket = OrderSend(symbol, type, volume, NormalizeDouble(price, digits),
                          InpSlippage, sl, tp, "MonWe|" + sigId, InpMagic, 0,
                          (type == OP_BUY) ? clrBlue : clrRed);

   if(ticket > 0)
   {
      PrintFormat("✅ Exécuté: %s %s — Ticket #%d", action, symbol, ticket);
      ConfirmExecution(sigId, ticket);
   }
   else
   {
      PrintFormat("❌ Échec: %s — Code erreur: %d", symbol, GetLastError());
      ConfirmExecution(sigId, 0);
   }
}

//+------------------------------------------------------------------+
//| Confirme l'exécution à l'API (POST)                             |
//+------------------------------------------------------------------+
void ConfirmExecution(string sigId, int ticket)
{
   string url = InpApiUrl + "/api/ea-poll";
   string json = "{\"key\":\"" + InpSecret + "\",\"id\":\"" + sigId +
                 "\",\"ticket\":" + IntegerToString(ticket) +
                 ",\"account\":\"" + IntegerToString(AccountNumber()) + "\"" +
                 ",\"platform\":\"mt4\"}";

   char   post[];
   char   result[];
   string resultHeaders;
   int len = StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, len - 1); // retirer le \0 final

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
//| Détection automatique des fermetures (MT4 = polling)            |
//| Garde la liste des tickets ouverts ; si un ticket disparaît     |
//| des positions ouvertes, on le cherche dans l'historique.        |
//+------------------------------------------------------------------+
int    g_openTickets[];   // tickets actuellement ouverts (gérés par cet EA)

void CheckClosedTrades()
{
   // 1) Construire la liste des tickets ouverts MAINTENANT (par magic)
   int current[];
   int cnt = 0;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      ArrayResize(current, cnt + 1);
      current[cnt] = OrderTicket();
      cnt++;
   }

   // 2) Pour chaque ticket connu précédemment mais absent maintenant -> fermé
   int prevN = ArraySize(g_openTickets);
   for(int p = 0; p < prevN; p++)
   {
      int t = g_openTickets[p];
      bool stillOpen = false;
      for(int c = 0; c < cnt; c++)
         if(current[c] == t) { stillOpen = true; break; }

      if(!stillOpen)
      {
         // Retrouver l'ordre fermé dans l'historique
         if(OrderSelect(t, SELECT_BY_TICKET, MODE_HISTORY))
         {
            if(OrderMagicNumber() == InpMagic && OrderCloseTime() > 0)
            {
               double net = OrderProfit() + OrderSwap() + OrderCommission();
               ReportClose(t, OrderClosePrice(), net);
            }
         }
      }
   }

   // 3) Mémoriser la liste courante pour le prochain tick
   ArrayResize(g_openTickets, cnt);
   for(int k = 0; k < cnt; k++) g_openTickets[k] = current[k];
}

//+------------------------------------------------------------------+
//| Envoie la fermeture à l'API (POST /api/ea-close)                |
//+------------------------------------------------------------------+
void ReportClose(int ticket, double closePrice, double profit)
{
   string url = InpApiUrl + "/api/ea-close";
   string json = "{\"key\":\"" + InpSecret + "\""
               + ",\"account\":\"" + IntegerToString(AccountNumber()) + "\""
               + ",\"ticket\":" + IntegerToString(ticket)
               + ",\"close_price\":" + DoubleToString(closePrice, 5)
               + ",\"profit\":" + DoubleToString(profit, 2) + "}";

   char   post[];
   char   res[];
   string resHeaders;
   int len = StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, len - 1);

   string headers = "Content-Type: application/json\r\n";

   ResetLastError();
   int code = WebRequest("POST", url, headers, 5000, post, res, resHeaders);
   if(code == 200)
   {
      if(InpVerbose) Print("✓ Fermeture signalée: ticket #", ticket, " profit ", DoubleToString(profit, 2));
   }
   else
   {
      Print("⚠ Report fermeture échoué (code ", code, ", err ", GetLastError(), ")");
   }
}
//+------------------------------------------------------------------+
