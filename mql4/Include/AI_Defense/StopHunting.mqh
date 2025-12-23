//+------------------------------------------------------------------+
//|                                           StopHunting.mqh        |
//|                          Stop Hunting Detection Module           |
//|           Detects AI-driven stop loss hunting patterns          |
//+------------------------------------------------------------------+
#property copyright "AI Defense System"
#property strict

#include "AIDefenseCore.mqh"

//+------------------------------------------------------------------+
//| Stop Hunting Detector Class                                      |
//+------------------------------------------------------------------+
class CStopHuntingDetector : public CAIDefenseModule
{
private:
   int      m_lookback_bars;        // 重要水準検出用のルックバック
   double   m_breach_tolerance;    // 突破許容範囲（pips）
   bool     m_hunt_detected;        // ストップ狩り検出中
   int      m_hunt_start_bar;       // 狩り開始バー
   double   m_hunted_level;         // 狩られた水準
   bool     m_hunt_direction_up;    // 上向き突破か下向き突破か
   
public:
   CStopHuntingDetector(int lookback = 50,
                       double breach_tolerance_pips = 10.0,
                       double sensitivity = 1.0)
      : CAIDefenseModule("StopHunting", sensitivity)
   {
      m_lookback_bars = lookback;
      m_breach_tolerance = breach_tolerance_pips * _Point;
      m_hunt_detected = false;
      m_hunt_start_bar = -1;
      m_hunted_level = 0.0;
      m_hunt_direction_up = false;
   }
   
   virtual AIDefenseSignal Analyze(const double &high[], const double &low[],
                                   const double &close[], const long &volume[])
   {
      AIDefenseSignal signal = CreateNeutralSignal();
      
      if(ArraySize(close) < m_lookback_bars) return signal;
      
      // ストップ狩り検出フェーズ
      if(!m_hunt_detected)
      {
         DetectStopHunt(signal, high, low, close, volume);
      }
      // 狩り完了と反転確認フェーズ
      else
      {
         CheckHuntCompletion(signal, high, low, close);
      }
      
      return signal;
   }
   
private:
   void DetectStopHunt(AIDefenseSignal &signal, const double &high[], const double &low[],
                      const double &close[], const long &volume[])
   {
      // 重要水準を特定
      double swing_high = FindRecentSwingHigh(high, m_lookback_bars);
      double swing_low = FindRecentSwingLow(low, m_lookback_bars);
      
      // ラウンドナンバー近くの水準を特定
      double round_levels[20];
      ArrayInitialize(round_levels, 0);
      int round_count = FindNearbyRoundLevels(round_levels, close[0], 5);
      
      // 現在の価格アクション
      double current_high = high[0];
      double current_low = low[0];
      double current_close = close[0];
      double prev_close = close[1];
      
      // ATRで異常な動きを判定
      double atr = CalculateATR(high, low, close, 14, 0);
      
      // 上向きストップ狩り検出（レジスタンス突破失敗）
      if(current_high > swing_high && current_close < swing_high)
      {
         // ウィックで突破したが終値で戻した = ストップ狩りの可能性
         double breach_size = current_high - swing_high;
         
         if(breach_size > m_breach_tolerance && breach_size < atr * 1.5)
         {
            // 出来高スパイク確認
            if(HasVolumeSpike(volume, 3.0))
            {
               m_hunt_detected = true;
               m_hunt_start_bar = 0;
               m_hunted_level = swing_high;
               m_hunt_direction_up = true;
               
               signal.TrapDetected = true;
               signal.TrapType = "Stop_Hunt_Up";
               signal.ConfidenceAdjustment = -0.6;
               signal.WaitBars = 3;
               signal.Reason = StringFormat("Upward stop hunt at %.5f (breach=%.1f pips)",
                                          swing_high, breach_size / _Point);
            }
         }
      }
      // 下向きストップ狩り検出（サポート突破失敗）
      else if(current_low < swing_low && current_close > swing_low)
      {
         // ウィックで突破したが終値で戻した = ストップ狩りの可能性
         double breach_size = swing_low - current_low;
         
         if(breach_size > m_breach_tolerance && breach_size < atr * 1.5)
         {
            // 出来高スパイク確認
            if(HasVolumeSpike(volume, 3.0))
            {
               m_hunt_detected = true;
               m_hunt_start_bar = 0;
               m_hunted_level = swing_low;
               m_hunt_direction_up = false;
               
               signal.TrapDetected = true;
               signal.TrapType = "Stop_Hunt_Down";
               signal.ConfidenceAdjustment = -0.6;
               signal.WaitBars = 3;
               signal.Reason = StringFormat("Downward stop hunt at %.5f (breach=%.1f pips)",
                                          swing_low, breach_size / _Point);
            }
         }
      }
      
      // ラウンドナンバーでのストップ狩りチェック
      CheckRoundNumberHunt(signal, round_levels, round_count, current_high, current_low, 
                          current_close, volume, atr);
   }
   
