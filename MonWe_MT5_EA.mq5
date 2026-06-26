//+------------------------------------------------------------------+
//|                                          MonWe_MT5_EA.mq5         |
//|                                      MonWe Infinity LLC           |
//|         Récupère les signaux depuis Vercel et les exécute        |
//+------------------------------------------------------------------+
#property copyright "MonWe Infinity LLC"
#property link      "https://monweinfinity.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

//--- Paramètres d'entrée
input string ServerURL   = "https://telegram-mt5-trader.vercel.app"; // URL Vercel (sans / final)
input string SecretKey   = "";          // Ton TELEGRAM_SECRET (identique à Vercel)
input int    PollSeconds = 3;           // Fréquence de vérification (secondes)
input int    MagicNumber = 20260626;    // Identifiant des trades de cet EA
input bool   AllowBuy    = true;
input bool   AllowSell   = true;
input double MaxVolume   = 10.0;        // Volume max autorisé (sécurité)

datetime g_lastPoll = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);

   Print("=== MonWe MT5 EA démarré ===");
   Print("Server: ", ServerURL);

   if(StringLen(SecretKey) == 0)
      Print("⚠ ATTENTION: SecretKey vide ! Renseigne ton TELEGRAM_SECRET.");

   // Rappel: autoriser l'URL dans Outils > Options > Expert Advisors > WebRequest
   Print("⚠ Vérifie que l'URL est autorisée dans Outils>Options>Expert Advisors");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { Print("MonWe MT5 EA arrêté."); }

//+------------------------------------------------------------------+
void OnTick()
{
   if(TimeCurrent() - g_lastPoll < PollSeconds) return;
   g_lastPoll = TimeCurrent();
   PollSignals();
}

//+------------------------------------------------------------------+
//| Interroge l'API et exécute les signaux reçus                     |
//+------------------------------------------------------------------+
void PollSignals()
{
   string url = ServerURL + "/api/ea-poll?key=" + SecretKey + "&platform=mt5";
   char   post[];
   char   result[];
   string headers;
   string resultHeaders;

   ResetLastError();
   int timeout = 5000;
   int code = WebRequest("GET", url, "", timeout, post, result, resultHeaders);

   if(code == -1)
   {
      int err = GetLastError();
      if(err == 4060)
         Print("⚠ URL non autorisée. Ajoute ", ServerURL, " dans Outils>Options>Expert Advisors>WebRequest");
      else
         Print("Erreur WebRequest: ", err);
      return;
   }

   string response = CharArrayToString(result);
   StringTrimLeft(response);
   StringTrimRight(response);

   if(response == "NONE" || response == "")  return;       // pas de signal
   if(response == "UNAUTHORIZED") { Print("⚠ Clé invalide (SecretKey)"); return; }
   if(response == "ERROR")        { Print("⚠ Erreur serveur"); return; }

   // Plusieurs signaux possibles, séparés par \n
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
//| Parse et exécute une ligne : ID;ACTION;SYMBOL;ENTRY;VOL;SL;TP    |
//+------------------------------------------------------------------+
void ProcessSignal(string line)
{
   string p[];
   int cnt = StringSplit(line, ';', p);
   if(cnt < 7) { Print("Ligne invalide: ", line); return; }

   string id     = p[0];
   string action = p[1];
   string symbol = p[2];
   double entry  = StringToDouble(p[3]);
   double volume = StringToDouble(p[4]);
   double sl     = StringToDouble(p[5]);
   double tp     = StringToDouble(p[6]);

   // Sécurités
   if(volume <= 0 || volume > MaxVolume) { Print("Volume refusé: ", volume); return; }
   if(action == "BUY"  && !AllowBuy)  { Print("BUY désactivé");  return; }
   if(action == "SELL" && !AllowSell) { Print("SELL désactivé"); return; }

   if(!SymbolSelect(symbol, true)) { Print("Symbole indisponible: ", symbol); return; }

   bool ok = false;
   if(action == "BUY")
      ok = trade.Buy(volume, symbol, 0, sl, tp, "MonWe");   // 0 = prix marché
   else if(action == "SELL")
      ok = trade.Sell(volume, symbol, 0, sl, tp, "MonWe");

   if(ok)
   {
      ulong ticket = trade.ResultOrder();
      PrintFormat("✓ %s %s %.2f lots → ticket #%I64u", action, symbol, volume, ticket);
      ConfirmExecution(id, (long)ticket);
   }
   else
   {
      PrintFormat("✗ Échec %s %s: %s", action, symbol, trade.ResultRetcodeDescription());
      ConfirmExecution(id, 0); // confirme quand même pour ne pas reboucler
   }
}

//+------------------------------------------------------------------+
//| Confirme au serveur que le signal a été pris (avec le ticket)    |
//+------------------------------------------------------------------+
void ConfirmExecution(string id, long ticket)
{
   string url  = ServerURL + "/api/ea-poll";
   string body = "{\"key\":\"" + SecretKey + "\",\"id\":\"" + id + "\",\"ticket\":" + IntegerToString(ticket) + "}";

   char post[]; StringToCharArray(body, post, 0, StringLen(body));
   char result[];
   string resultHeaders;
   string headers = "Content-Type: application/json\r\n";

   ResetLastError();
   int code = WebRequest("POST", url, headers, 5000, post, result, resultHeaders);
   if(code == -1)
      Print("⚠ Confirmation échouée (err ", GetLastError(), ") pour ", id);
}
//+------------------------------------------------------------------+
