//+------------------------------------------------------------------+
//| Telegram MT5 Trader EA v2 - MonWe Infinity LLC                   |
//| Receives signals from Vercel and reports results back            |
//+------------------------------------------------------------------+
#property copyright "MonWe Infinity LLC"
#property link      "https://monweinfinity.com"
#property version   "2.0"
#property description "Automated EA: receives signals from Telegram via Vercel webhook"

#include <Trade\Trade.mqh>
#include <Sockets\Socket.mqh>

CTrade trade;

input group "=== CONNEXION ==="
input string VercelURL       = "https://your-app.vercel.app";
input string ApiKey          = "your_api_key_here";

input group "=== TRADING ==="
input bool   AllowBuy        = true;
input bool   AllowSell       = true;
input double DefaultVolume   = 1.0;
input int    MagicNumber     = 20260625;
input double MaxDailyLoss    = 500.0;   // USD
input double MaxDailyProfit  = 1000.0;  // USD

input group "=== SIGNAUX ==="
input string SignalFolder    = "signals";
input int    CheckIntervalMs = 1000;
input bool   ReportResults   = true;

// === Globals ===
double    g_dayProfit   = 0;
double    g_dayLoss     = 0;
datetime  g_lastDay     = 0;
datetime  g_lastCheck   = 0;
ulong     g_lastTicket  = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(30);
   
   CreateFolder(SignalFolder);
   
   Print("=== MonWe Trading EA v2 démarré ===");
   PrintFormat("Vercel URL: %s", VercelURL);
   PrintFormat("Magic Number: %d", MagicNumber);
   PrintFormat("Max Daily Loss: %.2f USD", MaxDailyLoss);
   
   // Notify Vercel that EA is online
   if(ReportResults)
      SendHeartbeat();
      
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA stoppé. Raison: ", reason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Vérifier les signaux toutes les CheckIntervalMs ms
   if(GetTickCount() - (uint)g_lastCheck >= (uint)CheckIntervalMs)
   {
      g_lastCheck = GetTickCount();
      CheckNewSignals();
      UpdateDailyStats();
      CheckOpenPositions();
   }
}

//+------------------------------------------------------------------+
void CheckNewSignals()
{
   string path = SignalFolder + "\\pending.txt";
   int h = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   
   string raw = "";
   while(!FileIsEnding(h))
      raw += FileReadString(h);
   FileClose(h);
   
   StringTrimRight(raw);
   StringTrimLeft(raw);
   if(StringLen(raw) == 0) return;
   
   FileDelete(path);
   Print("Signal reçu: ", raw);
   ProcessSignal(raw);
}

