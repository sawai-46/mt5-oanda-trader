//+------------------------------------------------------------------+
//|                          ChannelDetector.mqh                     |
//|                 設計書セクション13: チャネルライン逆張り機能        |
//+------------------------------------------------------------------+
#ifndef __CHANNEL_DETECTOR_MQH__
#define __CHANNEL_DETECTOR_MQH__

#include <Strategies/Pullback/PullbackConfig.mqh>

//+------------------------------------------------------------------+
//| チャネル情報構造体                                                |
//+------------------------------------------------------------------+
struct SChannel
{
   // 上限ライン (レジスタンス)
   double   upperSlope;
   double   upperIntercept;
   
   // 下限ライン (サポート)
   double   lowerSlope;
   double   lowerIntercept;
   
   double   width;           // チャネル幅 (ポイント)
   int      direction;       // チャネル方向: 1=上昇, -1=下降, 0=水平
   datetime lastUpdate;
   bool     isValid;
   
   void Reset()
   {
      upperSlope = 0.0;
      upperIntercept = 0.0;
      lowerSlope = 0.0;
      lowerIntercept = 0.0;
      width = 0.0;
      direction = 0;
      lastUpdate = 0;
      isValid = false;
   }
};

//+------------------------------------------------------------------+
//| チャネル検出クラス                                                |
//+------------------------------------------------------------------+
class CChannelDetector
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   CPullbackConfig*  m_cfg;
   
   SChannel          m_channel;
   datetime          m_lastUpdateTime;
   
   //+------------------------------------------------------------------+
   //| ATR値を取得                                                      |
   //+------------------------------------------------------------------+
   double GetATR(int period = 14, int shift = 1)
   {
      int handle = iATR(m_symbol, m_timeframe, period);
      if(handle == INVALID_HANDLE) return 0.0;
      double buffer[1];
      if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0) return 0.0;
      IndicatorRelease(handle);
      return buffer[0];
   }
   
   //+------------------------------------------------------------------+
   //| スイングロー（極小点）検出                                        |
   //+------------------------------------------------------------------+
   int FindSwingLows(int &swingBars[], double &swingPrices[], int lookback)
   {
      ArrayResize(swingBars, 0);
      ArrayResize(swingPrices, 0);
      int count = 0;
      
      for(int i = 2; i < lookback - 2; i++)
      {
         double lowCenter = iLow(m_symbol, m_timeframe, i);
         double lowLeft1 = iLow(m_symbol, m_timeframe, i - 1);
         double lowLeft2 = iLow(m_symbol, m_timeframe, i - 2);
         double lowRight1 = iLow(m_symbol, m_timeframe, i + 1);
         double lowRight2 = iLow(m_symbol, m_timeframe, i + 2);
         
         if(lowCenter < lowLeft1 && lowCenter < lowLeft2 &&
            lowCenter < lowRight1 && lowCenter < lowRight2)
         {
            ArrayResize(swingBars, count + 1);
            ArrayResize(swingPrices, count + 1);
            swingBars[count] = i;
            swingPrices[count] = lowCenter;
            count++;
         }
      }
      
      return count;
   }
   
   //+------------------------------------------------------------------+
   //| スイングハイ（極大点）検出                                        |
   //+------------------------------------------------------------------+
   int FindSwingHighs(int &swingBars[], double &swingPrices[], int lookback)
   {
      ArrayResize(swingBars, 0);
      ArrayResize(swingPrices, 0);
      int count = 0;
      
      for(int i = 2; i < lookback - 2; i++)
      {
         double highCenter = iHigh(m_symbol, m_timeframe, i);
         double highLeft1 = iHigh(m_symbol, m_timeframe, i - 1);
         double highLeft2 = iHigh(m_symbol, m_timeframe, i - 2);
         double highRight1 = iHigh(m_symbol, m_timeframe, i + 1);
         double highRight2 = iHigh(m_symbol, m_timeframe, i + 2);
         
         if(highCenter > highLeft1 && highCenter > highLeft2 &&
            highCenter > highRight1 && highCenter > highRight2)
         {
            ArrayResize(swingBars, count + 1);
            ArrayResize(swingPrices, count + 1);
            swingBars[count] = i;
            swingPrices[count] = highCenter;
            count++;
         }
      }
      
      return count;
   }
   
   //+------------------------------------------------------------------+
   //| 線形回帰でラインをフィット                                        |
   //+------------------------------------------------------------------+
   void FitLine(const int &bars[], const double &prices[], int count, 
                double &slope, double &intercept)
   {
      if(count < 2)
      {
         slope = 0;
         intercept = prices[0];
         return;
      }
      
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      
      for(int i = 0; i < count; i++)
      {
         double x = bars[i];
         double y = prices[i];
         sumX += x;
         sumY += y;
         sumXY += x * y;
         sumX2 += x * x;
      }
      
      double n = count;
      double denom = n * sumX2 - sumX * sumX;
      
      if(MathAbs(denom) < 1e-10)
      {
         slope = 0;
         intercept = sumY / n;
         return;
      }
      
      slope = (n * sumXY - sumX * sumY) / denom;
      intercept = (sumY - slope * sumX) / n;
   }
   
   //+------------------------------------------------------------------+
   //| 平行度チェック                                                    |
   //+------------------------------------------------------------------+
   bool CheckParallel(double slope1, double slope2)
   {
      if(!m_cfg.ChannelRequireParallel)
         return true;
         
      double tolerance = m_cfg.ChannelParallelTolerance * _Point;
      return MathAbs(slope1 - slope2) <= tolerance;
   }
   
   //+------------------------------------------------------------------+
   //| 指定バーでの価格を取得                                            |
   //+------------------------------------------------------------------+
   double GetUpperPriceAtBar(int shift) const
   {
      if(!m_channel.isValid)
         return 0.0;
      return m_channel.upperIntercept + m_channel.upperSlope * shift;
   }
   
   double GetLowerPriceAtBar(int shift) const
   {
      if(!m_channel.isValid)
         return 0.0;
      return m_channel.lowerIntercept + m_channel.lowerSlope * shift;
   }

