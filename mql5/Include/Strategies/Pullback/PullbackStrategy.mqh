#ifndef __PULLBACK_STRATEGY_MQH__
#define __PULLBACK_STRATEGY_MQH__

#include <Core/StrategyBase.mqh>
#include <Integration/Logger.mqh>
#include <Integration/AiLearningLogger.mqh>
#include <Strategies/Pullback/PullbackConfig.mqh>
#include <Strategies/Pullback/TrendLineDetector.mqh>
#include <Strategies/Pullback/ChannelDetector.mqh>

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

   // === トレンドライン/チャネル検出器 ===
   CTrendLineDetector m_trendLineDetector;
   CChannelDetector   m_channelDetector;

   // === MT4非OOP互換: プルバック検出状態管理 ===
   bool     m_pullbackDetected;         // プルバック検出フラグ
   bool     m_confirmationBarValidated; // 確認足検証済みフラグ
   bool     m_isPullbackLong;           // プルバック方向 (true=ロング)
   double   m_pullbackEntryLevel;       // エントリー価格レベル
   datetime m_pullbackBarTime;          // プルバック検出時刻
   string   m_pullbackType;             // プルバックタイプ文字列

   // === AIノイズ対策: 状態管理 ===
   datetime m_atrSpikeDetectedTime;     // ATRスパイク検出時刻
   int      m_atrSpikeWaitCounter;      // スパイク後待機カウンター
   datetime m_firstTouchTime;           // 最初のタッチ時刻（2度目狙い用）
   int      m_touchCount;               // タッチ回数
   datetime m_stopHuntDetectedTime;     // ストップ狩り検出時刻
   double   m_stopHuntLow;              // ストップ狩り時の安値
   double   m_stopHuntHigh;             // ストップ狩り時の高値

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

      // === AIノイズ対策: ATRスパイクフィルター ===
      if(!CheckATRSpikeFilter()) return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| AIノイズ対策: ATRスパイク検出 (モメンタム・イグニッション回避)     |
   //| ドキュメント: セクション5.3, 7.2B                                  |
   //+------------------------------------------------------------------+
   bool CheckATRSpikeFilter()
   {
      if(!m_cfg.UseATRSpikeFilter)
         return true;

      // スパイク後の待機中か確認
      if(m_atrSpikeWaitCounter > 0)
      {
         m_atrSpikeWaitCounter--;
         CLogger::Log(LOG_DEBUG, StringFormat("ATRスパイク待機中: 残り%d本", m_atrSpikeWaitCounter));
         return false;
      }

      // 現在ATRと過去平均ATRを比較
      double atrCurrent = 0.0;
      if(!Copy1(m_handleATR, 1, atrCurrent)) return true;

      double atrSum = 0.0;
      int validCount = 0;
      for(int i = 2; i <= m_cfg.ATRSpikeAvgBars + 1; i++)
      {
         double atr = 0.0;
         if(Copy1(m_handleATR, i, atr))
         {
            atrSum += atr;
            validCount++;
         }
      }

      if(validCount == 0) return true;

      double atrAvg = atrSum / validCount;
      double spikeRatio = atrCurrent / atrAvg;

      // スパイク検出
      if(spikeRatio >= m_cfg.ATRSpikeMultiplier)
      {
         m_atrSpikeDetectedTime = TimeCurrent();
         m_atrSpikeWaitCounter = m_cfg.ATRSpikeWaitBars;
         CLogger::Log(LOG_INFO, StringFormat("ATRスパイク検出: 現在ATR=%.1f, 平均ATR=%.1f, 比率=%.2f → %d本待機",
            atrCurrent / _Point, atrAvg / _Point, spikeRatio, m_cfg.ATRSpikeWaitBars));
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| AIノイズ対策: 2度目の動きを狙う (セクション9.2-5)                  |
   //+------------------------------------------------------------------+
   bool CheckSecondWaveEntry(bool isLong)
   {
      if(!m_cfg.UseSecondWaveEntry)
         return true;  // 無効時は常に許可

      datetime currentBarTime = iTime(m_symbol, m_timeframe, 1);

      // 最初のタッチを記録
      if(m_touchCount == 0)
      {
         m_firstTouchTime = currentBarTime;
         m_touchCount = 1;
         CLogger::Log(LOG_DEBUG, "2度目狙い: 1回目のタッチ記録");
         return false;  // 1回目はスキップ
      }

      // 2回目のタッチ判定
      int barsSinceFirst = (int)((currentBarTime - m_firstTouchTime) / PeriodSeconds(m_timeframe));

      if(barsSinceFirst < m_cfg.SecondWaveMinBars)
      {
         CLogger::Log(LOG_DEBUG, StringFormat("2度目狙い: 間隔不足 (%d本 < %d本)", barsSinceFirst, m_cfg.SecondWaveMinBars));
         return false;
      }

      if(barsSinceFirst > m_cfg.SecondWaveMaxBars)
      {
         // 期限切れ、リセット
         m_touchCount = 1;
         m_firstTouchTime = currentBarTime;
         CLogger::Log(LOG_DEBUG, "2度目狙い: 期限切れ、リセット");
         return false;
      }

      // 2回目の条件OK
      m_touchCount++;
      CLogger::Log(LOG_INFO, StringFormat("2度目狙い: %d回目のタッチ → エントリー許可", m_touchCount));
      return true;
   }

   //+------------------------------------------------------------------+
   //| AIノイズ対策: ストップ狩り検出 (セクション9.2-3)                   |
   //+------------------------------------------------------------------+
   bool DetectStopHunt()
   {
      if(!m_cfg.UsePostStopHuntEntry)
         return false;

      double spikeThreshold = m_cfg.StopHuntSpikePoints * _Point;

      // 直近N本の高値安値を確認
      for(int i = 1; i <= m_cfg.StopHuntRecoveryBars + 1; i++)
      {
         double high = iHigh(m_symbol, m_timeframe, i);
         double low = iLow(m_symbol, m_timeframe, i);
         double close = iClose(m_symbol, m_timeframe, i);
         double open = iOpen(m_symbol, m_timeframe, i);

         // 下ヒゲスパイク（ストップ狩り後の買いシグナル）
         double lowerWick = MathMin(open, close) - low;
         if(lowerWick >= spikeThreshold)
         {
            // 回復確認: 終値がオープン付近に戻っている
            if(close > low + spikeThreshold * 0.5)
            {
               m_stopHuntDetectedTime = iTime(m_symbol, m_timeframe, i);
               m_stopHuntLow = low;
               CLogger::Log(LOG_INFO, StringFormat("ストップ狩り検出(下): Low=%.5f, Wick=%.1fpts", low, lowerWick / _Point));
               return true;
            }
         }

         // 上ヒゲスパイク（ストップ狩り後の売りシグナル）
         double upperWick = high - MathMax(open, close);
         if(upperWick >= spikeThreshold)
         {
            if(close < high - spikeThreshold * 0.5)
            {
               m_stopHuntDetectedTime = iTime(m_symbol, m_timeframe, i);
               m_stopHuntHigh = high;
               CLogger::Log(LOG_INFO, StringFormat("ストップ狩り検出(上): High=%.5f, Wick=%.1fpts", high, upperWick / _Point));
               return true;
            }
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| AIノイズ対策: ストップ狩り後エントリー判定                         |
   //+------------------------------------------------------------------+
   bool CheckPostStopHuntEntry(bool isLong)
   {
      if(!m_cfg.UsePostStopHuntEntry)
         return true;  // 無効時は常に許可

      // ストップ狩り検出がなければスキップ
      if(m_stopHuntDetectedTime == 0)
         return true;

      // ストップ狩り後の回復を確認
      datetime currentBarTime = iTime(m_symbol, m_timeframe, 1);
      int barsSinceHunt = (int)((currentBarTime - m_stopHuntDetectedTime) / PeriodSeconds(m_timeframe));

      if(barsSinceHunt > m_cfg.StopHuntRecoveryBars)
      {
         // 回復確認OK
         double close1 = iClose(m_symbol, m_timeframe, 1);

         if(isLong && m_stopHuntLow > 0)
         {
            // 下方ストップ狩り後、価格が回復していればOK
            if(close1 > m_stopHuntLow + m_cfg.StopHuntSpikePoints * _Point * 0.7)
            {
               CLogger::Log(LOG_INFO, "ストップ狩り後エントリー許可 [Buy]");
               m_stopHuntDetectedTime = 0;  // リセット
               m_stopHuntLow = 0;
               return true;
            }
         }

         if(!isLong && m_stopHuntHigh > 0)
         {
            // 上方ストップ狩り後、価格が回復していればOK
            if(close1 < m_stopHuntHigh - m_cfg.StopHuntSpikePoints * _Point * 0.7)
            {
               CLogger::Log(LOG_INFO, "ストップ狩り後エントリー許可 [Sell]");
               m_stopHuntDetectedTime = 0;
               m_stopHuntHigh = 0;
               return true;
            }
         }
      }

      return false;  // まだ待機
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: EMA傾きチェック                                     |
   //+------------------------------------------------------------------+
   bool CheckEMASlope(bool isLong)
   {
      if(!m_cfg.UseEmaSlopeFilter)
         return true;

      int lookback = MathMax(1, m_cfg.EmaSlopeBars);

      // 短期EMA傾き
      if(m_cfg.EmaMinSlopeFast > 0.0)
      {
         double emaShort1 = 0.0, emaShortOld = 0.0;
         if(!Copy1(m_handleEmaShort, 1, emaShort1)) return false;
         if(!Copy1(m_handleEmaShort, lookback + 1, emaShortOld)) return false;
         double slopeFast = (emaShort1 - emaShortOld) / lookback;

         if(isLong && slopeFast < m_cfg.EmaMinSlopeFast) return false;
         if(!isLong && slopeFast > -m_cfg.EmaMinSlopeFast) return false;
      }

      // 長期EMA傾き
      if(m_cfg.EmaMinSlopeSlow > 0.0)
      {
         double emaLong1 = 0.0, emaLongOld = 0.0;
         if(!Copy1(m_handleEmaLong, 1, emaLong1)) return false;
         if(!Copy1(m_handleEmaLong, lookback + 1, emaLongOld)) return false;
         double slopeSlow = (emaLong1 - emaLongOld) / lookback;

         if(isLong && slopeSlow < m_cfg.EmaMinSlopeSlow) return false;
         if(!isLong && slopeSlow > -m_cfg.EmaMinSlopeSlow) return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: ローソク足条件チェック                               |
   //+------------------------------------------------------------------+
   bool CheckCandleCondition(bool isLong)
   {
      if(!m_cfg.UseCandleCondition)
         return true;

      double open1 = iOpen(m_symbol, m_timeframe, 1);
      double close1 = iClose(m_symbol, m_timeframe, 1);
      double high1 = iHigh(m_symbol, m_timeframe, 1);
      double low1 = iLow(m_symbol, m_timeframe, 1);

      double body = MathAbs(close1 - open1);
      double totalRange = high1 - low1;

      // 実体比率チェック
      if(totalRange > 0)
      {
         double bodyPercent = (body / totalRange) * 100.0;
         if(bodyPercent < m_cfg.MinCandleBodyPercent)
            return false;
      }

      // ロング: 陽線が望ましい（実体の方向チェック）
      if(isLong && close1 < open1)
      {
         // 陰線だがボディが十分小さければ許容（ドジ足）
         if((body / totalRange) * 100.0 > 30.0)
            return false;
      }

      // ショート: 陰線が望ましい
      if(!isLong && close1 > open1)
      {
         if((body / totalRange) * 100.0 > 30.0)
            return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: 確認足サイズチェック                                 |
   //+------------------------------------------------------------------+
   bool CheckConfirmationBarSize()
   {
      double high1 = iHigh(m_symbol, m_timeframe, 1);
      double low1 = iLow(m_symbol, m_timeframe, 1);
      double barSizePips = (high1 - low1) / (_Point * 10);  // pips変換

      if(barSizePips < m_cfg.ConfirmationBarMinPips)
         return false;

      if(m_cfg.ConfirmationBarMaxPips > 0 && barSizePips > m_cfg.ConfirmationBarMaxPips)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: 強トレンドモードチェック                             |
   //+------------------------------------------------------------------+
   bool ShouldActivateStrongTrendMode()
   {
      if(!m_cfg.UseStrongTrendMode)
         return false;

      if(m_cfg.StrongTrendAutoActivate)
      {
         // 自動判定: ADXが高い場合に自動的に有効化
         double adx = 0.0;
         if(!CopyAdxMain(1, adx)) return false;
         return (adx > m_cfg.StrongTrendADXLevel);
      }

      return true;  // 手動有効時は常にtrue
   }

   //+------------------------------------------------------------------+
   //| Al Brooks理論: 連続陽線/陰線の検出                                 |
   //| N本連続で同方向の足があれば強トレンドと判断                          |
   //+------------------------------------------------------------------+
   bool DetectConsecutiveBars(bool isLong, int lookback = 10)
   {
      int consecutiveCount = 0;
      int requiredCount = m_cfg.ConsecutiveBarsCount;
      if(requiredCount <= 0) requiredCount = 3;  // デフォルト3本

      for(int i = 1; i <= lookback; i++)
      {
         double open = iOpen(m_symbol, m_timeframe, i);
         double close = iClose(m_symbol, m_timeframe, i);

         bool isBullish = close > open;
         bool isBearish = close < open;

         if(isLong && isBullish)
         {
            consecutiveCount++;
            if(consecutiveCount >= requiredCount)
               return true;
         }
         else if(!isLong && isBearish)
         {
            consecutiveCount++;
            if(consecutiveCount >= requiredCount)
               return true;
         }
         else
         {
            consecutiveCount = 0;  // リセット
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Al Brooks理論: 大陽線/大陰線の検出                                 |
   //| ATRの指定倍数以上の大きなローソク足を検出                           |
   //+------------------------------------------------------------------+
   bool DetectLargeCandle(bool isLong, int lookback = 5)
   {
      double multiplier = m_cfg.LargeCandleMultiplier;
      if(multiplier <= 0) multiplier = 1.5;  // デフォルト1.5倍

      double atrBuffer[];
      if(CopyBuffer(m_handleATR, 0, 1, 1, atrBuffer) != 1)
         return false;
      double atr = atrBuffer[0];

      double threshold = atr * multiplier;

      for(int i = 1; i <= lookback; i++)
      {
         double open = iOpen(m_symbol, m_timeframe, i);
         double close = iClose(m_symbol, m_timeframe, i);
         double bodySize = MathAbs(close - open);

         bool isBullish = close > open;
         bool isBearish = close < open;

         if(bodySize >= threshold)
         {
            if(isLong && isBullish)
               return true;
            if(!isLong && isBearish)
               return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Al Brooks理論: 浅いプルバック検出                                  |
   //| 直近のスイングからShallowPullbackPercent%以下の戻しでエントリー許可  |
   //+------------------------------------------------------------------+
   bool DetectShallowPullback(bool isLong)
   {
      double pullbackPercent = m_cfg.ShallowPullbackPercent;
      if(pullbackPercent <= 0) pullbackPercent = 40.0;  // デフォルト40%

      // 直近10本でスイングハイ/ローを探す
      double swingHigh = 0.0, swingLow = DBL_MAX;
      for(int i = 1; i <= 10; i++)
      {
         double high = iHigh(m_symbol, m_timeframe, i);
         double low = iLow(m_symbol, m_timeframe, i);
         if(high > swingHigh) swingHigh = high;
         if(low < swingLow) swingLow = low;
      }

      double swingRange = swingHigh - swingLow;
      if(swingRange <= 0) return false;

      double currentClose = iClose(m_symbol, m_timeframe, 1);

      if(isLong)
      {
         // ロング: 高値からの戻し率を計算
         double pullbackFromHigh = swingHigh - currentClose;
         double retracementPercent = (pullbackFromHigh / swingRange) * 100.0;
         // 浅い戻し(pullbackPercent%以下)ならtrue
         if(retracementPercent > 0 && retracementPercent <= pullbackPercent)
         {
            m_pullbackType = "ShallowPullback";
            return true;
         }
      }
      else
      {
         // ショート: 安値からの戻し率を計算
         double pullbackFromLow = currentClose - swingLow;
         double retracementPercent = (pullbackFromLow / swingRange) * 100.0;
         // 浅い戻し(pullbackPercent%以下)ならtrue
         if(retracementPercent > 0 && retracementPercent <= pullbackPercent)
         {
            m_pullbackType = "ShallowPullback";
            return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Al Brooks理論: ブレイクアウトバー検出                              |
   //| 直近のレジサポをブレイクした大きな足でプルバック待たずにエントリー     |
   //+------------------------------------------------------------------+
   bool CheckBreakoutBarEntry(bool isLong)
   {
      if(!m_cfg.UseBreakoutBarEntry)
         return false;

      double bar1High = iHigh(m_symbol, m_timeframe, 1);
      double bar1Low = iLow(m_symbol, m_timeframe, 1);
      double bar1Open = iOpen(m_symbol, m_timeframe, 1);
      double bar1Close = iClose(m_symbol, m_timeframe, 1);
      double bar1Body = MathAbs(bar1Close - bar1Open);
      double bar1Range = bar1High - bar1Low;

      // ボディ比率チェック
      double minBodyRatio = m_cfg.MinBarBodyRatio;
      if(minBodyRatio <= 0) minBodyRatio = 60.0;
      if(bar1Range > 0)
      {
         double bodyRatio = (bar1Body / bar1Range) * 100.0;
         if(bodyRatio < minBodyRatio)
            return false;
      }

      // 過去10本の高値/安値を探す（バー1を除く）
      double prevHigh = 0.0, prevLow = DBL_MAX;
      for(int i = 2; i <= 11; i++)
      {
         double h = iHigh(m_symbol, m_timeframe, i);
         double l = iLow(m_symbol, m_timeframe, i);
         if(h > prevHigh) prevHigh = h;
         if(l < prevLow) prevLow = l;
      }

      if(isLong)
      {
         // ロング: 直近高値を超えてブレイクアウト
         if(bar1Close > prevHigh && bar1Close > bar1Open)
         {
            m_pullbackType = "BreakoutBarEntry";
            return true;
         }
      }
      else
      {
         // ショート: 直近安値を割ってブレイクアウト
         if(bar1Close < prevLow && bar1Close < bar1Open)
         {
            m_pullbackType = "BreakoutBarEntry";
            return true;
         }
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| Al Brooks理論: ボディ比率チェック                                  |
   //| ヒゲが少ない（ボディ比率が高い）足を検出                            |
   //+------------------------------------------------------------------+
   bool CheckBarBodyRatio(int barIndex = 1)
   {
      double high = iHigh(m_symbol, m_timeframe, barIndex);
      double low = iLow(m_symbol, m_timeframe, barIndex);
      double open = iOpen(m_symbol, m_timeframe, barIndex);
      double close = iClose(m_symbol, m_timeframe, barIndex);

      double range = high - low;
      if(range <= 0) return false;

      double body = MathAbs(close - open);
      double bodyRatio = (body / range) * 100.0;

      double minBodyRatio = m_cfg.MinBarBodyRatio;
      if(minBodyRatio <= 0) minBodyRatio = 60.0;

      return (bodyRatio >= minBodyRatio);
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換 + Al Brooks拡張: 強トレンドモードでのプルバック検出     |
   //+------------------------------------------------------------------+
   bool DetectStrongTrendPullback(bool isLong)
   {
      if(!ShouldActivateStrongTrendMode())
         return false;

      double adx = 0.0;
      if(!CopyAdxMain(1, adx)) return false;
      if(adx <= m_cfg.StrongTrendADXLevel)
         return false;

      // === Al Brooks理論: ブレイクアウトバーエントリー（最優先） ===
      if(CheckBreakoutBarEntry(isLong))
         return true;

      // === Al Brooks理論: 連続陽線/陰線でトレンド確認 ===
      bool hasConsecutiveBars = DetectConsecutiveBars(isLong);

      // === Al Brooks理論: 大陽線/大陰線でモメンタム確認 ===
      bool hasLargeCandle = DetectLargeCandle(isLong);

      // 連続足または大足が検出された場合
      if(hasConsecutiveBars || hasLargeCandle)
      {
         // 浅いプルバックでエントリー許可
         if(DetectShallowPullback(isLong))
         {
            if(hasConsecutiveBars && hasLargeCandle)
               m_pullbackType = "StrongTrend_Consecutive+Large+Shallow";
            else if(hasConsecutiveBars)
               m_pullbackType = "StrongTrend_Consecutive+Shallow";
            else
               m_pullbackType = "StrongTrend_Large+Shallow";
            return true;
         }

         // ボディ比率の高い足でエントリー許可
         if(CheckBarBodyRatio(1))
         {
            if(hasConsecutiveBars && hasLargeCandle)
               m_pullbackType = "StrongTrend_Consecutive+Large+BodyRatio";
            else if(hasConsecutiveBars)
               m_pullbackType = "StrongTrend_Consecutive+BodyRatio";
            else
               m_pullbackType = "StrongTrend_Large+BodyRatio";
            return true;
         }
      }

      // === 従来のEMA12タッチ検出（フォールバック） ===
      for(int i = 1; i <= 5; i++)
      {
         double barHigh = iHigh(m_symbol, m_timeframe, i);
         double barLow = iLow(m_symbol, m_timeframe, i);
         double barClose = iClose(m_symbol, m_timeframe, i);

         double emaShort = 0.0;
         if(!Copy1(m_handleEmaShort, i, emaShort)) continue;

         // ロング: 安値がEMA12にタッチ → 終値がEMA12より上
         if(isLong && barLow <= emaShort && barClose > emaShort)
         {
            m_pullbackType = "StrongTrendEMA12Touch";
            return true;
         }

         // ショート: 高値がEMA12にタッチ → 終値がEMA12より下
         if(!isLong && barHigh >= emaShort && barClose < emaShort)
         {
            m_pullbackType = "StrongTrendEMA12Touch";
            return true;
         }
      }

      return false;
   }

   bool m_allowBuy;
   bool m_allowSell;

   bool TrendIsBuy()
   {
      if(!m_allowBuy) return false;
      
      double s, m, l;
      if(!GetEmaValues(1, s, m, l)) return false;

      // MT4非OOP互換: EMA傾きチェック
      if(!CheckEMASlope(true)) return false;
      
      // MT4互換: RequirePerfectOrder=falseなら価格がEMA上にあればOK
      if(!m_cfg.RequirePerfectOrder)
      {
         double close1 = iClose(m_symbol, m_timeframe, 1);
         // 少なくとも1つの有効EMAより上にあればトレンドアップとみなす
         if(m_cfg.UseEmaShort && close1 > s) return true;
         if(m_cfg.UseEmaMid && close1 > m) return true;
         if(m_cfg.UseEmaLong && close1 > l) return true;
         return false;
      }

      // Check adjacent pairs if both are enabled
      // Sequence: Short -> Mid -> Long
      
      // Short vs Mid
      if(m_cfg.UseEmaShort && m_cfg.UseEmaMid)
      {
         if(s <= m) return false;
      }

      // Mid vs Long
      if(m_cfg.UseEmaMid && m_cfg.UseEmaLong)
      {
         if(m <= l) return false;
      }

      // Short vs Long (if Mid is disabled, we check S > L directly? Or do we assume S > L is implied?)
      // If we have S, M, L: S>M and M>L implies S>L.
      // If we have S, L (M off): S>L.
      if(m_cfg.UseEmaShort && m_cfg.UseEmaLong && !m_cfg.UseEmaMid)
      {
         if(s <= l) return false;
      }

      return true;
   }

   bool TrendIsSell()
   {
      if(!m_allowSell) return false;

      double s, m, l;
      if(!GetEmaValues(1, s, m, l)) return false;

      // MT4非OOP互換: EMA傾きチェック
      if(!CheckEMASlope(false)) return false;

      // MT4互換: RequirePerfectOrder=falseなら価格がEMA下にあればOK
      if(!m_cfg.RequirePerfectOrder)
      {
         double close1 = iClose(m_symbol, m_timeframe, 1);
         // 少なくとも1つの有効EMAより下にあればトレンドダウンとみなす
         if(m_cfg.UseEmaShort && close1 < s) return true;
         if(m_cfg.UseEmaMid && close1 < m) return true;
         if(m_cfg.UseEmaLong && close1 < l) return true;
         return false;
      }

      // Short vs Mid
      if(m_cfg.UseEmaShort && m_cfg.UseEmaMid)
      {
         if(s >= m) return false;
      }

      // Mid vs Long
      if(m_cfg.UseEmaMid && m_cfg.UseEmaLong)
      {
         if(m >= l) return false;
      }

      // Short vs Long (only if Mid is disabled)
      if(m_cfg.UseEmaShort && m_cfg.UseEmaLong && !m_cfg.UseEmaMid)
      {
         if(s >= l) return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: プルバック検出 (Lookback対応)                        |
   //+------------------------------------------------------------------+
   bool PullbackBuySignal()
   {
      // 強トレンドモードチェック
      if(DetectStrongTrendPullback(true))
      {
         m_pullbackType = "StrongTrendEMA12Touch";
         return true;
      }

      int refPeriod = EmaRefPeriod();
      int hRef = iMA(m_symbol, m_timeframe, refPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hRef == INVALID_HANDLE) return false;

      int lookback = MathMax(1, MathMin(m_cfg.PullbackLookback, 10));

      // 過去N本を遡ってプルバックを探す
      for(int i = 1; i <= lookback; i++)
      {
         double close_i = iClose(m_symbol, m_timeframe, i);
         double close_prev = iClose(m_symbol, m_timeframe, i + 1);
         double low_i = iLow(m_symbol, m_timeframe, i);
         double high_i = iHigh(m_symbol, m_timeframe, i);

         double buf[];
         ArraySetAsSeries(buf, true);
         if(CopyBuffer(hRef, 0, i, 2, buf) != 2) continue;
         double ema_i = buf[0];
         double ema_prev = buf[1];

         // タイプA: EMAタッチ
         if(m_cfg.UseTouchPullback && low_i <= ema_i && high_i >= ema_i)
         {
            IndicatorRelease(hRef);
            m_pullbackType = "touch";
            m_pullbackEntryLevel = high_i;  // ブレイクレベル設定
            return true;
         }

         // タイプB: EMAクロス
         if(m_cfg.UseCrossPullback)
         {
            double low_prev = iLow(m_symbol, m_timeframe, i + 1);
            if(low_prev < ema_prev && high_i > ema_i)
            {
               IndicatorRelease(hRef);
               m_pullbackType = "cross";
               m_pullbackEntryLevel = high_i;
               return true;
            }
         }

         // タイプC: EMA完全ブレイク
         if(m_cfg.UseBreakPullback)
         {
            if(close_prev < ema_prev && close_i > ema_i)
            {
               IndicatorRelease(hRef);
               m_pullbackType = "break";
               m_pullbackEntryLevel = high_i;
               return true;
            }
         }
      }

      IndicatorRelease(hRef);
      return false;
   }

   string PullbackBuyPattern()
   {
      return m_pullbackType;
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: Sell側プルバック検出 (Lookback対応)                  |
   //+------------------------------------------------------------------+
   bool PullbackSellSignal()
   {
      // 強トレンドモードチェック
      if(DetectStrongTrendPullback(false))
      {
         m_pullbackType = "StrongTrendEMA12Touch";
         return true;
      }

      int refPeriod = EmaRefPeriod();
      int hRef = iMA(m_symbol, m_timeframe, refPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hRef == INVALID_HANDLE) return false;

      int lookback = MathMax(1, MathMin(m_cfg.PullbackLookback, 10));

      // 過去N本を遡ってプルバックを探す
      for(int i = 1; i <= lookback; i++)
      {
         double close_i = iClose(m_symbol, m_timeframe, i);
         double close_prev = iClose(m_symbol, m_timeframe, i + 1);
         double low_i = iLow(m_symbol, m_timeframe, i);
         double high_i = iHigh(m_symbol, m_timeframe, i);

         double buf[];
         ArraySetAsSeries(buf, true);
         if(CopyBuffer(hRef, 0, i, 2, buf) != 2) continue;
         double ema_i = buf[0];
         double ema_prev = buf[1];

         // タイプA: EMAタッチ
         if(m_cfg.UseTouchPullback && high_i >= ema_i && low_i <= ema_i)
         {
            IndicatorRelease(hRef);
            m_pullbackType = "touch";
            m_pullbackEntryLevel = low_i;  // ブレイクレベル設定
            return true;
         }

         // タイプB: EMAクロス
         if(m_cfg.UseCrossPullback)
         {
            double high_prev = iHigh(m_symbol, m_timeframe, i + 1);
            if(high_prev > ema_prev && low_i < ema_i)
            {
               IndicatorRelease(hRef);
               m_pullbackType = "cross";
               m_pullbackEntryLevel = low_i;
               return true;
            }
         }

         // タイプC: EMA完全ブレイク
         if(m_cfg.UseBreakPullback)
         {
            if(close_prev > ema_prev && close_i < ema_i)
            {
               IndicatorRelease(hRef);
               m_pullbackType = "break";
               m_pullbackEntryLevel = low_i;
               return true;
            }
         }
      }

      IndicatorRelease(hRef);
      return false;
   }

   string PullbackSellPattern()
   {
      return m_pullbackType;
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
         double a = 0.0;
         if(Copy1(m_handleATR, i, a) && a > 0.0)
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
   void SetAllowedDirections(bool allowBuy, bool allowSell)
   {
      m_allowBuy = allowBuy;
      m_allowSell = allowSell;
   }

   CPullbackConfig* GetCfgPointer() { return &m_cfg; }

   CPullbackStrategy(string symbol, ENUM_TIMEFRAMES timeframe, const CPullbackConfig &cfg)
   : CStrategyBase(symbol, timeframe),
     m_cfg(cfg),
     m_allowBuy(true),
     m_allowSell(true),
     m_handleEmaShort(INVALID_HANDLE),
     m_handleEmaMid(INVALID_HANDLE),
     m_handleEmaLong(INVALID_HANDLE),
     m_handleADX(INVALID_HANDLE),
     m_handleATR(INVALID_HANDLE),
     m_lastBarTime(0),
     m_pullbackDetected(false),
     m_confirmationBarValidated(false),
     m_isPullbackLong(false),
     m_pullbackEntryLevel(0.0),
     m_pullbackBarTime(0),
     m_pullbackType(""),
     m_atrSpikeDetectedTime(0),
     m_atrSpikeWaitCounter(0),
     m_firstTouchTime(0),
     m_touchCount(0),
     m_stopHuntDetectedTime(0),
     m_stopHuntLow(0.0),
     m_stopHuntHigh(0.0)
   {
      m_trade.Configure(m_cfg.MagicNumber, m_cfg.DeviationPoints, ORDER_FILLING_IOC);
      m_aiLogger.Configure(m_cfg.EnableAiLearningLog, m_cfg.TerminalId, m_cfg.AiLearningFolder);

      m_handleEmaShort = iMA(m_symbol, m_timeframe, m_cfg.EmaShortPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleEmaMid   = iMA(m_symbol, m_timeframe, m_cfg.EmaMidPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleEmaLong  = iMA(m_symbol, m_timeframe, m_cfg.EmaLongPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(m_cfg.UseADXFilter)
         m_handleADX = iADX(m_symbol, m_timeframe, m_cfg.ADXPeriod);

      m_handleATR = iATR(m_symbol, m_timeframe, m_cfg.ATRPeriod);

      // トレンドライン/チャネル検出器の初期化
      m_trendLineDetector.Init(m_symbol, m_timeframe, GetCfgPointer());
      m_channelDetector.Init(m_symbol, m_timeframe, GetCfgPointer());
   }

   virtual ~CPullbackStrategy()
   {
      if(m_handleEmaShort != INVALID_HANDLE) IndicatorRelease(m_handleEmaShort);
      if(m_handleEmaMid   != INVALID_HANDLE) IndicatorRelease(m_handleEmaMid);
      if(m_handleEmaLong  != INVALID_HANDLE) IndicatorRelease(m_handleEmaLong);
      if(m_handleADX      != INVALID_HANDLE) IndicatorRelease(m_handleADX);
      if(m_handleATR      != INVALID_HANDLE) IndicatorRelease(m_handleATR);
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: 状態リセット                                        |
   //+------------------------------------------------------------------+
   void ResetPullbackState()
   {
      m_pullbackDetected = false;
      m_confirmationBarValidated = false;
      m_pullbackEntryLevel = 0.0;
      m_pullbackType = "";
      // AIノイズ対策: 2度目狙いのリセット
      m_touchCount = 0;
      m_firstTouchTime = 0;
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: 確認足チェック                                      |
   //+------------------------------------------------------------------+
   void CheckConfirmationBarEntry()
   {
      if(!m_pullbackDetected) return;
      if(m_confirmationBarValidated) return;  // 既に検証済み

      // 確認足サイズチェック
      if(!CheckConfirmationBarSize())
      {
         ResetPullbackState();
         return;
      }

      // ローソク足条件チェック
      if(!CheckCandleCondition(m_isPullbackLong))
      {
         ResetPullbackState();
         return;
      }

      // エントリーレベルを確認足の高値/安値に更新
      double high1 = iHigh(m_symbol, m_timeframe, 1);
      double low1 = iLow(m_symbol, m_timeframe, 1);
      m_pullbackEntryLevel = m_isPullbackLong ? high1 : low1;
      m_confirmationBarValidated = true;

      CLogger::Log(LOG_DEBUG, StringFormat("確認足OK: エントリーレベル=%s", 
         DoubleToString(m_pullbackEntryLevel, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS))));
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: 価格ブレイクエントリーチェック（毎Tick）              |
   //+------------------------------------------------------------------+
   bool CheckPriceBreakEntry()
   {
      if(!m_pullbackDetected) return false;

      // 確認足モードで未検証の場合はスキップ
      if(m_cfg.UseConfirmationBar && !m_confirmationBarValidated)
         return false;

      double buffer = m_cfg.EntryBreakBufferPips * _Point * 10;  // pips→points変換
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(m_isPullbackLong)
      {
         if(ask >= m_pullbackEntryLevel + buffer)
            return true;
      }
      else
      {
         if(bid <= m_pullbackEntryLevel - buffer)
            return true;
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| MT4非OOP互換: エントリー実行                                      |
   //+------------------------------------------------------------------+
   void ExecuteEntry(bool isLong)
   {
      double price = isLong ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double sl, tp;
      
      ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!CalcSLTP(orderType, price, sl, tp)) 
      {
         ResetPullbackState();
         return;
      }

      string pattern = m_pullbackType;
      string comment = isLong ? "PullbackBuy" : "PullbackSell";

      bool success = isLong 
         ? m_trade.Buy(m_cfg.LotSize, m_symbol, price, sl, tp, comment)
         : m_trade.Sell(m_cfg.LotSize, m_symbol, price, sl, tp, comment);

      if(success)
      {
         CLogger::Log(LOG_INFO, StringFormat("%s placed [%s]", (isLong ? "BUY" : "SELL"), pattern));
         LogAiLearningRow((isLong ? "BUY" : "SELL"), price, pattern);
      }
      else
      {
         CLogger::Log(LOG_ERROR, StringFormat("ENTRY_FAILED: %s failure. Error=%d", 
            (isLong ? "BUY" : "SELL"), GetLastError()));
      }

      ResetPullbackState();
   }

   //+------------------------------------------------------------------+
   //| トレンドラインモード: プルバック検出                               |
   //+------------------------------------------------------------------+
   bool TrendLinePullbackBuySignal()
   {
      int signalType = 0;
      if(m_trendLineDetector.DetectTrendlinePullback(true, signalType))
      {
         switch(signalType)
         {
            case 1: m_pullbackType = "TL_touch"; break;
            case 2: m_pullbackType = "TL_cross"; break;
            case 3: m_pullbackType = "TL_break"; break;
         }
         m_pullbackEntryLevel = iHigh(m_symbol, m_timeframe, 1);
         return true;
      }
      return false;
   }

   bool TrendLinePullbackSellSignal()
   {
      int signalType = 0;
      if(m_trendLineDetector.DetectTrendlinePullback(false, signalType))
      {
         switch(signalType)
         {
            case 1: m_pullbackType = "TL_touch"; break;
            case 2: m_pullbackType = "TL_cross"; break;
            case 3: m_pullbackType = "TL_break"; break;
         }
         m_pullbackEntryLevel = iLow(m_symbol, m_timeframe, 1);
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| チャネルモード: 逆張りシグナル検出                                 |
   //+------------------------------------------------------------------+
   int ChannelReversalSignal()
   {
      int signalType = 0;
      int direction = m_channelDetector.DetectChannelReversalSignal(signalType);
      
      if(direction != 0)
      {
         switch(signalType)
         {
            case 1: m_pullbackType = "CH_touch"; break;
            case 2: m_pullbackType = "CH_cross"; break;
            case 3: m_pullbackType = "CH_break"; break;
         }
         
         if(direction > 0)
            m_pullbackEntryLevel = iHigh(m_symbol, m_timeframe, 1);
         else
            m_pullbackEntryLevel = iLow(m_symbol, m_timeframe, 1);
      }
      
      return direction;  // 1=ロング, -1=ショート, 0=なし
   }

   //+------------------------------------------------------------------+
   //| トレンドラインモード処理                                          |
   //+------------------------------------------------------------------+
   void ProcessTrendLineMode()
   {
      // トレンドライン更新（新バー時）
      m_trendLineDetector.Update();

      // トレンドラインでトレンド判定
      int trend = m_trendLineDetector.CheckTrendWithTrendLine();

      // Buy処理
      if(trend > 0 && m_allowBuy && TrendLinePullbackBuySignal())
      {
         if(!CheckCandleCondition(true)) return;

         m_pullbackDetected = true;
         m_isPullbackLong = true;
         m_pullbackBarTime = iTime(m_symbol, m_timeframe, 1);

         if(m_cfg.UseConfirmationBar)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("TLプルバック検出 [Buy/%s] → 確認足待機", m_pullbackType));
            m_confirmationBarValidated = false;
            return;
         }

         if(m_cfg.RequirePriceBreak)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("TLプルバック検出 [Buy/%s] → ブレイク待機", m_pullbackType));
            return;
         }

         ExecuteEntry(true);
         return;
      }

      // Sell処理
      if(trend < 0 && m_allowSell && TrendLinePullbackSellSignal())
      {
         if(!CheckCandleCondition(false)) return;

         m_pullbackDetected = true;
         m_isPullbackLong = false;
         m_pullbackBarTime = iTime(m_symbol, m_timeframe, 1);

         if(m_cfg.UseConfirmationBar)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("TLプルバック検出 [Sell/%s] → 確認足待機", m_pullbackType));
            m_confirmationBarValidated = false;
            return;
         }

         if(m_cfg.RequirePriceBreak)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("TLプルバック検出 [Sell/%s] → ブレイク待機", m_pullbackType));
            return;
         }

         ExecuteEntry(false);
      }
   }

   //+------------------------------------------------------------------+
   //| チャネルモード処理（逆張り）                                       |
   //+------------------------------------------------------------------+
   void ProcessChannelMode()
   {
      // チャネル更新
      m_channelDetector.Update();

      if(!m_channelDetector.HasValidChannel())
         return;

      // 逆張りシグナル検出
      int signal = ChannelReversalSignal();

      if(signal > 0 && m_allowBuy)
      {
         if(!CheckCandleCondition(true)) return;

         m_pullbackDetected = true;
         m_isPullbackLong = true;
         m_pullbackBarTime = iTime(m_symbol, m_timeframe, 1);

         if(m_cfg.UseConfirmationBar)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("CHリバーサル検出 [Buy/%s] → 確認足待機", m_pullbackType));
            m_confirmationBarValidated = false;
            return;
         }

         if(m_cfg.RequirePriceBreak)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("CHリバーサル検出 [Buy/%s] → ブレイク待機", m_pullbackType));
            return;
         }

         ExecuteEntry(true);
         return;
      }

      if(signal < 0 && m_allowSell)
      {
         if(!CheckCandleCondition(false)) return;

         m_pullbackDetected = true;
         m_isPullbackLong = false;
         m_pullbackBarTime = iTime(m_symbol, m_timeframe, 1);

         if(m_cfg.UseConfirmationBar)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("CHリバーサル検出 [Sell/%s] → 確認足待機", m_pullbackType));
            m_confirmationBarValidated = false;
            return;
         }

         if(m_cfg.RequirePriceBreak)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("CHリバーサル検出 [Sell/%s] → ブレイク待機", m_pullbackType));
            return;
         }

         ExecuteEntry(false);
      }
   }

   //+------------------------------------------------------------------+
   //| EMAモード処理（従来のロジック）                                    |
   //+------------------------------------------------------------------+
   void ProcessEmaMode()
   {
      // === プルバック検出 ===
      bool buyTrend  = TrendIsBuy();
      bool sellTrend = TrendIsSell();

      if(buyTrend && PullbackBuySignal())
      {
         // ローソク足条件チェック
         if(!CheckCandleCondition(true))
         {
            CLogger::Log(LOG_DEBUG, "ローソク足条件不適合 [Buy]");
            return;
         }

         m_pullbackDetected = true;
         m_isPullbackLong = true;
         m_pullbackBarTime = iTime(m_symbol, m_timeframe, 1);

         if(m_cfg.UseConfirmationBar)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("プルバック検出 [Buy/%s] → 確認足待機", m_pullbackType));
            m_confirmationBarValidated = false;
            return;
         }

         if(m_cfg.RequirePriceBreak)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("プルバック検出 [Buy/%s] → ブレイク待機 (Level=%s)", 
               m_pullbackType, DoubleToString(m_pullbackEntryLevel, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS))));
            return;
         }

         ExecuteEntry(true);
         return;
      }

      if(sellTrend && PullbackSellSignal())
      {
         // ローソク足条件チェック
         if(!CheckCandleCondition(false))
         {
            CLogger::Log(LOG_DEBUG, "ローソク足条件不適合 [Sell]");
            return;
         }

         m_pullbackDetected = true;
         m_isPullbackLong = false;
         m_pullbackBarTime = iTime(m_symbol, m_timeframe, 1);

         if(m_cfg.UseConfirmationBar)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("プルバック検出 [Sell/%s] → 確認足待機", m_pullbackType));
            m_confirmationBarValidated = false;
            return;
         }

         if(m_cfg.RequirePriceBreak)
         {
            CLogger::Log(LOG_DEBUG, StringFormat("プルバック検出 [Sell/%s] → ブレイク待機 (Level=%s)", 
               m_pullbackType, DoubleToString(m_pullbackEntryLevel, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS))));
            return;
         }

         ExecuteEntry(false);
         return;
      }
   }

   virtual void OnTick()
   {
      // ポジションチェック
      if(HasPosition())
      {
         ResetPullbackState();
         return;
      }

      // === 毎Tick: 価格ブレイクエントリーチェック ===
      if(m_pullbackDetected && m_cfg.RequirePriceBreak)
      {
         if(CheckPriceBreakEntry())
         {
            ExecuteEntry(m_isPullbackLong);
            return;
         }
      }

      // === 新規バー処理 ===
      if(!IsNewBar()) return;

      // フィルターチェック
      if(!FiltersOk())
      {
         ResetPullbackState();
         return;
      }

      // 確認足モード: 確認足チェック
      if(m_pullbackDetected && m_cfg.UseConfirmationBar)
      {
         CheckConfirmationBarEntry();
         
         // 価格ブレイク不要の場合、確認足検証後すぐエントリー
         if(m_confirmationBarValidated && !m_cfg.RequirePriceBreak)
         {
            ExecuteEntry(m_isPullbackLong);
            return;
         }
      }

      // === モード別処理 ===
      switch(m_cfg.TLChannelMode)
      {
         case MODE_TRENDLINE_TREND:
            ProcessTrendLineMode();
            break;
            
         case MODE_CHANNEL_RANGE:
            ProcessChannelMode();
            break;
            
         case MODE_EMA_ONLY:
         default:
            ProcessEmaMode();
            break;
      }
   }
};

#endif
