//+------------------------------------------------------------------+
//| Telegram MT5 Trader EA                                           |
//| Receives trading signals and executes orders on MT5              |
//+------------------------------------------------------------------+
#property copyright "MonWe Infinity LLC"
#property link      "https://monweinfinity.com"
#property version   "1.0"
#property strict
#property description "Automated trading EA that receives signals from Telegram via webhook"

#include <Trade\Trade.mqh>

CTrade trade;

// Input parameters
input string WebhookURL = "https://your-app.vercel.app/api/telegram-webhook";
input string ApiKey = "your_api_key";
input bool AllowBuy = true;
input bool AllowSell = true;
input double DefaultVolume = 1.0;
input int MagicNumber = 20260625;
input string SymbolFilter = "";
input double MaxDailyDrawdown = 1000.0;
input int SignalCheckInterval = 1; // seconds

// Global variables
datetime lastSignalCheck = 0;
double dailyLoss = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set default magic number
   trade.SetMagicNumber(MagicNumber);
   
   // Initialize
   PrintFormat("EA started on %s", Symbol());
   Print("Telegram MT5 Trader EA initialized");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA stopped");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check for signals at regular intervals
   if(TimeCurrent() - lastSignalCheck >= SignalCheckInterval)
   {
      CheckForSignals();
      lastSignalCheck = TimeCurrent();
   }
   
   // Update daily PnL
   UpdateDailyPnL();
}

//+------------------------------------------------------------------+
//| Check for pending signals                                        |
//+------------------------------------------------------------------+
void CheckForSignals()
{
   // Method 1: Check for signal files
   CheckFileSignals();
   
   // Method 2: HTTP request (if implemented)
   // CheckWebhookSignals();
}

//+------------------------------------------------------------------+
//| Check file-based signals                                         |
//+------------------------------------------------------------------+
void CheckFileSignals()
{
   string signalFile = "signals.txt";
   
   // Check if signal file exists
   int handle = FileOpen(signalFile, FILE_READ | FILE_TXT | FILE_ANSI);
   
   if(handle != INVALID_HANDLE)
   {
      // Read signal from file
      string signal = FileReadString(handle);
      FileClose(handle);
      
      if(signal != "")
      {
         ProcessSignal(signal);
         
         // Delete processed signal
         FileDelete(signalFile);
      }
   }
}

//+------------------------------------------------------------------+
//| Process trading signal                                           |
//+------------------------------------------------------------------+
void ProcessSignal(string signal)
{
   Print("Processing signal: " + signal);
   
   // Parse signal format: "BUY,XAUUSD,2650,1.05,2640,2660"
   // Format: ACTION,SYMBOL,ENTRY,VOLUME,SL,TP
   
   string parts[];
   int count = StringSplit(signal, ',', parts);
   
   if(count < 6)
   {
      PrintFormat("Invalid signal format: %s", signal);
      return;
   }
   
   string action = parts[0];
   string symbol = parts[1];
   double entry = StringToDouble(parts[2]);
   double volume = StringToDouble(parts[3]);
   double sl = StringToDouble(parts[4]);
   double tp = StringToDouble(parts[5]);
   
   // Validate signal
   if(!ValidateSignal(action, symbol, entry, volume, sl, tp))
   {
      return;
   }
   
   // Execute trade
   ExecuteTrade(action, symbol, entry, volume, sl, tp);
}

//+------------------------------------------------------------------+
//| Validate signal                                                   |
//+------------------------------------------------------------------+
bool ValidateSignal(const string action, const string symbol, double entry,
                    double volume, double sl, double tp)
{
   // Check action
   if(action != "BUY" && action != "SELL")
   {
      Print("Invalid action: " + action);
      return false;
   }
   
   // Check if trading allowed for this symbol
   if(SymbolFilter != "" && symbol != Symbol())
   {
      PrintFormat("Symbol %s filtered out (filter: %s)", symbol, SymbolFilter);
      return false;
   }
   
   // Check volume
   if(volume <= 0 || volume > 100)
   {
      PrintFormat("Invalid volume: %.2f", volume);
      return false;
   }
   
   // Check daily drawdown limit
   if(dailyLoss > MaxDailyDrawdown)
   {
      PrintFormat("Daily loss limit exceeded: %.2f / %.2f", dailyLoss, MaxDailyDrawdown);
      return false;
   }
   
   // Check buy/sell allowed
   if(action == "BUY" && !AllowBuy)
   {
      Print("Buy orders disabled");
      return false;
   }
   
   if(action == "SELL" && !AllowSell)
   {
      Print("Sell orders disabled");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Execute trade                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(const string action, const string symbol, double entry,
                  double volume, double sl, double tp)
{
   if(!SymbolSelect(symbol, true))
   {
      PrintFormat("Cannot select symbol: %s", symbol);
      return;
   }
   
   MqlTick tick;
   SymbolInfoTick(symbol, tick);
   
   bool success = false;
   
   if(action == "BUY")
   {
      success = trade.Buy(volume, symbol, entry, sl, tp);
   }
   else if(action == "SELL")
   {
      success = trade.Sell(volume, symbol, entry, sl, tp);
   }
   
   if(success)
   {
      PrintFormat("✓ Trade executed: %s %s @ %.5f (SL: %.5f, TP: %.5f)",
                  action, symbol, entry, sl, tp);
      Print("Order ID: " + IntegerToString(trade.ResultOrder()));
   }
   else
   {
      PrintFormat("✗ Trade failed: %s. Error: %s",
                  symbol, trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Update daily PnL                                                  |
//+------------------------------------------------------------------+
void UpdateDailyPnL()
{
   static datetime lastDate = 0;
   datetime currentDate = (datetime)(TimeCurrent() / 86400 * 86400);
   
   // Reset daily loss at start of new day
   if(currentDate != lastDate)
   {
      lastDate = currentDate;
      dailyLoss = 0;
   }
   
   // Calculate today's loss from closed positions
   double todayPnL = 0;
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;
      
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      
      if(dealTime >= lastDate)
      {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if(profit < 0)
            todayPnL += profit;
      }
   }
   
   dailyLoss = MathAbs(todayPnL);
}

//+------------------------------------------------------------------+
//| Helper: String to Double                                         |
//+------------------------------------------------------------------+
double StringToDouble(const string value)
{
   return StringToDouble(value);
}

//+------------------------------------------------------------------+
//| Helper: String Split                                             |
//+------------------------------------------------------------------+
int StringSplit(const string str, const uchar separator, string &result[])
{
   int count = 0;
   int start = 0;
   int pos = 0;
   
   ArrayResize(result, 0);
   
   while(pos <= StringLen(str))
   {
      uchar c = (uchar)StringGetChar(str, pos);
      
      if(c == separator || pos == StringLen(str))
      {
         string part = StringSubstr(str, start, pos - start);
         
         ArrayResize(result, count + 1);
         result[count] = part;
         count++;
         
         start = pos + 1;
      }
      
      pos++;
   }
   
   return count;
}

//+------------------------------------------------------------------+
// END OF EA
//+------------------------------------------------------------------+