public:
   //+------------------------------------------------------------------+
   //| コンストラクタ                                                    |
   //+------------------------------------------------------------------+
   CChannelDetector()
   : m_symbol(""),
     m_timeframe(PERIOD_CURRENT),
     m_cfg(NULL),
     m_lastUpdateTime(0)
   {
      m_channel.Reset();
   }
   
   //+------------------------------------------------------------------+
   //| 初期化                                                            |
   //+------------------------------------------------------------------+
   void Init(const string symbol, ENUM_TIMEFRAMES timeframe, CPullbackConfig* cfg)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_cfg = cfg;
   }
   
   //+------------------------------------------------------------------+
   //| チャネル検出                                                      |
   //+------------------------------------------------------------------+
   bool DetectChannel()
   {
      if(m_cfg == NULL)
         return false;
         
      int swingLowBars[], swingHighBars[];
      double swingLowPrices[], swingHighPrices[];
      
      int lowCount = FindSwingLows(swingLowBars, swingLowPrices, m_cfg.TrendLineLookbackBars);
      int highCount = FindSwingHighs(swingHighBars, swingHighPrices, m_cfg.TrendLineLookbackBars);
      
      // 最低2点ずつ必要
      if(lowCount < 2 || highCount < 2)
         return false;
      
      // 下限ライン（サポート）: スイングローをフィット
      double lowerSlope, lowerIntercept;
      FitLine(swingLowBars, swingLowPrices, lowCount, lowerSlope, lowerIntercept);
      
      // 上限ライン（レジスタンス）: スイングハイをフィット
      double upperSlope, upperIntercept;
      FitLine(swingHighBars, swingHighPrices, highCount, upperSlope, upperIntercept);
      
      // 平行度チェック
      if(!CheckParallel(lowerSlope, upperSlope))
         return false;
      
      // ATRを取得して幅計算に使用
      double atr = GetATR(m_cfg.ATRPeriod, 1);
      
      // チャネル幅計算（中間バーでの幅）
      int midBar = m_cfg.TrendLineLookbackBars / 2;
      double upperPrice = upperIntercept + upperSlope * midBar;
      double lowerPrice = lowerIntercept + lowerSlope * midBar;
      double width = upperPrice - lowerPrice;  // 価格差
      
      // ATR倍率で幅の範囲チェック
      double minWidth = atr * m_cfg.ChannelMinWidthATR;
      double maxWidth = atr * m_cfg.ChannelMaxWidthATR;
      if(width < minWidth || width > maxWidth)
         return false;
      
      // チャネル方向判定
      int direction = 0;
      double avgSlope = (lowerSlope + upperSlope) / 2;
      double slopeThreshold = _Point * 0.1;  // 0.1 point/bar以上で傾斜あり
      
      if(avgSlope > slopeThreshold)
         direction = 1;   // 上昇チャネル
      else if(avgSlope < -slopeThreshold)
         direction = -1;  // 下降チャネル
      else
         direction = 0;   // 水平チャネル
      
      // チャネル情報を保存
      m_channel.upperSlope = upperSlope;
      m_channel.upperIntercept = upperIntercept;
      m_channel.lowerSlope = lowerSlope;
      m_channel.lowerIntercept = lowerIntercept;
      m_channel.width = width;
      m_channel.direction = direction;
      m_channel.lastUpdate = TimeCurrent();
      m_channel.isValid = true;
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| チャネル更新                                                      |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(m_cfg == NULL)
         return;
         
      if(!m_cfg.TrendLineAutoUpdate)
         return;
         
      DetectChannel();
      m_lastUpdateTime = TimeCurrent();
   }
   
   //+------------------------------------------------------------------+
   //| チャネル上限タッチ検出（ショート）                                 |
   //+------------------------------------------------------------------+
   bool DetectUpperBoundaryTouch(int lookback = 5)
   {
      if(!m_channel.isValid)
         return false;
         
      double tolerance = GetATR() * m_cfg.TrendLineToleranceATR;
      
      for(int i = 1; i <= lookback; i++)
      {
         double upperPrice = GetUpperPriceAtBar(i);
         double high = iHigh(m_symbol, m_timeframe, i);
         
         if(high >= upperPrice - tolerance && high <= upperPrice + tolerance)
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| チャネル下限タッチ検出（ロング）                                   |
   //+------------------------------------------------------------------+
   bool DetectLowerBoundaryTouch(int lookback = 5)
   {
      if(!m_channel.isValid)
         return false;
         
      double tolerance = GetATR() * m_cfg.TrendLineToleranceATR;
      
      for(int i = 1; i <= lookback; i++)
      {
         double lowerPrice = GetLowerPriceAtBar(i);
         double low = iLow(m_symbol, m_timeframe, i);
         
         if(low >= lowerPrice - tolerance && low <= lowerPrice + tolerance)
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| チャネル上限クロス検出（ショート）                                 |
   //+------------------------------------------------------------------+
   bool DetectUpperBoundaryCross(int lookback = 5)
   {
      if(!m_channel.isValid)
         return false;
      
      for(int i = 1; i <= lookback; i++)
      {
         double upperPrice_i = GetUpperPriceAtBar(i);
         double upperPrice_prev = GetUpperPriceAtBar(i + 1);
         
         double high_prev = iHigh(m_symbol, m_timeframe, i + 1);
         double close_i = iClose(m_symbol, m_timeframe, i);
         
         // 上限突破後に戻る
         if(high_prev > upperPrice_prev && close_i < upperPrice_i)
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| チャネル下限クロス検出（ロング）                                   |
   //+------------------------------------------------------------------+
   bool DetectLowerBoundaryCross(int lookback = 5)
   {
      if(!m_channel.isValid)
         return false;
      
      for(int i = 1; i <= lookback; i++)
      {
         double lowerPrice_i = GetLowerPriceAtBar(i);
         double lowerPrice_prev = GetLowerPriceAtBar(i + 1);
         
         double low_prev = iLow(m_symbol, m_timeframe, i + 1);
         double close_i = iClose(m_symbol, m_timeframe, i);
         
         // 下限突破後に戻る
         if(low_prev < lowerPrice_prev && close_i > lowerPrice_i)
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| チャネル上限ブレイク検出（終値基準）                               |
   //+------------------------------------------------------------------+
   bool DetectUpperBoundaryBreak(int lookback = 5)
   {
      if(!m_channel.isValid)
         return false;
      
      for(int i = 1; i <= lookback; i++)
      {
         double upperPrice_i = GetUpperPriceAtBar(i);
         double upperPrice_prev = GetUpperPriceAtBar(i + 1);
         
         double close_prev = iClose(m_symbol, m_timeframe, i + 1);
         double close_i = iClose(m_symbol, m_timeframe, i);
         
         // 終値が上限を一時的に突破して戻る
         if(close_prev > upperPrice_prev && close_i < upperPrice_i)
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| チャネル下限ブレイク検出（終値基準）                               |
   //+------------------------------------------------------------------+
   bool DetectLowerBoundaryBreak(int lookback = 5)
   {
      if(!m_channel.isValid)
         return false;
      
      for(int i = 1; i <= lookback; i++)
      {
         double lowerPrice_i = GetLowerPriceAtBar(i);
         double lowerPrice_prev = GetLowerPriceAtBar(i + 1);
         
         double close_prev = iClose(m_symbol, m_timeframe, i + 1);
         double close_i = iClose(m_symbol, m_timeframe, i);
         
         // 終値が下限を一時的に突破して戻る
         if(close_prev < lowerPrice_prev && close_i > lowerPrice_i)
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| チャネル逆張りシグナル検出                                        |
   //+------------------------------------------------------------------+
   int DetectChannelReversalSignal(int &signalType)
   {
      signalType = 0;
      
      if(!m_channel.isValid)
         return 0;
      
      // 逆張りモード限定の場合、チャネル方向をチェック
      if(m_cfg.ChannelReversalOnly && m_channel.direction != 0)
      {
         // 上昇チャネルでのショートのみ許可
         // 下降チャネルでのロングのみ許可
      }
      
      // ショートシグナル: 上限でのリバーサル
      if(m_cfg.UseTouchPullback && DetectUpperBoundaryTouch())
      {
         signalType = 1;
         return -1;  // ショート
      }
      if(m_cfg.UseCrossPullback && DetectUpperBoundaryCross())
      {
         signalType = 2;
         return -1;
      }
      if(m_cfg.UseBreakPullback && DetectUpperBoundaryBreak())
      {
         signalType = 3;
         return -1;
      }
      
      // ロングシグナル: 下限でのリバーサル
      if(m_cfg.UseTouchPullback && DetectLowerBoundaryTouch())
      {
         signalType = 1;
         return 1;   // ロング
      }
      if(m_cfg.UseCrossPullback && DetectLowerBoundaryCross())
      {
         signalType = 2;
         return 1;
      }
      if(m_cfg.UseBreakPullback && DetectLowerBoundaryBreak())
      {
         signalType = 3;
         return 1;
      }
      
      return 0;  // シグナルなし
   }
   
   //+------------------------------------------------------------------+
   //| 価格位置の判定                                                    |
   //+------------------------------------------------------------------+
   int GetPricePosition()
   {
      if(!m_channel.isValid)
         return 0;
         
      double close = iClose(m_symbol, m_timeframe, 1);
      double upper = GetUpperPriceAtBar(1);
      double lower = GetLowerPriceAtBar(1);
      double mid = (upper + lower) / 2;
      
      if(close >= mid)
         return 1;   // チャネル上部
      else
         return -1;  // チャネル下部
   }
   
   //+------------------------------------------------------------------+
   //| ゲッター                                                          |
   //+------------------------------------------------------------------+
   SChannel GetChannel() const { return m_channel; }
   bool HasValidChannel() const { return m_channel.isValid; }
   int GetChannelDirection() const { return m_channel.direction; }
   double GetChannelWidth() const { return m_channel.width; }
};

#endif // __CHANNEL_DETECTOR_MQH__
