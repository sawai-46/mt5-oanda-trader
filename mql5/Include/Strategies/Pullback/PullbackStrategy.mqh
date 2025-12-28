#ifndef __PULLBACK_STRATEGY_MQH__
#define __PULLBACK_STRATEGY_MQH__

#include <Core/StrategyBase.mqh>
#include <Integration/Logger.mqh>
#include <Integration/AiLearningLogger.mqh>
#include <Strategies/Pullback/PullbackConfig.mqh>

class CPullbackStrategy : public CStrategyBase
{
private:
   CPullbackConfig  m_cfg;

   CAiLearningLogger m_aiLogger;

   int m_handleEmaShort;
   int m_handleEmaMid;
   int m_handleEmaLong;
   int m_handleADX;
   int m_handleATR;

   datetime m_lastBarTime;

private:
   int EmaRefPeriod() const
   {
      if(m_cfg.PullbackEmaRef == PULLBACK_EMA_12)  return m_cfg.EmaShortPeriod;
      if(m_cfg.PullbackEmaRef == PULLBACK_EMA_100) return m_cfg.EmaLongPeriod;
      return m_cfg.EmaMidPeriod;
   }

   bool IsNewBar()
   {
      datetime t = iTime(m_symbol, m_timeframe, 0);
      if(t <= 0) return false;
      if(m_lastBarTime == 0)
      {
         m_lastBarTime = t;
         return false;
      }
      if(t != m_lastBarTime)
      {
         m_lastBarTime = t;
         return true;
      }
      return false;
   }

