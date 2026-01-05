//+------------------------------------------------------------------+
//|                                             FilterManager.mqh    |
//|                     Filter Management for Pullback Strategy      |
//|                    Time / Spread / ADX / ATR / Channel Filters   |
//+------------------------------------------------------------------+
#ifndef __FILTER_MANAGER_MQH__
#define __FILTER_MANAGER_MQH__

//--- Filter Configuration
struct SFilterConfig
{
   string   Symbol;
   
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
   
   // Default values
   SFilterConfig()
   : Symbol(""),
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
     ADXMinLevel(20.0),
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
     UseMTFEmaLong(true)
   {
   }
};

//+------------------------------------------------------------------+
//| CFilterManager - OOP Filter Management                           |
//+------------------------------------------------------------------+
class CFilterManager
{
private:
   SFilterConfig m_cfg;
   int           m_handleADX;
   int           m_handleATR;
   int           m_handleMtfEmaS;
   int           m_handleMtfEmaM;
   int           m_handleMtfEmaL;
   
   string        m_lastRejectReason;

public:
   //--- Constructor
   CFilterManager()
   : m_handleADX(INVALID_HANDLE),
     m_handleATR(INVALID_HANDLE),
     m_handleMtfEmaS(INVALID_HANDLE),
     m_handleMtfEmaM(INVALID_HANDLE),
     m_handleMtfEmaL(INVALID_HANDLE),
     m_lastRejectReason("")
   {
   }
   
   //--- Destructor
   ~CFilterManager()
   {
      if(m_handleADX != INVALID_HANDLE) IndicatorRelease(m_handleADX);
      if(m_handleATR != INVALID_HANDLE) IndicatorRelease(m_handleATR);
      ReleaseMtfIndicators();
   }

   void ReleaseMtfIndicators()
   {
      if(m_handleMtfEmaS != INVALID_HANDLE) { IndicatorRelease(m_handleMtfEmaS); m_handleMtfEmaS = INVALID_HANDLE; }
      if(m_handleMtfEmaM != INVALID_HANDLE) { IndicatorRelease(m_handleMtfEmaM); m_handleMtfEmaM = INVALID_HANDLE; }
      if(m_handleMtfEmaL != INVALID_HANDLE) { IndicatorRelease(m_handleMtfEmaL); m_handleMtfEmaL = INVALID_HANDLE; }
   }
   
   //--- Initialize with config
   void Init(const SFilterConfig &cfg, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
   {
      m_cfg = cfg;
      
      if(m_cfg.EnableADXFilter && StringLen(m_cfg.Symbol) > 0)
         m_handleADX = iADX(m_cfg.Symbol, timeframe, m_cfg.ADXPeriod);
      
      if((m_cfg.EnableATRFilter || m_cfg.EnableChannelFilter) && StringLen(m_cfg.Symbol) > 0)
         m_handleATR = iATR(m_cfg.Symbol, timeframe, m_cfg.ATRPeriod);

      if(m_cfg.EnableMTFFilter && StringLen(m_cfg.Symbol) > 0)
      {
         m_handleMtfEmaS = iMA(m_cfg.Symbol, m_cfg.MTFTimeframe, m_cfg.MTFEmaShort, 0, MODE_EMA, PRICE_CLOSE);
         m_handleMtfEmaM = iMA(m_cfg.Symbol, m_cfg.MTFTimeframe, m_cfg.MTFEmaMid, 0, MODE_EMA, PRICE_CLOSE);
         m_handleMtfEmaL = iMA(m_cfg.Symbol, m_cfg.MTFTimeframe, m_cfg.MTFEmaLong, 0, MODE_EMA, PRICE_CLOSE);
      }
   }
   
   //--- Check all filters - returns true if all pass
   bool CheckAll()
   {
      m_lastRejectReason = "";
      
      if(m_cfg.EnableTimeFilter && !CheckTimeFilter())
         return false;
      
      if(m_cfg.EnableSpreadFilter && !CheckSpreadFilter())
         return false;
      
      if(m_cfg.EnableADXFilter && !CheckADXFilter())
         return false;
      
      if(m_cfg.EnableATRFilter && !CheckATRFilter())
         return false;
      
      if(m_cfg.EnableChannelFilter && !CheckChannelFilter())
         return false;
      
      return true;
   }
   
   //--- Check MTF Direction (returns true if direction is allowed)
   //--- Check MTF Direction (returns true if direction is allowed)
   bool CheckMTF(ENUM_ORDER_TYPE orderType)
   {
      if(!m_cfg.EnableMTFFilter) return true;
      if(m_handleMtfEmaS == INVALID_HANDLE || m_handleMtfEmaM == INVALID_HANDLE || m_handleMtfEmaL == INVALID_HANDLE) return true;

      double s[], m[], l[];
      ArraySetAsSeries(s, true); ArraySetAsSeries(m, true); ArraySetAsSeries(l, true);

      if(CopyBuffer(m_handleMtfEmaS, 0, 1, 1, s) != 1) return true;
      if(CopyBuffer(m_handleMtfEmaM, 0, 1, 1, m) != 1) return true;
      if(CopyBuffer(m_handleMtfEmaL, 0, 1, 1, l) != 1) return true;

      bool isUp = true;
      bool isDown = true;

      // Logic: If a pair is enabled, check order. If any check fails, flag becomes false.

      // Up checks (S > M > L)
      if(m_cfg.UseMTFEmaShort && m_cfg.UseMTFEmaMid)
      {
         if(s[0] <= m[0]) isUp = false;
      }
      if(m_cfg.UseMTFEmaMid && m_cfg.UseMTFEmaLong)
      {
         if(m[0] <= l[0]) isUp = false;
      }
      if(m_cfg.UseMTFEmaShort && m_cfg.UseMTFEmaLong && !m_cfg.UseMTFEmaMid)
      {
         if(s[0] <= l[0]) isUp = false;
      }

      // Down checks (S < M < L)
      if(m_cfg.UseMTFEmaShort && m_cfg.UseMTFEmaMid)
      {
         if(s[0] >= m[0]) isDown = false;
      }
      if(m_cfg.UseMTFEmaMid && m_cfg.UseMTFEmaLong)
      {
         if(m[0] >= l[0]) isDown = false;
      }
      if(m_cfg.UseMTFEmaShort && m_cfg.UseMTFEmaLong && !m_cfg.UseMTFEmaMid)
      {
         if(s[0] >= l[0]) isDown = false;
      }

      if(orderType == ORDER_TYPE_BUY)
      {
         if(isUp) return true;
         m_lastRejectReason = "MTF Filter: Trend condition not met (Up)";
         return false;
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         if(isDown) return true;
         m_lastRejectReason = "MTF Filter: Trend condition not met (Down)";
         return false;
      }
      return true;
   }

   //--- Get last rejection reason
   string GetLastRejectReason() const { return m_lastRejectReason; }

private:
   //--- Time Filter (JST-based)
   bool CheckTimeFilter()
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      
      // Friday check
      if(dt.day_of_week == 5 && !m_cfg.TradeOnFriday)
      {
         m_lastRejectReason = "Friday trading disabled";
         return false;
      }
      
      // Convert to JST
      int gmt_offset_seconds = m_cfg.GMTOffset * 3600;
      if(m_cfg.UseDST) gmt_offset_seconds += 3600;
      datetime jst_time = TimeCurrent() - gmt_offset_seconds + (9 * 3600);
      MqlDateTime jst_dt;
      TimeToStruct(jst_time, jst_dt);
      
      int current_minutes = jst_dt.hour * 60 + jst_dt.min;
      int start_minutes = m_cfg.StartHour * 60 + m_cfg.StartMinute;
      int end_minutes = m_cfg.EndHour * 60 + m_cfg.EndMinute;
      
      bool inTimeRange = false;
      if(start_minutes <= end_minutes)
      {
         // Normal pattern (8:00 - 21:00)
         inTimeRange = (current_minutes >= start_minutes && current_minutes <= end_minutes);
      }
      else
      {
         // Overnight pattern (22:00 - 6:00)
         inTimeRange = (current_minutes >= start_minutes || current_minutes <= end_minutes);
      }
      
      if(!inTimeRange)
      {
         m_lastRejectReason = "Outside trading hours (JST " + IntegerToString(jst_dt.hour) + ":" + 
                              IntegerToString(jst_dt.min) + ")";
         return false;
      }
      
      return true;
   }
   
