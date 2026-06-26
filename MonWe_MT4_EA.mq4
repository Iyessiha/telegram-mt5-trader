//+------------------------------------------------------------------+
//|                                          MonWe_MT4_EA.mq4         |
//|                                      MonWe Infinity LLC           |
//|         Récupère les signaux depuis Vercel et les exécute        |
//+------------------------------------------------------------------+
#property copyright "MonWe Infinity LLC"
#property link      "https://monweinfinity.com"
#property version   "1.00"
#property strict

//--- Paramètres d'entrée
input string ServerURL   = "https://telegram-mt5-trader.vercel.app"; // URL Vercel (sans / final)
input string SecretKey   = "";          // Ton TELEGRAM_SECRET (identique à Vercel)
input int    PollSeconds = 3;
input int    MagicNumber = 20260626;
input bool   AllowBuy    = true;
input bool   AllowSell   = true;
input double MaxVolume    = 10.0;
input int    SlippagePts = 30;

datetime g_lastPoll = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== MonWe MT4 EA démarré ===");
   Print("Server: ", ServerURL);
   if(StringLen(SecretKey) == 0)
      Print("⚠ ATTENTION: SecretKey vide ! Renseigne ton TELEGRAM_SECRET.");
   Print("⚠ Autorise l'URL dans Outils>Options>Expert Advisors>WebRequest");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { Print("MonWe MT4 EA arrêté."); }

//+------------------------------------------------------------------+
void OnTick()
{
   if(TimeCurrent() - g_lastPoll < PollSeconds) return;
   g_lastPoll = TimeCurrent();
   PollSignals();
}

//+------------------------------------------------------------------+
void PollSignals()
{
   string url = ServerURL + "/api/ea-poll?key=" + SecretKey + "&platform=mt4";
   char   post[];
   char   result[];
   string resultHeaders;

   ResetLastError();
   int code = WebRequest("GET", url, "", "", 5000, post, 0, result, resultHeaders);

   if(code == -1)
   {
      int err = GetLastError();
      if(err == 4060)
         Print("⚠ URL non autorisée. Ajoute ", ServerURL, " dans Outils>Options>Expert Advisors");
      else
         Print("Erreur WebRequest: ", err);
      return;
   }

   string response = CharArrayToString(result);
   StringTrimLeft(response); StringTrimRight(response);

   if(response == "NONE" || response == "") return;
   if(response == "UNAUTHORIZED") { Print("⚠ Clé invalide (SecretKey)"); return; }
   if(response == "ERROR")        { Print("⚠ Erreur serveur"); return; }

   string lines[];
   int n = StringSplit(response, '\n', lines);
   for(int i = 0; i < n; i++)
   {
      string line = lines[i];
      StringTrimLeft(line); StringTrimRight(line);
      if(StringLen(line) > 0)
         ProcessSignal(line);
   }
}

//+------------------------------------------------------------------+
//| Parse et exécute : ID;ACTION;SYMBOL;ENTRY;VOL;SL;TP              |
//+------------------------------------------------------------------+
void ProcessSignal(string line)
{
   string p[];
   int cnt = StringSplit(line, ';', p);
   if(cnt < 7) { Print("Ligne invalide: ", line); return; }

   string id     = p[0];
   string action = p[1];
   string symbol = p[2];
   double sl     = StrToDouble(p[5]);
   double tp     = StrToDouble(p[6]);
   double volume = StrToDouble(p[4]);

   if(volume <= 0 || volume > MaxVolume) { Print("Volume refusé: ", volume); return; }
   if(action == "BUY"  && !AllowBuy)  { Print("BUY désactivé");  return; }
   if(action == "SELL" && !AllowSell) { Print("SELL désactivé"); return; }

   double price;
   int    type;
   color  arrow;

   if(action == "BUY")  { type = OP_BUY;  price = MarketInfo(symbol, MODE_ASK); arrow = clrBlue; }
   else                 { type = OP_SELL; price = MarketInfo(symbol, MODE_BID); arrow = clrRed;  }

   int ticket = OrderSend(symbol, type, volume, price, SlippagePts, sl, tp, "MonWe", MagicNumber, 0, arrow);

   if(ticket > 0)
   {
      PrintFormat("✓ %s %s %.2f lots → ticket #%d", action, symbol, volume, ticket);
      ConfirmExecution(id, ticket);
   }
   else
   {
      PrintFormat("✗ Échec %s %s: erreur %d", action, symbol, GetLastError());
      ConfirmExecution(id, 0);
   }
}

//+------------------------------------------------------------------+
void ConfirmExecution(string id, int ticket)
{
   string url  = ServerURL + "/api/ea-poll";
   string body = "{\"key\":\"" + SecretKey + "\",\"id\":\"" + id + "\",\"ticket\":" + IntegerToString(ticket) + "}";

   char post[]; StringToCharArray(body, post, 0, StringLen(body));
   char result[];
   string resultHeaders;
   string headers = "Content-Type: application/json\r\n";

   ResetLastError();
   int code = WebRequest("POST", url, headers, "", 5000, post, ArraySize(post), result, resultHeaders);
   if(code == -1)
      Print("⚠ Confirmation échouée (err ", GetLastError(), ") pour ", id);
}
//+------------------------------------------------------------------+
