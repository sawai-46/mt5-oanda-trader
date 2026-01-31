//+------------------------------------------------------------------+
//|                                        CandlePatternFilter.mqh  |
//|                        MT5 Candle Pattern Filter                |
//|                                                                  |
//| ローソク足パターン検出（ピンバー、包み足）                        |
//| MT4 CommonEAからの移植版                                          |
//+------------------------------------------------------------------+
#ifndef __CANDLE_PATTERN_FILTER_MQH__
#define __CANDLE_PATTERN_FILTER_MQH__

#property copyright "2025"
#property strict

#include <Filters/IFilter.mqh>

//+------------------------------------------------------------------+
//| CCandlePatternFilter - ローソク足パターン検出フィルター          |
//+------------------------------------------------------------------+
class CCandlePatternFilter : public IFilter
{
private:
   string             m_symbol;
   ENUM_TIMEFRAMES    m_timeframe;
   bool               m_detectPinBar;      // ピンバー検出
   bool               m_detectEngulfing;   // 包み足検出
   double             m_minWickRatio;      // ピンバー最小ヒゲ比率（2.0 = ヒゲが実体の2倍）
   
   // ピンバー検出
   bool IsBullishPinBar(int shift)
   {
      double open = iOpen(m_symbol, m_timeframe, shift);
      double high = iHigh(m_symbol, m_timeframe, shift);
      double low = iLow(m_symbol, m_timeframe, shift);
      double close = iClose(m_symbol, m_timeframe, shift);
      
      double body = MathAbs(close - open);
      double upperWick = high - MathMax(open, close);
      double lowerWick = MathMin(open, close) - low;
      
      if(body == 0) body = 0.0001;
      
      // 強気ピンバー: 下ヒゲが実体の指定倍以上、上ヒゲが小さい
      return (lowerWick >= body * m_minWickRatio && upperWick < body);
   }
   
   bool IsBearishPinBar(int shift)
   {
      double open = iOpen(m_symbol, m_timeframe, shift);
      double high = iHigh(m_symbol, m_timeframe, shift);
      double low = iLow(m_symbol, m_timeframe, shift);
      double close = iClose(m_symbol, m_timeframe, shift);
      
      double body = MathAbs(close - open);
      double upperWick = high - MathMax(open, close);
      double lowerWick = MathMin(open, close) - low;
      
      if(body == 0) body = 0.0001;
      
      // 弱気ピンバー: 上ヒゲが実体の指定倍以上、下ヒゲが小さい
      return (upperWick >= body * m_minWickRatio && lowerWick < body);
   }
   
   // 包み足検出
   bool IsBullishEngulfing(int shift)
   {
      double currOpen = iOpen(m_symbol, m_timeframe, shift);
      double currClose = iClose(m_symbol, m_timeframe, shift);
      double prevOpen = iOpen(m_symbol, m_timeframe, shift + 1);
      double prevClose = iClose(m_symbol, m_timeframe, shift + 1);
      
      // 現在足が陽線で、前足が陰線で、現在足が前足を完全に包む
      return (currClose > currOpen &&
              prevClose < prevOpen &&
              currOpen <= prevClose &&
              currClose >= prevOpen);
   }
   
   bool IsBearishEngulfing(int shift)
   {
      double currOpen = iOpen(m_symbol, m_timeframe, shift);
      double currClose = iClose(m_symbol, m_timeframe, shift);
      double prevOpen = iOpen(m_symbol, m_timeframe, shift + 1);
      double prevClose = iClose(m_symbol, m_timeframe, shift + 1);
      
      // 現在足が陰線で、前足が陽線で、現在足が前足を完全に包む
      return (currClose < currOpen &&
              prevClose > prevOpen &&
              currOpen >= prevClose &&
              currClose <= prevOpen);
   }
   
public:
   //--- コンストラクタ
   CCandlePatternFilter()
   {
      m_name = "CandlePatternFilter";
      m_enabled = true;
      m_symbol = "";
      m_timeframe = PERIOD_CURRENT;
      m_detectPinBar = true;
      m_detectEngulfing = true;
      m_minWickRatio = 2.0;
   }
   
   //--- 初期化
   void Init(const string symbol, ENUM_TIMEFRAMES tf,
             bool detectPinBar = true, bool detectEngulfing = true, double minWickRatio = 2.0)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_detectPinBar = detectPinBar;
      m_detectEngulfing = detectEngulfing;
      m_minWickRatio = minWickRatio;
   }
   
   //--- 設定変更
   void SetDetectPinBar(bool detect) { m_detectPinBar = detect; }
   void SetDetectEngulfing(bool detect) { m_detectEngulfing = detect; }
   void SetMinWickRatio(double ratio) { m_minWickRatio = ratio; }
   
   //--- フィルターチェック（パターン検出 = エントリー許可）
   virtual bool Check(ENUM_TREND_DIRECTION trend) override
   {
      m_lastResult.Clear();
      
      if(!m_enabled)
      {
         m_lastResult.SetPass();
         return true;
      }
      
      if(trend == TREND_NONE)
      {
         m_lastResult.SetPass();
         return true;
      }
      
      bool patternFound = false;
      string patternName = "";
      
      if(m_detectPinBar)
      {
         if(trend == TREND_UP && IsBullishPinBar(1))
         {
            patternFound = true;
            patternName = "Bullish Pin Bar";
         }
         else if(trend == TREND_DOWN && IsBearishPinBar(1))
         {
            patternFound = true;
            patternName = "Bearish Pin Bar";
         }
      }
      
      if(!patternFound && m_detectEngulfing)
      {
         if(trend == TREND_UP && IsBullishEngulfing(1))
         {
            patternFound = true;
            patternName = "Bullish Engulfing";
         }
         else if(trend == TREND_DOWN && IsBearishEngulfing(1))
         {
            patternFound = true;
            patternName = "Bearish Engulfing";
         }
      }
      
      if(!patternFound)
      {
         m_lastResult.SetReject(FILTER_REJECT_PATTERN, "No candle pattern detected");
         return false;
      }
      
      Print("[CandlePattern] Detected: ", patternName);
      m_lastResult.SetPass();
      return true;
   }
   
   //--- パターン名取得（ログ用）
   string GetDetectedPattern(ENUM_TREND_DIRECTION trend)
   {
      if(m_detectPinBar)
      {
         if(trend == TREND_UP && IsBullishPinBar(1)) return "Bullish Pin Bar";
         if(trend == TREND_DOWN && IsBearishPinBar(1)) return "Bearish Pin Bar";
      }
      if(m_detectEngulfing)
      {
         if(trend == TREND_UP && IsBullishEngulfing(1)) return "Bullish Engulfing";
         if(trend == TREND_DOWN && IsBearishEngulfing(1)) return "Bearish Engulfing";
      }
      return "";
   }
};

#endif // __CANDLE_PATTERN_FILTER_MQH__
