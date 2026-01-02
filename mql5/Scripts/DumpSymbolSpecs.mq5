//+------------------------------------------------------------------+
//|                                                   DumpSymbolSpecs.mq5
//| Dumps broker symbol specifications to Experts log.
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input string InpSymbol = "";   // 空なら現在チャートのシンボル

string BoolStr(const bool v){ return v ? "true" : "false"; }

void PrintDbl(const string name, const double v, const int digits=10)
{
   Print(name, "=", DoubleToString(v, digits));
}

void PrintInt(const string name, const long v)
{
   Print(name, "=", (string)v);
}

void OnStart()
{
   string sym = InpSymbol;
   if(StringLen(sym) == 0)
      sym = _Symbol;

   if(!SymbolSelect(sym, true))
   {
      Print("[DumpSymbolSpecs] SymbolSelect failed: ", sym);
      return;
   }

   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   long spreadPts = SymbolInfoInteger(sym, SYMBOL_SPREAD);

   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double contractSize = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);

   double volMin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double volMax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   double volStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

   long tradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
   long calcMode = SymbolInfoInteger(sym, SYMBOL_TRADE_CALC_MODE);

   Print("==================== DumpSymbolSpecs ====================");
   Print("Symbol=", sym);
   Print("Digits=", digits, " Point=", DoubleToString(point, digits));
   Print("SpreadPts=", spreadPts, " SpreadPrice=", DoubleToString(spreadPts * point, digits));

   PrintInt("SYMBOL_TRADE_MODE", tradeMode);
   PrintInt("SYMBOL_TRADE_CALC_MODE", calcMode);

   PrintDbl("SYMBOL_TRADE_TICK_SIZE", tickSize, digits);
   PrintDbl("SYMBOL_TRADE_TICK_VALUE", tickValue, 10);
   PrintDbl("SYMBOL_TRADE_CONTRACT_SIZE", contractSize, 10);

   PrintDbl("SYMBOL_VOLUME_MIN", volMin, 10);
   PrintDbl("SYMBOL_VOLUME_STEP", volStep, 10);
   PrintDbl("SYMBOL_VOLUME_MAX", volMax, 10);

   // Quick risk helpers
   Print("-- Quick helpers --");
   Print("1 tick value (account currency) = SYMBOL_TRADE_TICK_VALUE");
   Print("1 point value (approx) = tickValue * (point / tickSize)  (when tickSize>0)");
   if(tickSize > 0)
   {
      double pointValue = tickValue * (point / tickSize);
      Print("ApproxPointValue=", DoubleToString(pointValue, 10));

      // Extra: min volume helpers
      double tickValueAtMinVol = tickValue * volMin;
      double pointValueAtMinVol = pointValue * volMin;
      Print("TickValueAtMinVol(=tickValue*VOL_MIN)=", DoubleToString(tickValueAtMinVol, 10));
      Print("PointValueAtMinVol(approx)=", DoubleToString(pointValueAtMinVol, 10));

      // Extra: 1.0 price unit helpers (when tickSize divides 1.0)
      double ticksPerOnePrice = 1.0 / tickSize;
      double valuePerOnePrice = tickValue * ticksPerOnePrice;
      Print("ApproxValuePer1.0Price(=tickValue*(1/tickSize))=", DoubleToString(valuePerOnePrice, 10));
      Print("ApproxValuePer1.0PriceAtMinVol=", DoubleToString(valuePerOnePrice * volMin, 10));
   }
   Print("=========================================================");
}