   //--- Spread Filter
   bool CheckSpreadFilter()
   {
      long spreadPoints = SymbolInfoInteger(m_cfg.Symbol, SYMBOL_SPREAD);
      
      if(spreadPoints > m_cfg.MaxSpreadPoints)
      {
         m_lastRejectReason = "Spread too wide: " + IntegerToString(spreadPoints) + " > " + 
                              IntegerToString(m_cfg.MaxSpreadPoints) + " points";
         return false;
      }
      
      return true;
   }
   
   //--- ADX Filter
   bool CheckADXFilter()
   {
      if(m_handleADX == INVALID_HANDLE) return true;
      
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(m_handleADX, 0, 1, 1, adx) != 1) return true;
      
      if(adx[0] < m_cfg.ADXMinLevel)
      {
         m_lastRejectReason = "ADX too low: " + DoubleToString(adx[0], 1) + " < " + 
                              DoubleToString(m_cfg.ADXMinLevel, 1);
         return false;
      }
      
      return true;
   }
   
   //--- ATR Filter
   bool CheckATRFilter()
   {
      if(m_handleATR == INVALID_HANDLE) return true;
      
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(m_handleATR, 0, 1, 1, atr) != 1) return true;
      
      double point = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_POINT);
      double atrPoints = atr[0] / point;
      
      if(atrPoints < m_cfg.ATRMinPoints)
      {
         m_lastRejectReason = "ATR too low: " + DoubleToString(atrPoints, 0) + " < " + 
                              DoubleToString(m_cfg.ATRMinPoints, 0) + " points";
         return false;
      }
      
      return true;
   }
   
   //--- Channel Width Filter (EMA12-EMA100 range)
   bool CheckChannelFilter()
   {
      // Calculate EMA12 and EMA100
      int hShort = iMA(m_cfg.Symbol, PERIOD_CURRENT, 12, 0, MODE_EMA, PRICE_CLOSE);
      int hLong = iMA(m_cfg.Symbol, PERIOD_CURRENT, 100, 0, MODE_EMA, PRICE_CLOSE);
      
      if(hShort == INVALID_HANDLE || hLong == INVALID_HANDLE)
      {
         if(hShort != INVALID_HANDLE) IndicatorRelease(hShort);
         if(hLong != INVALID_HANDLE) IndicatorRelease(hLong);
         return true;
      }
      
      double emaShort[], emaLong[];
      ArraySetAsSeries(emaShort, true);
      ArraySetAsSeries(emaLong, true);
      
      bool ok = (CopyBuffer(hShort, 0, 1, 1, emaShort) == 1 &&
                 CopyBuffer(hLong, 0, 1, 1, emaLong) == 1);
      
      IndicatorRelease(hShort);
      IndicatorRelease(hLong);
      
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