   bool Copy1(int handle, int shift, double &outValue)
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, 0, shift, 1, buf) != 1) return false;
      outValue = buf[0];
      return true;
   }

   bool CopyAdxMain(int shift, double &outValue)
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      // iADX: buffer 0 = MAIN
      if(CopyBuffer(m_handleADX, 0, shift, 1, buf) != 1) return false;
      outValue = buf[0];
      return true;
   }

   bool GetEmaValues(int shift, double &emaS, double &emaM, double &emaL)
   {
      if(!Copy1(m_handleEmaShort, shift, emaS)) return false;
      if(!Copy1(m_handleEmaMid, shift, emaM)) return false;
      if(!Copy1(m_handleEmaLong, shift, emaL)) return false;
      return true;
   }

   bool HasPosition() const
   {
      return PositionSelect(m_symbol);
   }

   bool SpreadOk() const
   {
      long spreadPoints = 0;
      if(!SymbolInfoInteger(m_symbol, SYMBOL_SPREAD, spreadPoints)) return true;
      return (spreadPoints <= (long)m_cfg.MaxSpreadPoints);
   }

   bool FiltersOk()
   {
      if(!SpreadOk()) return false;

      if(m_cfg.ATRPeriod > 0 && m_cfg.ATRThresholdPoints > 0.0)
      {
         double atr = 0.0;
         if(!Copy1(m_handleATR, 1, atr)) return false;
         double atrPoints = atr / _Point;
         if(atrPoints < m_cfg.ATRThresholdPoints) return false;
      }

      if(m_cfg.UseADXFilter)
      {
         double adx = 0.0;
         if(!CopyAdxMain(1, adx)) return false;
         if(adx < m_cfg.ADXMinLevel) return false;
      }

      return true;
   }

   bool TrendIsBuy()
   {
      double s, m, l;
      if(!GetEmaValues(1, s, m, l)) return false;
      if(!m_cfg.RequirePerfectOrder) return (s > m);
      return (s > m && m > l);
   }

   bool TrendIsSell()
   {
      double s, m, l;
      if(!GetEmaValues(1, s, m, l)) return false;
      if(!m_cfg.RequirePerfectOrder) return (s < m);
      return (s < m && m < l);
   }

   bool PullbackBuySignal()
   {
      int refPeriod = EmaRefPeriod();
      int hRef = iMA(m_symbol, m_timeframe, refPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hRef == INVALID_HANDLE) return false;

      double ema1=0.0, ema2=0.0;
      double close1 = iClose(m_symbol, m_timeframe, 1);
      double close2 = iClose(m_symbol, m_timeframe, 2);
      double low1 = iLow(m_symbol, m_timeframe, 1);

      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(hRef, 0, 1, 2, buf) != 2)
      {
         IndicatorRelease(hRef);
         return false;
      }
      ema1 = buf[0];
      ema2 = buf[1];
      IndicatorRelease(hRef);

      bool touch = m_cfg.UseTouchPullback && (low1 <= ema1 && close1 > ema1);
      bool cross = m_cfg.UseCrossPullback && (close2 < ema2 && close1 > ema1);
      bool brk   = m_cfg.UseBreakPullback && (close1 > ema1 && close2 < ema2);
      return (touch || cross || brk);
   }

   string PullbackBuyPattern()
   {
      int refPeriod = EmaRefPeriod();
      int hRef = iMA(m_symbol, m_timeframe, refPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hRef == INVALID_HANDLE) return "";

      double close1 = iClose(m_symbol, m_timeframe, 1);
      double close2 = iClose(m_symbol, m_timeframe, 2);
      double low1 = iLow(m_symbol, m_timeframe, 1);

      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(hRef, 0, 1, 2, buf) != 2)
      {
         IndicatorRelease(hRef);
         return "";
      }
      double ema1 = buf[0];
      double ema2 = buf[1];
      IndicatorRelease(hRef);

      bool touch = m_cfg.UseTouchPullback && (low1 <= ema1 && close1 > ema1);
      bool cross = m_cfg.UseCrossPullback && (close2 < ema2 && close1 > ema1);
      bool brk   = m_cfg.UseBreakPullback && (close1 > ema1 && close2 < ema2);
      if(touch) return "touch";
      if(cross) return "cross";
      if(brk)   return "break";
      return "";
   }

   bool PullbackSellSignal()
   {
      int refPeriod = EmaRefPeriod();
      int hRef = iMA(m_symbol, m_timeframe, refPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hRef == INVALID_HANDLE) return false;

      double ema1=0.0, ema2=0.0;
      double close1 = iClose(m_symbol, m_timeframe, 1);
      double close2 = iClose(m_symbol, m_timeframe, 2);
      double high1 = iHigh(m_symbol, m_timeframe, 1);

      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(hRef, 0, 1, 2, buf) != 2)
      {
         IndicatorRelease(hRef);
         return false;
      }
      ema1 = buf[0];
      ema2 = buf[1];
      IndicatorRelease(hRef);

      bool touch = m_cfg.UseTouchPullback && (high1 >= ema1 && close1 < ema1);
      bool cross = m_cfg.UseCrossPullback && (close2 > ema2 && close1 < ema1);
      bool brk   = m_cfg.UseBreakPullback && (close1 < ema1 && close2 > ema2);
      return (touch || cross || brk);
   }

   string PullbackSellPattern()
   {
      int refPeriod = EmaRefPeriod();
      int hRef = iMA(m_symbol, m_timeframe, refPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hRef == INVALID_HANDLE) return "";

      double close1 = iClose(m_symbol, m_timeframe, 1);
      double close2 = iClose(m_symbol, m_timeframe, 2);
      double high1 = iHigh(m_symbol, m_timeframe, 1);

      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(hRef, 0, 1, 2, buf) != 2)
      {
         IndicatorRelease(hRef);
         return "";
      }
      double ema1 = buf[0];
      double ema2 = buf[1];
      IndicatorRelease(hRef);

      bool touch = m_cfg.UseTouchPullback && (high1 >= ema1 && close1 < ema1);
      bool cross = m_cfg.UseCrossPullback && (close2 > ema2 && close1 < ema1);
      bool brk   = m_cfg.UseBreakPullback && (close1 < ema1 && close2 > ema2);
      if(touch) return "touch";
      if(cross) return "cross";
      if(brk)   return "break";
      return "";
   }

   void LogAiLearningRow(const string direction, const double entryPrice, const string patternType)
   {
      if(!m_cfg.EnableAiLearningLog)
         return;

      double emaS=0.0, emaM=0.0, emaL=0.0;
      if(!GetEmaValues(1, emaS, emaM, emaL))
         return;

      double atr = 0.0;
      if(!Copy1(m_handleATR, 1, atr))
         atr = 0.0;

      double adx = 0.0;
      if(m_cfg.UseADXFilter)
      {
         if(!CopyAdxMain(1, adx))
            adx = 0.0;
      }

      double channelWidth = MathAbs(emaS - emaL) / _Point;
      long tickVol = (long)iVolume(m_symbol, m_timeframe, 1);
      double barRange = (iHigh(m_symbol, m_timeframe, 1) - iLow(m_symbol, m_timeframe, 1)) / _Point;

      MqlDateTime dt;
      TimeCurrent(dt);
      int hour = dt.hour;
      int dow = dt.day_of_week;

      long spread = 0;
      SymbolInfoInteger(m_symbol, SYMBOL_SPREAD, spread);
      long spreadMax = (long)m_cfg.MaxSpreadPoints;

      // Simple heuristics (placeholders; can be upgraded later)
      double algoLevel = 1.0;
      double noiseRatio = 0.0;

      // Tick volume surge ratio (current vs avg last 10)
      double tickVolSurge = 1.0;
      double volSum = 0.0;
      int volN = 0;
      for(int i = 2; i <= 11; i++)
      {
         long v = (long)iVolume(m_symbol, m_timeframe, i);
         if(v > 0)
         {
            volSum += (double)v;
            volN++;
         }
      }
      double volAvg = (volN > 0) ? (volSum / volN) : 0.0;
      if(volAvg > 0.0 && tickVol > 0)
         tickVolSurge = (double)tickVol / volAvg;

      // ATR spike ratio (current vs avg last 10)
      double atrSpikeRatio = 1.0;
      double atrSum = 0.0;
      int atrN = 0;
      for(int i = 2; i <= 11; i++)
      {
         double a = iATR(m_symbol, m_timeframe, m_cfg.ATRPeriod, i);
         if(a > 0.0)
         {
            atrSum += a;
            atrN++;
         }
      }
      double atrAvg = (atrN > 0) ? (atrSum / atrN) : 0.0;
      if(atrAvg > 0.0 && atr > 0.0)
         atrSpikeRatio = atr / atrAvg;

      string spoofingSuspect = "";
      double open1 = iOpen(m_symbol, m_timeframe, 1);
      double close1 = iClose(m_symbol, m_timeframe, 1);
      double priceChangePct = (open1 != 0.0) ? ((close1 - open1) / open1) * 100.0 : 0.0;

      m_aiLogger.LogPullbackEntry(
         m_symbol,
         m_timeframe,
         direction,
         entryPrice,
         patternType,
         emaS,
         emaM,
         emaL,
         atr,
         adx,
         channelWidth,
         tickVol,
         barRange,
         hour,
         dow,
         algoLevel,
         noiseRatio,
         spread,
         spreadMax,
         tickVolSurge,
         atrSpikeRatio,
         spoofingSuspect,
         priceChangePct
      );
   }

   bool CalcSLTP(ENUM_ORDER_TYPE type, double entryPrice, double &sl, double &tp)
   {
      sl = 0.0;
      tp = 0.0;

      double atr = 0.0;
      if(m_cfg.SLTPMode == SLTP_ATR)
      {
         if(!Copy1(m_handleATR, 1, atr)) return false;
      }

      if(type == ORDER_TYPE_BUY)
      {
         if(m_cfg.UseStopLoss)
         {
            double slDist = (m_cfg.SLTPMode == SLTP_ATR) ? (atr * m_cfg.StopLossAtrMulti) : (m_cfg.StopLossFixedPoints * _Point);
            sl = entryPrice - slDist;
         }
         if(m_cfg.UseTakeProfit)
         {
            double tpDist = (m_cfg.SLTPMode == SLTP_ATR) ? (atr * m_cfg.TakeProfitAtrMulti) : (m_cfg.TakeProfitFixedPoints * _Point);
            tp = entryPrice + tpDist;
         }
      }
      else if(type == ORDER_TYPE_SELL)
      {
         if(m_cfg.UseStopLoss)
         {
            double slDist = (m_cfg.SLTPMode == SLTP_ATR) ? (atr * m_cfg.StopLossAtrMulti) : (m_cfg.StopLossFixedPoints * _Point);
            sl = entryPrice + slDist;
         }
         if(m_cfg.UseTakeProfit)
         {
            double tpDist = (m_cfg.SLTPMode == SLTP_ATR) ? (atr * m_cfg.TakeProfitAtrMulti) : (m_cfg.TakeProfitFixedPoints * _Point);
            tp = entryPrice - tpDist;
         }
      }

      return true;
   }

