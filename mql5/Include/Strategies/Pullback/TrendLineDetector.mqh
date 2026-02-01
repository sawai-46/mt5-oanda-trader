//+------------------------------------------------------------------+
//|                        TrendLineDetector.mqh                     |
//|                 設計書セクション12: トレンドライン統合機能          |
//+------------------------------------------------------------------+
#ifndef __TRENDLINE_DETECTOR_MQH__
#define __TRENDLINE_DETECTOR_MQH__

#include <Strategies/Pullback/PullbackConfig.mqh>

//+------------------------------------------------------------------+
//| トレンドライン情報構造体                                          |
//+------------------------------------------------------------------+
struct STrendLine
{
   double   slope;           // 傾き (価格/バー)
   double   intercept;       // 切片 (bar=0での価格)
   int      touchCount;      // タッチ回数
   datetime lastUpdate;      // 最終更新時刻
   bool     isValid;         // 有効フラグ
   
   void Reset()
   {
      slope = 0.0;
      intercept = 0.0;
      touchCount = 0;
      lastUpdate = 0;
      isValid = false;
   }
};

//+------------------------------------------------------------------+
//| トレンドライン検出クラス                                          |
//+------------------------------------------------------------------+
class CTrendLineDetector
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   CPullbackConfig*  m_cfg;
   
   STrendLine        m_upTrendLine;    // 上昇トレンドライン（サポート）
   STrendLine        m_downTrendLine;  // 下降トレンドライン（レジスタンス）
   
   datetime          m_lastUpdateTime;
   
   //+------------------------------------------------------------------+
   //| スイングロー（極小点）検出                                        |
   //+------------------------------------------------------------------+
   int FindSwingLows(int &swingBars[], int lookback)
   {
      ArrayResize(swingBars, 0);
      int count = 0;
      
      // 左右2本より低い安値を探す
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
            swingBars[count] = i;
            count++;
         }
      }
      
      return count;
   }
   
   //+------------------------------------------------------------------+
   //| スイングハイ（極大点）検出                                        |
   //+------------------------------------------------------------------+
   int FindSwingHighs(int &swingBars[], int lookback)
   {
      ArrayResize(swingBars, 0);
      int count = 0;
      
      // 左右2本より高い高値を探す
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
            swingBars[count] = i;
            count++;
         }
      }
      
      return count;
   }
   
   //+------------------------------------------------------------------+
   //| ラインタッチ回数カウント                                          |
   //+------------------------------------------------------------------+
   int CountLineTouches(double slope, double intercept, int lookback, bool isSupport)
   {
      int touches = 0;
      double tolerance = m_cfg.TrendLineTolerancePoints * _Point;
      
      for(int i = 1; i < lookback; i++)
      {
         double linePrice = intercept + slope * i;
         
         if(isSupport)
         {
            // サポートライン: 安値がラインにタッチ
            double low = iLow(m_symbol, m_timeframe, i);
            if(MathAbs(low - linePrice) <= tolerance)
               touches++;
         }
         else
         {
            // レジスタンスライン: 高値がラインにタッチ
            double high = iHigh(m_symbol, m_timeframe, i);
            if(MathAbs(high - linePrice) <= tolerance)
               touches++;
         }
      }
      
      return touches;
   }
   
   //+------------------------------------------------------------------+
   //| 現在のバーにおけるライン価格を取得                                 |
   //+------------------------------------------------------------------+
   double GetLinePriceAtBar(const STrendLine &line, int shift)
   {
      if(!line.isValid)
         return 0.0;
      return line.intercept + line.slope * shift;
   }

