//+------------------------------------------------------------------+
//|                                             FilterManager.mqh    |
//|                     Filter Management for Pullback Strategy      |
//|       Time / Spread / ADX / ATR / Channel / MTF / Pattern Filters|
//|                     MT4 CommonEA互換・モジュラー設計              |
//+------------------------------------------------------------------+
#ifndef __FILTER_MANAGER_MQH__
#define __FILTER_MANAGER_MQH__

#include <Filters/IFilter.mqh>
#include <Filters/FilterBase.mqh>
#include <Filters/ADXFilter.mqh>
#include <Filters/ATRFilter.mqh>
#include <Filters/SpreadFilter.mqh>
#include <Filters/TimeFilter.mqh>
#include <Filters/CandlePatternFilter.mqh>
#include <Filters/MTFTrendFilter.mqh>

//--- Filter Configuration
struct SFilterConfig
{
   string   Symbol;
   double   PipMultiplier;    // pips→points変換係数（FX=10.0, Index=1.0）
   
   // Time Filter (JST-based)
   bool     EnableTimeFilter;
   int      GMTOffset;
   bool     UseDST;
   int      StartHour;
   int      StartMinute;
   int      EndHour;
   int      EndMinute;
   bool     TradeOnFriday;
   
   // Spread Filter
   bool     EnableSpreadFilter;
   int      MaxSpreadPoints;
   
   // ADX Filter
   bool     EnableADXFilter;
   int      ADXPeriod;
   double   ADXMinLevel;
   bool     ADXRequireRising;
   double   DISpreadMin;
   
   // ATR Filter
   bool     EnableATRFilter;
   int      ATRPeriod;
   double   ATRMinPoints;
   
   // Channel Width Filter
   bool     EnableChannelFilter;
   int      ChannelPeriod;
   double   MinChannelWidthPoints;

   // MTF Trend Filter
   bool     EnableMTFFilter;
   ENUM_TIMEFRAMES MTFTimeframe;
   int      MTFEmaShort;
   int      MTFEmaMid;
   int      MTFEmaLong;
   bool     UseMTFEmaShort;
   bool     UseMTFEmaMid;
   bool     UseMTFEmaLong;

   // Candle Pattern Filter
   bool     EnableCandlePatternFilter;
   bool     DetectPinBar;
   bool     DetectEngulfing;
   double   MinWickRatio;
   
   // Default values
   SFilterConfig()
   : Symbol(""),
     PipMultiplier(10.0),
     EnableTimeFilter(true),
     GMTOffset(3),
     UseDST(false),
     StartHour(8),
     StartMinute(0),
     EndHour(21),
     EndMinute(0),
     TradeOnFriday(true),
     EnableSpreadFilter(true),
     MaxSpreadPoints(200),
     EnableADXFilter(true),
     ADXPeriod(14),
     ADXMinLevel(15.0),
     ADXRequireRising(false),
     DISpreadMin(0),
     EnableATRFilter(true),
     ATRPeriod(14),
     ATRMinPoints(30.0),
     EnableChannelFilter(false),
     ChannelPeriod(20),
     MinChannelWidthPoints(300.0),
     EnableMTFFilter(false),
     MTFTimeframe(PERIOD_H1),
     MTFEmaShort(12),
     MTFEmaMid(25),
     MTFEmaLong(100),
     UseMTFEmaShort(true),
     UseMTFEmaMid(true),
     UseMTFEmaLong(true),
     EnableCandlePatternFilter(false),
     DetectPinBar(true),
     DetectEngulfing(true),
     MinWickRatio(2.0)
   {
   }
};

//+------------------------------------------------------------------+
//| CFilterManager - OOP Filter Management                           |
//|              個別フィルタークラスを統合管理                       |
//+------------------------------------------------------------------+
class CFilterManager
{
private:
   SFilterConfig m_cfg;
   ENUM_TIMEFRAMES m_timeframe;
   
   // 個別フィルタークラス（モジュラー設計）
   CTimeFilter          m_timeFilter;
   CSpreadFilter        m_spreadFilter;
   CADXFilter           m_adxFilter;
   CATRFilter           m_atrFilter;
   CCandlePatternFilter m_candlePattern;
   CMTFTrendFilter      m_mtfFilter;
   
   // チャネルフィルター用ハンドル（独自実装）
   int           m_handleChannelShort;
   int           m_handleChannelLong;
   
