//+------------------------------------------------------------------+
//| InferenceHttpSmoke.mq5                                           |
//| MT5 -> HTTP inference server smoke test (no trading)             |
//+------------------------------------------------------------------+
#property strict
#property version "0.100"

#include <Integration/InferenceClient.mqh>

input string InpServerUrl       = "http://127.0.0.1:5001";
input string InpPredictEndpoint = "/predict";
input string InpPreset          = "antigravity_pullback";
input int    InpBars            = 120;
input int    InpTimeoutMs       = 2000;

bool GetIndicatorValue(const int handle, const int bufferIndex, const int shift, double &outValue)
{
   if(handle == INVALID_HANDLE)
      return false;

   double buf[];
   ArraySetAsSeries(buf, true);
   int copied = CopyBuffer(handle, bufferIndex, shift, 1, buf);
   if(copied != 1)
      return false;

   outValue = buf[0];
   return true;
}

int OnStart()
{
   string symbol = _Symbol;
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;

   int hEma12 = iMA(symbol, tf, 12, 0, MODE_EMA, PRICE_CLOSE);
   int hEma25 = iMA(symbol, tf, 25, 0, MODE_EMA, PRICE_CLOSE);
   int hEma100 = iMA(symbol, tf, 100, 0, MODE_EMA, PRICE_CLOSE);
   int hAtr = iATR(symbol, tf, 14);

   double ema12 = 0.0;
   double ema25 = 0.0;
   double ema100 = 0.0;
   double atr = 0.0;
   double close = iClose(symbol, tf, 0);

   bool ok12 = GetIndicatorValue(hEma12, 0, 0, ema12);
   bool ok25 = GetIndicatorValue(hEma25, 0, 0, ema25);
   bool ok100 = GetIndicatorValue(hEma100, 0, 0, ema100);
   bool okAtr = GetIndicatorValue(hAtr, 0, 0, atr);

   IndicatorRelease(hEma12);
   IndicatorRelease(hEma25);
   IndicatorRelease(hEma100);
   IndicatorRelease(hAtr);

   if(!ok12 || !ok25 || !ok100 || !okAtr)
   {
      Print("Indicator read failed. ok12=", ok12,
            " ok25=", ok25,
            " ok100=", ok100,
            " okAtr=", okAtr,
            " err=", GetLastError());
      return 0;
   }

   int bars = (int)MathMin((double)InpBars, (double)Bars(symbol, tf));
   string prices = "";
   for(int i=0; i<bars; i++)
   {
      if(i>0) prices += ",";
      prices += DoubleToString(iClose(symbol, tf, i), _Digits);
   }

   CInferenceClient client(InpServerUrl, InpPredictEndpoint, InpTimeoutMs);

   int signal = 0;
   double confidence = 0.0;
   string reason = "";
   int httpStatus = 0;
   string raw = "";

   bool ok = client.Predict(symbol, tf, InpPreset, ema12, ema25, ema100, atr, close, prices,
                            signal, confidence, reason, httpStatus, raw);

   Print("HTTP status=", httpStatus, " ok=", ok,
         " signal=", signal,
         " conf=", DoubleToString(confidence, 4),
         " reason=", reason);

   if(httpStatus != 200)
   {
      Print("Raw response: ", raw);
   }

   return 0;
}