public:
   //+------------------------------------------------------------------+
   //| コンストラクタ                                                    |
   //+------------------------------------------------------------------+
   CTrendLineDetector()
   : m_symbol(""),
     m_timeframe(PERIOD_CURRENT),
     m_cfg(NULL),
     m_lastUpdateTime(0)
   {
      m_upTrendLine.Reset();
      m_downTrendLine.Reset();
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
   //| 上昇トレンドライン検出                                            |
   //+------------------------------------------------------------------+
   bool DetectUpTrendLine()
   {
      if(m_cfg == NULL)
         return false;
         
      int swingLows[];
      int swingCount = FindSwingLows(swingLows, m_cfg.TrendLineLookbackBars);
      
      if(swingCount < m_cfg.TrendLineMinTouches)
         return false;
      
      double bestSlope = 0;
      double bestIntercept = 0;
      int bestTouchCount = 0;
      double bestScore = 0;
      
      // すべての組み合わせを試す
      for(int i = 0; i < swingCount - 1; i++)
      {
         for(int j = i + 1; j < swingCount; j++)
         {
            int bar1 = swingLows[i];
            int bar2 = swingLows[j];
            
            // 時間的に十分離れているか
            if(bar2 - bar1 < 5) continue;
            
            // ラインの傾きと切片を計算
            double price1 = iLow(m_symbol, m_timeframe, bar1);
            double price2 = iLow(m_symbol, m_timeframe, bar2);
            
            double tempSlope = (price2 - price1) / (bar2 - bar1);
            double tempIntercept = price1 - tempSlope * bar1;
            
            // 上昇トレンドラインは正の傾き必須
            if(tempSlope <= 0) continue;
            
            // このラインが何回タッチされているかカウント
            int touches = CountLineTouches(tempSlope, tempIntercept, 
                                          m_cfg.TrendLineLookbackBars, true);
            
            // スコア計算: タッチ回数 + 傾きの適切さ
            double score = touches + (tempSlope / _Point) * 0.001;
            
            if(score > bestScore)
            {
               bestSlope = tempSlope;
               bestIntercept = tempIntercept;
               bestTouchCount = touches;
               bestScore = score;
            }
         }
      }
      
      if(bestTouchCount >= m_cfg.TrendLineMinTouches)
      {
         m_upTrendLine.slope = bestSlope;
         m_upTrendLine.intercept = bestIntercept;
         m_upTrendLine.touchCount = bestTouchCount;
         m_upTrendLine.lastUpdate = TimeCurrent();
         m_upTrendLine.isValid = true;
         return true;
      }
      
      m_upTrendLine.isValid = false;
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| 下降トレンドライン検出                                            |
   //+------------------------------------------------------------------+
   bool DetectDownTrendLine()
   {
      if(m_cfg == NULL)
         return false;
         
      int swingHighs[];
      int swingCount = FindSwingHighs(swingHighs, m_cfg.TrendLineLookbackBars);
      
      if(swingCount < m_cfg.TrendLineMinTouches)
         return false;
      
      double bestSlope = 0;
      double bestIntercept = 0;
      int bestTouchCount = 0;
      double bestScore = 0;
      
      for(int i = 0; i < swingCount - 1; i++)
      {
         for(int j = i + 1; j < swingCount; j++)
         {
            int bar1 = swingHighs[i];
            int bar2 = swingHighs[j];
            
            if(bar2 - bar1 < 5) continue;
            
            double price1 = iHigh(m_symbol, m_timeframe, bar1);
            double price2 = iHigh(m_symbol, m_timeframe, bar2);
            
            double tempSlope = (price2 - price1) / (bar2 - bar1);
            double tempIntercept = price1 - tempSlope * bar1;
            
            // 下降トレンドラインは負の傾き必須
            if(tempSlope >= 0) continue;
            
            int touches = CountLineTouches(tempSlope, tempIntercept, 
                                          m_cfg.TrendLineLookbackBars, false);
            
            double score = touches + (MathAbs(tempSlope) / _Point) * 0.001;
            
            if(score > bestScore)
            {
               bestSlope = tempSlope;
               bestIntercept = tempIntercept;
               bestTouchCount = touches;
               bestScore = score;
            }
         }
      }
      
      if(bestTouchCount >= m_cfg.TrendLineMinTouches)
      {
         m_downTrendLine.slope = bestSlope;
         m_downTrendLine.intercept = bestIntercept;
         m_downTrendLine.touchCount = bestTouchCount;
         m_downTrendLine.lastUpdate = TimeCurrent();
         m_downTrendLine.isValid = true;
         return true;
      }
      
      m_downTrendLine.isValid = false;
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| トレンドライン更新（新バー時に呼び出し）                           |
   //+------------------------------------------------------------------+
   void Update()
   {
      if(m_cfg == NULL)
         return;
         
      if(!m_cfg.TrendLineAutoUpdate)
         return;
         
      DetectUpTrendLine();
      DetectDownTrendLine();
      m_lastUpdateTime = TimeCurrent();
   }
   
   //+------------------------------------------------------------------+
   //| トレンドラインタッチプルバック検出                                 |
   //+------------------------------------------------------------------+
   bool DetectTrendLineTouchPullback(bool isLong, int lookback = 5)
   {
      // MQL5: 構造体参照をローカル変数に代入できないため直接アクセス
      if(isLong && !m_upTrendLine.isValid)
         return false;
      if(!isLong && !m_downTrendLine.isValid)
         return false;
         
      double tolerance = m_cfg.TrendLineTolerancePoints * _Point;
      
      for(int i = 1; i <= lookback; i++)
      {
         double linePrice = isLong ? GetLinePriceAtBar(m_upTrendLine, i) : GetLinePriceAtBar(m_downTrendLine, i);
         
         if(isLong)
         {
            // ロング: 安値がサポートラインにタッチ
            double low = iLow(m_symbol, m_timeframe, i);
            double high = iHigh(m_symbol, m_timeframe, i);
            
            if(low <= linePrice + tolerance && high >= linePrice - tolerance)
               return true;
         }
         else
         {
            // ショート: 高値がレジスタンスラインにタッチ
            double low = iLow(m_symbol, m_timeframe, i);
            double high = iHigh(m_symbol, m_timeframe, i);
            
            if(high >= linePrice - tolerance && low <= linePrice + tolerance)
               return true;
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| トレンドラインクロスプルバック検出                                 |
   //+------------------------------------------------------------------+
   bool DetectTrendLineCrossPullback(bool isLong, int lookback = 5)
   {
      // MQL5: 構造体参照をローカル変数に代入できないため直接アクセス
      if(isLong && !m_upTrendLine.isValid)
         return false;
      if(!isLong && !m_downTrendLine.isValid)
         return false;
         
      for(int i = 1; i <= lookback; i++)
      {
         double linePrice_i = isLong ? GetLinePriceAtBar(m_upTrendLine, i) : GetLinePriceAtBar(m_downTrendLine, i);
         double linePrice_prev = isLong ? GetLinePriceAtBar(m_upTrendLine, i + 1) : GetLinePriceAtBar(m_downTrendLine, i + 1);
         
         if(isLong)
         {
            // ロング: 価格がサポートラインを下→上クロス
            double low_prev = iLow(m_symbol, m_timeframe, i + 1);
            double high_i = iHigh(m_symbol, m_timeframe, i);
            
            if(low_prev < linePrice_prev && high_i > linePrice_i)
               return true;
         }
         else
         {
            // ショート: 価格がレジスタンスラインを上→下クロス
            double high_prev = iHigh(m_symbol, m_timeframe, i + 1);
            double low_i = iLow(m_symbol, m_timeframe, i);
            
            if(high_prev > linePrice_prev && low_i < linePrice_i)
               return true;
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| トレンドラインブレイクプルバック検出（終値基準）                    |
   //+------------------------------------------------------------------+
   bool DetectTrendLineBreakPullback(bool isLong, int lookback = 5)
   {
      // MQL5: 構造体参照をローカル変数に代入できないため直接アクセス
      if(isLong && !m_upTrendLine.isValid)
         return false;
      if(!isLong && !m_downTrendLine.isValid)
         return false;
         
      for(int i = 1; i <= lookback; i++)
      {
         double linePrice_i = isLong ? GetLinePriceAtBar(m_upTrendLine, i) : GetLinePriceAtBar(m_downTrendLine, i);
         double linePrice_prev = isLong ? GetLinePriceAtBar(m_upTrendLine, i + 1) : GetLinePriceAtBar(m_downTrendLine, i + 1);
         
         double close_i = iClose(m_symbol, m_timeframe, i);
         double close_prev = iClose(m_symbol, m_timeframe, i + 1);
         
         if(isLong)
         {
            // ロング: 終値がラインを下抜け → 上に戻る
            if(close_prev < linePrice_prev && close_i > linePrice_i)
               return true;
         }
         else
         {
            // ショート: 終値がラインを上抜け → 下に戻る
            if(close_prev > linePrice_prev && close_i < linePrice_i)
               return true;
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| 統合プルバック検出                                                |
   //+------------------------------------------------------------------+
   bool DetectTrendlinePullback(bool isLong, int &signalType)
   {
      signalType = 0;
      
      // タイプA: タッチ
      if(m_cfg.UseTouchPullback && DetectTrendLineTouchPullback(isLong))
      {
         signalType = 1;
         return true;
      }
      
      // タイプB: クロス
      if(m_cfg.UseCrossPullback && DetectTrendLineCrossPullback(isLong))
      {
         signalType = 2;
         return true;
      }
      
      // タイプC: ブレイク
      if(m_cfg.UseBreakPullback && DetectTrendLineBreakPullback(isLong))
      {
         signalType = 3;
         return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| トレンド判定（トレンドラインモード）                               |
   //+------------------------------------------------------------------+
   int CheckTrendWithTrendLine()
   {
      // 上昇トレンドライン有効 → ロング
      if(m_upTrendLine.isValid && m_upTrendLine.touchCount >= m_cfg.TrendLineMinTouches)
      {
         // 現在価格がラインの上にあること
         double linePrice = GetLinePriceAtBar(m_upTrendLine, 1);
         double close1 = iClose(m_symbol, m_timeframe, 1);
         
         if(close1 > linePrice)
            return 1;  // 上昇トレンド
      }
      
      // 下降トレンドライン有効 → ショート
      if(m_downTrendLine.isValid && m_downTrendLine.touchCount >= m_cfg.TrendLineMinTouches)
      {
         double linePrice = GetLinePriceAtBar(m_downTrendLine, 1);
         double close1 = iClose(m_symbol, m_timeframe, 1);
         
         if(close1 < linePrice)
            return -1; // 下降トレンド
      }
      
      return 0; // トレンドなし
   }
   
   //+------------------------------------------------------------------+
   //| ゲッター                                                          |
   //+------------------------------------------------------------------+
   STrendLine GetUpTrendLine() const { return m_upTrendLine; }
   STrendLine GetDownTrendLine() const { return m_downTrendLine; }
   bool HasValidUpTrendLine() const { return m_upTrendLine.isValid; }
   bool HasValidDownTrendLine() const { return m_downTrendLine.isValid; }
};

#endif // __TRENDLINE_DETECTOR_MQH__
