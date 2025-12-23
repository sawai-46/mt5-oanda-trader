//+------------------------------------------------------------------+
//| InferenceHttpSmoke.mq5                                           |
//| MT5 -> HTTP inference server smoke test (no trading)             |
//+------------------------------------------------------------------+
#property strict
#property version "0.1"

#include <Integration/InferenceClient.mqh>

input string InpServerUrl       = "http://127.0.0.1:5001";
input string InpPredictEndpoint = "/predict";
input string InpPreset          = "antigravity_pullback";
input int    InpBars            = 120;
input int    InpTimeoutMs       = 2000;

int OnStart()
{
   string symbol = _Symbol;
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)_Period;

   double ema12 = iMA(symbol, tf, 12, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ema25 = iMA(symbol, tf, 25, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ema100 = iMA(symbol, tf, 100, 0, MODE_EMA, PRICE_CLOSE, 0);
   double atr = iATR(symbol, tf, 14, 0);
   double close = iClose(symbol, tf, 0);

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
