//+------------------------------------------------------------------+
//|                                             MTFTrendFilter.mqh  |
//|                           MT5 MTF Trend Filter                  |
//|                                                                  |
//| 上位足EMAのトレンド一致を確認                                   |
//| MT4 CommonEAからの移植版                                          |
//+------------------------------------------------------------------+
#ifndef __MTF_TREND_FILTER_MQH__
#define __MTF_TREND_FILTER_MQH__

#property copyright "2025"
#property strict

#include <Filters/IFilter.mqh>

class CMTFTrendFilter : public IFilter
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int             m_emaShort;
   int             m_emaMid;
   int             m_emaLong;
   bool            m_useEmaShort;
   bool            m_useEmaMid;
   bool            m_useEmaLong;
   ENUM_MA_METHOD  m_method;
   
   // MT5 ハンドル
   int             m_handleEmaShort;
   int             m_handleEmaMid;
   int             m_handleEmaLong;

   double GetMA(int handle, int shift = 1) const
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, 0, shift, 1, buf) != 1)
         return 0;
      return buf[0];
   }

   bool CheckUp(const double emaS, const double emaM, const double emaL) const
   {
      bool upOk = true;
      if(m_useEmaShort && m_useEmaMid)
         upOk &= (emaS > emaM);
      if(m_useEmaMid && m_useEmaLong)
         upOk &= (emaM > emaL);
      if(m_useEmaShort && m_useEmaLong && !m_useEmaMid)
         upOk &= (emaS > emaL);
      return upOk;
   }

   bool CheckDown(const double emaS, const double emaM, const double emaL) const
   {
      bool downOk = true;
      if(m_useEmaShort && m_useEmaMid)
         downOk &= (emaS < emaM);
      if(m_useEmaMid && m_useEmaLong)
         downOk &= (emaM < emaL);
      if(m_useEmaShort && m_useEmaLong && !m_useEmaMid)
         downOk &= (emaS < emaL);
      return downOk;
   }

public:
   CMTFTrendFilter()
   {
      m_name = "MTFTrendFilter";
      m_enabled = true;
      m_symbol = "";
      m_timeframe = PERIOD_H1;
      m_emaShort = 12;
      m_emaMid = 25;
      m_emaLong = 100;
      m_useEmaShort = true;
      m_useEmaMid = true;
      m_useEmaLong = true;
      m_method = MODE_EMA;
      m_handleEmaShort = INVALID_HANDLE;
      m_handleEmaMid = INVALID_HANDLE;
      m_handleEmaLong = INVALID_HANDLE;
   }
   
   ~CMTFTrendFilter()
   {
      ReleaseHandles();
   }
   
   void ReleaseHandles()
   {
      if(m_handleEmaShort != INVALID_HANDLE) { IndicatorRelease(m_handleEmaShort); m_handleEmaShort = INVALID_HANDLE; }
      if(m_handleEmaMid != INVALID_HANDLE) { IndicatorRelease(m_handleEmaMid); m_handleEmaMid = INVALID_HANDLE; }
      if(m_handleEmaLong != INVALID_HANDLE) { IndicatorRelease(m_handleEmaLong); m_handleEmaLong = INVALID_HANDLE; }
   }

   void Init(const string symbol,
             ENUM_TIMEFRAMES timeframe,
             int emaShort,
             int emaMid,
             int emaLong,
             bool useEmaShort,
             bool useEmaMid,
             bool useEmaLong,
             ENUM_MA_METHOD method = MODE_EMA)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_emaShort = emaShort;
      m_emaMid = emaMid;
      m_emaLong = emaLong;
      m_useEmaShort = useEmaShort;
      m_useEmaMid = useEmaMid;
      m_useEmaLong = useEmaLong;
      m_method = method;
      
      // ハンドル作成
      ReleaseHandles();
      if(m_useEmaShort)
         m_handleEmaShort = iMA(m_symbol, m_timeframe, m_emaShort, 0, m_method, PRICE_CLOSE);
      if(m_useEmaMid)
         m_handleEmaMid = iMA(m_symbol, m_timeframe, m_emaMid, 0, m_method, PRICE_CLOSE);
      if(m_useEmaLong)
         m_handleEmaLong = iMA(m_symbol, m_timeframe, m_emaLong, 0, m_method, PRICE_CLOSE);
   }

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

      double emaS = m_useEmaShort ? GetMA(m_handleEmaShort, 1) : 0;
      double emaM = m_useEmaMid ? GetMA(m_handleEmaMid, 1) : 0;
      double emaL = m_useEmaLong ? GetMA(m_handleEmaLong, 1) : 0;

      bool upOk = CheckUp(emaS, emaM, emaL);
      bool downOk = CheckDown(emaS, emaM, emaL);

      if(trend == TREND_UP && !upOk)
      {
         m_lastResult.SetReject(FILTER_REJECT_MTF, "MTF trend mismatch (UP)");
         return false;
      }
      if(trend == TREND_DOWN && !downOk)
      {
         m_lastResult.SetReject(FILTER_REJECT_MTF, "MTF trend mismatch (DOWN)");
         return false;
      }

      m_lastResult.SetPass();
      return true;
   }
   
   string GetInfo() const
   {
      return StringFormat("MTF[%s] EMA(%d/%d/%d)", 
         EnumToString(m_timeframe), m_emaShort, m_emaMid, m_emaLong);
   }
};

#endif // __MTF_TREND_FILTER_MQH__
