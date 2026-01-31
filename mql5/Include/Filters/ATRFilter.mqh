//+------------------------------------------------------------------+
//|                                                ATRFilter.mqh     |
//|                           MT5 ATR Filter                         |
//|                                                                  |
//| ATRフィルター - ボラティリティをチェック                          |
//| MT4 PullbackOOPからの移植版                                       |
//+------------------------------------------------------------------+
#ifndef __ATR_FILTER_MQH__
#define __ATR_FILTER_MQH__

#property copyright "2025"
#property strict

#include <Filters/IFilter.mqh>

//+------------------------------------------------------------------+
//| CATRFilter - ATRフィルター                                       |
//+------------------------------------------------------------------+
class CATRFilter : public IFilter
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int      m_period;
   int      m_handleATR;
   double   m_minATRPoints;   // 最小ATR（Points）
   double   m_maxATRPoints;   // 最大ATR（Points、0=無制限）
   double   m_pipMultiplier;  // pips→points変換係数
   
public:
   //--- コンストラクタ
   CATRFilter()
   {
      m_name = "ATRFilter";
      m_symbol = "";
      m_timeframe = PERIOD_CURRENT;
      m_period = 14;
      m_handleATR = INVALID_HANDLE;
      m_minATRPoints = 30.0;
      m_maxATRPoints = 0;
      m_pipMultiplier = 10.0;
   }
   
   //--- デストラクタ
   ~CATRFilter()
   {
      if(m_handleATR != INVALID_HANDLE)
      {
         IndicatorRelease(m_handleATR);
         m_handleATR = INVALID_HANDLE;
      }
   }
   
   //--- 初期化（遅延初期化対応）
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int period = 14, double minATRPoints = 30.0, double pipMulti = 10.0)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_period = period;
      m_minATRPoints = minATRPoints;
      m_pipMultiplier = pipMulti;
      return true;
   }
   
   //--- ハンドル作成（遅延初期化）
   bool EnsureHandle()
   {
      if(m_handleATR != INVALID_HANDLE) return true;
      if(StringLen(m_symbol) == 0) return false;
      
      m_handleATR = iATR(m_symbol, m_timeframe, m_period);
      return (m_handleATR != INVALID_HANDLE);
   }
   
   //--- ATR閾値設定（Points）
   void SetThresholdsPoints(double minPoints, double maxPoints = 0)
   {
      m_minATRPoints = minPoints;
      m_maxATRPoints = maxPoints;
   }
   
   //--- ATR閾値設定（Pips）
   void SetThresholdsPips(double minPips, double maxPips = 0)
   {
      m_minATRPoints = minPips * m_pipMultiplier;
      m_maxATRPoints = (maxPips > 0) ? maxPips * m_pipMultiplier : 0;
   }
   
   //--- フィルターチェック
   virtual bool Check(ENUM_TREND_DIRECTION trend) override
   {
      m_lastResult.Clear();
      
      // 無効時は即パス（インジケータ呼び出しを回避）
      if(!m_enabled)
      {
         m_lastResult.SetPass();
         return true;
      }
      
      // 遅延初期化
      if(!EnsureHandle())
      {
         m_lastResult.SetReject(FILTER_REJECT_ATR, "ATR handle creation failed");
         return false;
      }
      
      // ATR値取得
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_handleATR, 0, 1, 1, buf) != 1)
      {
         m_lastResult.SetReject(FILTER_REJECT_ATR, "Failed to copy ATR buffer");
         return false;
      }
      
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0) point = 0.00001;
      
      double atrPoints = buf[0] / point;
      
      m_lastResult.value = atrPoints;
      m_lastResult.threshold = m_minATRPoints;
      
      // 1. 最小ATRチェック（ボラティリティ不足）
      if(atrPoints < m_minATRPoints)
      {
         m_lastResult.SetReject(FILTER_REJECT_ATR,
            StringFormat("ATR %.1f < %.1f pts (low volatility)", atrPoints, m_minATRPoints),
            atrPoints, m_minATRPoints);
         return false;
      }
      
      // 2. 最大ATRチェック（過度なボラティリティ）
      if(m_maxATRPoints > 0 && atrPoints > m_maxATRPoints)
      {
         m_lastResult.SetReject(FILTER_REJECT_ATR,
            StringFormat("ATR %.1f > %.1f pts (excessive volatility)", atrPoints, m_maxATRPoints),
            atrPoints, m_maxATRPoints);
         return false;
      }
      
      m_lastResult.SetPass();
      return true;
   }
   
   //--- 現在のATR取得（Points）
   double GetCurrentATRPoints()
   {
      if(!EnsureHandle()) return 0;
      
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_handleATR, 0, 1, 1, buf) != 1) return 0;
      
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0) point = 0.00001;
      
      return buf[0] / point;
   }
   
   //--- 現在のATR取得（Pips）
   double GetCurrentATRPips()
   {
      return GetCurrentATRPoints() / m_pipMultiplier;
   }
   
   //--- 現在のATR取得（価格）
   double GetCurrentATRPrice()
   {
      if(!EnsureHandle()) return 0;
      
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_handleATR, 0, 1, 1, buf) != 1) return 0;
      
      return buf[0];
   }
};

#endif // __ATR_FILTER_MQH__