   string        m_lastRejectReason;

public:
   //--- Constructor
   CFilterManager()
   : m_timeframe(PERIOD_CURRENT),
     m_handleChannelShort(INVALID_HANDLE),
     m_handleChannelLong(INVALID_HANDLE),
     m_lastRejectReason("")
   {
   }
   
   //--- Destructor
   ~CFilterManager()
   {
      ReleaseChannelIndicators();
   }

   void ReleaseChannelIndicators()
   {
      if(m_handleChannelShort != INVALID_HANDLE) { IndicatorRelease(m_handleChannelShort); m_handleChannelShort = INVALID_HANDLE; }
      if(m_handleChannelLong != INVALID_HANDLE) { IndicatorRelease(m_handleChannelLong); m_handleChannelLong = INVALID_HANDLE; }
   }
   
   //--- Initialize with config
   void Init(const SFilterConfig &cfg, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
   {
      m_cfg = cfg;
      m_timeframe = timeframe;
      
      // Time Filter
      if(m_cfg.EnableTimeFilter)
      {
         m_timeFilter.Init(m_cfg.StartHour, m_cfg.StartMinute, m_cfg.EndHour, m_cfg.EndMinute,
                           m_cfg.GMTOffset, m_cfg.UseDST, m_cfg.TradeOnFriday);
         m_timeFilter.SetEnabled(true);
      }
      else
      {
         m_timeFilter.SetEnabled(false);
      }
      
      // Spread Filter
      if(m_cfg.EnableSpreadFilter && StringLen(m_cfg.Symbol) > 0)
      {
         m_spreadFilter.Init(m_cfg.Symbol, m_cfg.MaxSpreadPoints, m_cfg.PipMultiplier);
         m_spreadFilter.SetEnabled(true);
      }
      else
      {
         m_spreadFilter.SetEnabled(false);
      }
      
      // ADX Filter
      if(m_cfg.EnableADXFilter && StringLen(m_cfg.Symbol) > 0)
      {
         m_adxFilter.Init(m_cfg.Symbol, timeframe, m_cfg.ADXPeriod, m_cfg.ADXMinLevel);
         m_adxFilter.SetRequireRising(m_cfg.ADXRequireRising);
         m_adxFilter.SetDISpreadMin(m_cfg.DISpreadMin);
         m_adxFilter.SetEnabled(true);
      }
      else
      {
         m_adxFilter.SetEnabled(false);
      }
      
      // ATR Filter
      if(m_cfg.EnableATRFilter && StringLen(m_cfg.Symbol) > 0)
      {
         m_atrFilter.Init(m_cfg.Symbol, timeframe, m_cfg.ATRPeriod, m_cfg.ATRMinPoints, m_cfg.PipMultiplier);
         m_atrFilter.SetEnabled(true);
      }
      else
      {
         m_atrFilter.SetEnabled(false);
      }
      
      // MTF Filter
      if(m_cfg.EnableMTFFilter && StringLen(m_cfg.Symbol) > 0)
      {
         m_mtfFilter.Init(m_cfg.Symbol, m_cfg.MTFTimeframe, 
                          m_cfg.MTFEmaShort, m_cfg.MTFEmaMid, m_cfg.MTFEmaLong,
                          m_cfg.UseMTFEmaShort, m_cfg.UseMTFEmaMid, m_cfg.UseMTFEmaLong);
         m_mtfFilter.SetEnabled(true);
      }
      else
      {
         m_mtfFilter.SetEnabled(false);
      }

      // Candle Pattern Filter
      if(m_cfg.EnableCandlePatternFilter && StringLen(m_cfg.Symbol) > 0)
      {
         m_candlePattern.Init(m_cfg.Symbol, timeframe, m_cfg.DetectPinBar, m_cfg.DetectEngulfing, m_cfg.MinWickRatio);
         m_candlePattern.SetEnabled(true);
      }
      else
      {
         m_candlePattern.SetEnabled(false);
      }
   }
   
   //--- Check all filters - returns true if all pass
   bool CheckAll()
   {
      m_lastRejectReason = "";
      
      // Time Filter
      if(!m_timeFilter.Check(TREND_NONE))
      {
         m_lastRejectReason = m_timeFilter.GetLastResult().message;
         return false;
      }
      
      // Spread Filter
      if(!m_spreadFilter.Check(TREND_NONE))
      {
         m_lastRejectReason = m_spreadFilter.GetLastResult().message;
         return false;
      }
      
      // ADX Filter (direction-neutral check)
      if(!m_adxFilter.Check(TREND_NONE))
      {
         m_lastRejectReason = m_adxFilter.GetLastResult().message;
         return false;
      }
      
      // ATR Filter
      if(!m_atrFilter.Check(TREND_NONE))
      {
         m_lastRejectReason = m_atrFilter.GetLastResult().message;
         return false;
      }
      
      // Channel Filter（独自実装）
      if(m_cfg.EnableChannelFilter && !CheckChannelFilter())
         return false;
      
      return true;
   }
   
   //--- Check MTF Direction (returns true if direction is allowed)
   bool CheckMTF(ENUM_ORDER_TYPE orderType)
   {
      if(!m_cfg.EnableMTFFilter) return true;
      
      ENUM_TREND_DIRECTION trend = TREND_NONE;
      if(orderType == ORDER_TYPE_BUY) trend = TREND_UP;
      else if(orderType == ORDER_TYPE_SELL) trend = TREND_DOWN;
      
      if(!m_mtfFilter.Check(trend))
      {
         m_lastRejectReason = m_mtfFilter.GetLastResult().message;
         return false;
      }
      return true;
   }

   //--- Get last rejection reason
   string GetLastRejectReason() const { return m_lastRejectReason; }

   //--- Check Candle Pattern (direction-aware)
   bool CheckCandlePattern(ENUM_ORDER_TYPE orderType)
   {
      if(!m_cfg.EnableCandlePatternFilter) return true;
      
      ENUM_TREND_DIRECTION trend = TREND_NONE;
      if(orderType == ORDER_TYPE_BUY) trend = TREND_UP;
      else if(orderType == ORDER_TYPE_SELL) trend = TREND_DOWN;
      
      if(!m_candlePattern.Check(trend))
      {
         m_lastRejectReason = "Candle Pattern: No pattern detected";
         return false;
      }
      return true;
   }
   
   //--- Get detected pattern name (for logging)
   string GetDetectedPatternName(ENUM_ORDER_TYPE orderType)
   {
      if(!m_cfg.EnableCandlePatternFilter) return "";
      ENUM_TREND_DIRECTION trend = (orderType == ORDER_TYPE_BUY) ? TREND_UP : TREND_DOWN;
      return m_candlePattern.GetDetectedPattern(trend);
   }
   
   //--- 個別フィルター参照取得（拡張用）
   CADXFilter*     GetADXFilter()     { return &m_adxFilter; }
   CATRFilter*     GetATRFilter()     { return &m_atrFilter; }
   CSpreadFilter*  GetSpreadFilter()  { return &m_spreadFilter; }
   CTimeFilter*    GetTimeFilter()    { return &m_timeFilter; }
   CMTFTrendFilter* GetMTFFilter()    { return &m_mtfFilter; }
   CCandlePatternFilter* GetCandlePatternFilter() { return &m_candlePattern; }

private:
   //--- Channel Width Filter (EMA12-EMA100 range)
   bool CheckChannelFilter()
   {
      // 遅延初期化
      if(m_handleChannelShort == INVALID_HANDLE)
         m_handleChannelShort = iMA(m_cfg.Symbol, m_timeframe, 12, 0, MODE_EMA, PRICE_CLOSE);
      if(m_handleChannelLong == INVALID_HANDLE)
         m_handleChannelLong = iMA(m_cfg.Symbol, m_timeframe, 100, 0, MODE_EMA, PRICE_CLOSE);
      
      if(m_handleChannelShort == INVALID_HANDLE || m_handleChannelLong == INVALID_HANDLE)
         return true;
      
      double emaShort[], emaLong[];
      ArraySetAsSeries(emaShort, true);
      ArraySetAsSeries(emaLong, true);
      
      bool ok = (CopyBuffer(m_handleChannelShort, 0, 1, 1, emaShort) == 1 &&
                 CopyBuffer(m_handleChannelLong, 0, 1, 1, emaLong) == 1);
      
      if(!ok) return true;
      
      double point = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_POINT);
      double channelWidth = MathAbs(emaShort[0] - emaLong[0]) / point;
      
      if(channelWidth < m_cfg.MinChannelWidthPoints)
      {
         m_lastRejectReason = "Channel too narrow: " + DoubleToString(channelWidth, 0) + " < " + 
                              DoubleToString(m_cfg.MinChannelWidthPoints, 0) + " points";
         return false;
      }
      
      return true;
   }
};

#endif