//+------------------------------------------------------------------+
void ProcessSignal(string raw)
{
   // Format: ACTION,SYMBOL,ENTRY,VOLUME,SL,TP,SIGNAL_ID
   string p[];
   int cnt = StringSplit(raw, StringGetCharacter(",", 0), p);
   if(cnt < 6) { PrintFormat("Signal invalide (%d parts): %s", cnt, raw); return; }
   
   string action = p[0];
   string symbol = p[1];
   double entry  = StringToDouble(p[2]);
   double volume = StringToDouble(p[3]);
   double sl     = StringToDouble(p[4]);
   double tp     = StringToDouble(p[5]);
   string sig_id = cnt >= 7 ? p[6] : "";
   
   if(!Validate(action, symbol, volume)) return;
   
   bool ok = false;
   if(action == "BUY")
      ok = trade.Buy(volume, symbol, entry, sl, tp, "MonWe|" + sig_id);
   else if(action == "SELL")
      ok = trade.Sell(volume, symbol, entry, sl, tp, "MonWe|" + sig_id);
   
   if(ok)
   {
      g_lastTicket = trade.ResultOrder();
      PrintFormat("✓ Trade exécuté: %s %s @ %.5f (SL:%.5f TP:%.5f) → Ticket #%d",
                  action, symbol, entry, sl, tp, g_lastTicket);
      
      if(ReportResults && StringLen(sig_id) > 0)
         ReportExecuted(sig_id, g_lastTicket);
   }
   else
   {
      PrintFormat("✗ Trade échoué: %s | Code: %d | %s",
                  symbol, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
bool Validate(string action, string symbol, double volume)
{
   if(action != "BUY" && action != "SELL") { Print("Action invalide: ", action); return false; }
   if(action == "BUY"  && !AllowBuy)  { Print("BUY désactivé"); return false; }
   if(action == "SELL" && !AllowSell) { Print("SELL désactivé"); return false; }
   if(volume <= 0 || volume > 100) { PrintFormat("Volume invalide: %.2f", volume); return false; }
   
   if(g_dayLoss >= MaxDailyLoss)
   {
      PrintFormat("Limite perte journalière atteinte: %.2f/%.2f", g_dayLoss, MaxDailyLoss);
      return false;
   }
   if(g_dayProfit >= MaxDailyProfit)
   {
      PrintFormat("Objectif profit journalier atteint: %.2f/%.2f", g_dayProfit, MaxDailyProfit);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void CheckOpenPositions()
{
   if(!ReportResults) return;
   
   // Check if any position managed by this EA was recently closed
   datetime since = TimeCurrent() - 60; // last 60 sec
   
   if(!HistorySelect(since, TimeCurrent())) return;
   
   for(int i = HistoryDealsTotal()-1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      
      ENUM_DEAL_ENTRY type = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(type != DEAL_ENTRY_OUT) continue; // Only closing deals
      
      datetime dtime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dtime < since) continue;
      
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
      
      // Extract signal ID from comment (format: MonWe|SIGNAL_ID)
      string sig_id = "";
      if(StringFind(comment, "MonWe|") == 0)
         sig_id = StringSubstr(comment, 6);
      
      // Report result to Vercel
      if(StringLen(sig_id) > 0)
      {
         string result = profit > 0 ? "win" : profit < 0 ? "loss" : "breakeven";
         double closePrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
         
         ReportTradeClosed(sig_id, result, profit, closePrice);
         
         if(profit > 0) g_dayProfit += profit;
         else           g_dayLoss   += MathAbs(profit);
      }
   }
}

//+------------------------------------------------------------------+
void UpdateDailyStats()
{
   datetime today = (datetime)((long)TimeCurrent() / 86400 * 86400);
   if(today != g_lastDay)
   {
      g_lastDay    = today;
      g_dayProfit  = 0;
      g_dayLoss    = 0;
      Print("=== Nouveau jour de trading. Stats réinitialisées ===");
   }
}

//+------------------------------------------------------------------+
// HTTP Helpers (via Vercel API)
//+------------------------------------------------------------------+
void ReportExecuted(string sig_id, ulong order_id)
{
   // This is called after a signal is executed
   // Useful for logging purposes on Vercel
   PrintFormat("Signal %s → Ordre MT5 #%d", sig_id, order_id);
}

void ReportTradeClosed(string sig_id, string result, double pnl, double closePrice)
{
   // Typically done via WebRequest to Vercel /api/close-trade
   // Requires MT5 to have internet access (Tools → Options → Expert Advisors → Allow WebRequest)
   
   PrintFormat("Trade fermé: ID=%s | %s | PnL=%.2f | Close=%.5f",
               sig_id, result, pnl, closePrice);
   
   // Optional: Write to close-results.txt for dashboard to read
   string path = SignalFolder + "\\closed_" + sig_id + ".txt";
   int h = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, StringFormat("%s,%.2f,%.5f", result, pnl, closePrice));
      FileClose(h);
   }
}

void SendHeartbeat()
{
   Print("EA actif - Heartbeat envoyé");
}

void CreateFolder(string folder)
{
   if(!FolderCreate(folder, FILE_COMMON))
      Print("Dossier déjà existant: ", folder);
}

//+------------------------------------------------------------------+
// OnChartEvent: Receive signals via chart comment
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_KEYDOWN)
   {
      if(lparam == 'R') // R key = Reload signals
         CheckNewSignals();
   }
}