   void CheckHuntCompletion(AIDefenseSignal &signal, const double &high[], 
                           const double &low[], const double &close[])
   {
      int bars_since_hunt = 0 - m_hunt_start_bar;
      
      // 10バー以内に反転確認
      if(bars_since_hunt <= 10)
      {
         // 反転確認
         bool reversal_confirmed = false;
         
         if(m_hunt_direction_up)
         {
            // 上向き狩り後の下落反転
            if(close[0] < m_hunted_level && close[1] < m_hunted_level && close[2] < m_hunted_level)
            {
               reversal_confirmed = true;
               signal.TrapCleared = true;
               signal.ConfidenceAdjustment = +0.7;  // 売りエントリー推奨
               signal.Reason = StringFormat("Stop hunt completed at %.5f - SELL opportunity", m_hunted_level);
            }
         }
         else
         {
            // 下向き狩り後の上昇反転
            if(close[0] > m_hunted_level && close[1] > m_hunted_level && close[2] > m_hunted_level)
            {
               reversal_confirmed = true;
               signal.TrapCleared = true;
               signal.ConfidenceAdjustment = +0.7;  // 買いエントリー推奨
               signal.Reason = StringFormat("Stop hunt completed at %.5f - BUY opportunity", m_hunted_level);
            }
         }
         
         if(reversal_confirmed)
         {
            // リセット
            m_hunt_detected = false;
            m_hunt_start_bar = -1;
            m_hunted_level = 0.0;
         }
      }
      else
      {
         // タイムアウト - リセット
         m_hunt_detected = false;
         m_hunt_start_bar = -1;
      }
   }
   
   double FindRecentSwingHigh(const double &high[], int bars)
   {
      double swing_high = 0.0;
      for(int i = 5; i < bars; i++)
      {
         if(high[i] > high[i-1] && high[i] > high[i+1] &&
            high[i] > high[i-2] && high[i] > high[i+2])
         {
            if(high[i] > swing_high)
               swing_high = high[i];
         }
      }
      return swing_high;
   }
   
   double FindRecentSwingLow(const double &low[], int bars)
   {
      double swing_low = 999999.0;
      for(int i = 5; i < bars; i++)
      {
         if(low[i] < low[i-1] && low[i] < low[i+1] &&
            low[i] < low[i-2] && low[i] < low[i+2])
         {
            if(low[i] < swing_low)
               swing_low = low[i];
         }
      }
      return (swing_low < 999999.0) ? swing_low : 0.0;
   }
   
   int FindNearbyRoundLevels(double &levels[], double price, int max_count)
   {
      // 100pips単位のラウンドナンバー
      int pip_level = (int)MathFloor(price / (_Point * 100));
      int count = 0;
      
      for(int i = -2; i <= 2 && count < max_count; i++)
      {
         double level = (pip_level + i) * _Point * 100;
         if(count < max_count) levels[count++] = level;
      }
      
      return count;
   }
   
   void CheckRoundNumberHunt(AIDefenseSignal &signal, const double &round_levels[], 
                            int count, double current_high, double current_low, 
                            double current_close, const long &volume[], double atr)
   {
      for(int i = 0; i < count && i < ArraySize(round_levels); i++)
      {
         double level = round_levels[i];
         
         // 上向き狩り
         if(current_high > level && current_close < level)
         {
            double breach = current_high - level;
            if(breach < atr && HasVolumeSpike(volume, 2.5))
            {
               signal.TrapDetected = true;
               signal.TrapType = "Round_Number_Hunt_Up";
               signal.ConfidenceAdjustment = -0.5;
               signal.Reason = StringFormat("Round number hunt at %.5f", level);
               break;
            }
         }
         // 下向き狩り
         else if(current_low < level && current_close > level)
         {
            double breach = level - current_low;
            if(breach < atr && HasVolumeSpike(volume, 2.5))
            {
               signal.TrapDetected = true;
               signal.TrapType = "Round_Number_Hunt_Down";
               signal.ConfidenceAdjustment = -0.5;
               signal.Reason = StringFormat("Round number hunt at %.5f", level);
               break;
            }
         }
      }
   }
   
   bool HasVolumeSpike(const long &volume[], double multiplier)
   {
      if(ArraySize(volume) < 20) return false;
      
      double avg_volume = 0.0;
      for(int i = 5; i < 20; i++)
         avg_volume += (double)volume[i];
      avg_volume /= 15;
      
      return ((double)volume[0] > avg_volume * multiplier);
   }
};

//+------------------------------------------------------------------+