public:
   CPullbackStrategy(string symbol, ENUM_TIMEFRAMES timeframe, const CPullbackConfig &cfg)
   : CStrategyBase(symbol, timeframe),
     m_cfg(cfg),
     m_handleEmaShort(INVALID_HANDLE),
     m_handleEmaMid(INVALID_HANDLE),
     m_handleEmaLong(INVALID_HANDLE),
     m_handleADX(INVALID_HANDLE),
     m_handleATR(INVALID_HANDLE),
     m_lastBarTime(0)
   {
      m_trade.Configure(m_cfg.MagicNumber, m_cfg.DeviationPoints, ORDER_FILLING_IOC);
      m_aiLogger.Configure(m_cfg.EnableAiLearningLog, m_cfg.TerminalId, m_cfg.AiLearningFolder);

      m_handleEmaShort = iMA(m_symbol, m_timeframe, m_cfg.EmaShortPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleEmaMid   = iMA(m_symbol, m_timeframe, m_cfg.EmaMidPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleEmaLong  = iMA(m_symbol, m_timeframe, m_cfg.EmaLongPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(m_cfg.UseADXFilter)
         m_handleADX = iADX(m_symbol, m_timeframe, m_cfg.ADXPeriod);

      m_handleATR = iATR(m_symbol, m_timeframe, m_cfg.ATRPeriod);
   }

   virtual ~CPullbackStrategy()
   {
      if(m_handleEmaShort != INVALID_HANDLE) IndicatorRelease(m_handleEmaShort);
      if(m_handleEmaMid   != INVALID_HANDLE) IndicatorRelease(m_handleEmaMid);
      if(m_handleEmaLong  != INVALID_HANDLE) IndicatorRelease(m_handleEmaLong);
      if(m_handleADX      != INVALID_HANDLE) IndicatorRelease(m_handleADX);
      if(m_handleATR      != INVALID_HANDLE) IndicatorRelease(m_handleATR);
   }

   virtual void OnTick()
   {
      if(!IsNewBar()) return;
      if(HasPosition()) return;
      if(!FiltersOk()) return;

      bool buyTrend  = TrendIsBuy();
      bool sellTrend = TrendIsSell();

      if(buyTrend && PullbackBuySignal())
      {
         double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         double sl, tp;
         if(!CalcSLTP(ORDER_TYPE_BUY, ask, sl, tp)) return;

         string pattern = PullbackBuyPattern();

         if(m_trade.Buy(m_cfg.LotSize, m_symbol, ask, sl, tp, "PullbackBuy"))
         {
            CLogger::Log(LOG_INFO, "BUY placed");
            LogAiLearningRow("BUY", ask, pattern);
         }
         else
            CLogger::Log(LOG_ERROR, "BUY failed: " + (string)GetLastError());

         return;
      }

      if(sellTrend && PullbackSellSignal())
      {
         double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         double sl, tp;
         if(!CalcSLTP(ORDER_TYPE_SELL, bid, sl, tp)) return;

         string pattern = PullbackSellPattern();

         if(m_trade.Sell(m_cfg.LotSize, m_symbol, bid, sl, tp, "PullbackSell"))
         {
            CLogger::Log(LOG_INFO, "SELL placed");
            LogAiLearningRow("SELL", bid, pattern);
         }
         else
            CLogger::Log(LOG_ERROR, "SELL failed: " + (string)GetLastError());

         return;
      }
   }
};

#endif
