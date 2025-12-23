//+------------------------------------------------------------------+
//|                                         MeanReversion.mqh        |
//|                      Mean Reversion Timing Module                |
//|        Detects counter-trade opportunities after AI overreaction |
//+------------------------------------------------------------------+
#property copyright "AI Defense System"
#property strict

#include "AIDefenseCore.mqh"

//+------------------------------------------------------------------+
//| Mean Reversion Detector Class                                    |
//+------------------------------------------------------------------+
class CMeanReversionDetector : public CAIDefenseModule
{
private:
   int      m_bb_period;            // ボリンジャーバンド期間
   double   m_bb_deviation;         // 標準偏差倍率
   int      m_rsi_period;           // RSI期間
   double   m_rsi_overbought;       // 買われ過ぎ閾値
   double   m_rsi_oversold;         // 売られ過ぎ閾値
   
public:
   CMeanReversionDetector(int bb_period = 20,
                         double bb_dev = 2.5,
                         int rsi_period = 14,
                         double rsi_ob = 75.0,
                         double rsi_os = 25.0,
                         double sensitivity = 1.0)
      : CAIDefenseModule("MeanReversion", sensitivity)
   {
      m_bb_period = bb_period;
      m_bb_deviation = bb_dev + (sensitivity - 1.0) * 0.5;  // 感度でバンド幅調整
      m_rsi_period = rsi_period;
      m_rsi_overbought = rsi_ob - (sensitivity - 1.0) * 5.0;
      m_rsi_oversold = rsi_os + (sensitivity - 1.0) * 5.0;
   }
   
   virtual AIDefenseSignal Analyze(const double &high[], const double &low[],
                                   const double &close[], const long &volume[])
   {
      AIDefenseSignal signal = CreateNeutralSignal();
      
      if(ArraySize(close) < m_bb_period + 10) return signal;
      
      // ボリンジャーバンド計算
      double bb_mid = CalculateSMA(close, m_bb_period, 0);
      double bb_std = CalculateStdDev(close, m_bb_period, bb_mid, 0);
      double bb_upper = bb_mid + (bb_std * m_bb_deviation);
      double bb_lower = bb_mid - (bb_std * m_bb_deviation);
      
      // RSI計算
      double rsi = CalculateRSI(close, m_rsi_period, 0);
      
      // 現在価格
      double current_price = close[0];
      double prev_price = close[1];
      
      // 出来高減少確認（AI活動終了の兆候）
      bool volume_declining = IsVolumeDeclining(volume);
      
      // バンド上限突破 + RSI買われ過ぎ + 出来高減少 = 売り逆張りチャンス
      if(current_price > bb_upper && rsi > m_rsi_overbought && volume_declining)
      {
         // 価格が戻り始めているか確認
         if(prev_price > current_price)  // 下落開始
         {
            signal.TrapCleared = true;  // AI過剰反応終了
            signal.ConfidenceAdjustment = +0.6;
            signal.Reason = StringFormat("Mean reversion SELL opportunity: Price %.5f > BB %.5f, RSI %.1f",
                                       current_price, bb_upper, rsi);
            
            // ターゲットは中心線
            double target_pips = (current_price - bb_mid) / _Point;
            signal.Reason += StringFormat(", Target: %.1f pips to mid-line", target_pips);
         }
      }
      // バンド下限突破 + RSI売られ過ぎ + 出来高減少 = 買い逆張りチャンス
      else if(current_price < bb_lower && rsi < m_rsi_oversold && volume_declining)
      {
         // 価格が戻り始めているか確認
         if(prev_price < current_price)  // 上昇開始
         {
            signal.TrapCleared = true;  // AI過剰反応終了
            signal.ConfidenceAdjustment = +0.6;
            signal.Reason = StringFormat("Mean reversion BUY opportunity: Price %.5f < BB %.5f, RSI %.1f",
                                       current_price, bb_lower, rsi);
            
            // ターゲットは中心線
            double target_pips = (bb_mid - current_price) / _Point;
            signal.Reason += StringFormat(", Target: %.1f pips to mid-line", target_pips);
         }
      }
      
      // 極端な値での警告（平均回帰の可能性は高いが、エントリーには慎重）
      if(current_price > bb_upper + bb_std * 0.5)
      {
         signal.ConfidenceAdjustment = -0.3;  // 買いエントリーは避ける
         signal.Reason = "Extreme overbought - Avoid BUY entries";
      }
      else if(current_price < bb_lower - bb_std * 0.5)
      {
         signal.ConfidenceAdjustment = -0.3;  // 売りエントリーは避ける
         signal.Reason = "Extreme oversold - Avoid SELL entries";
      }
      
      return signal;
   }
   
private:
   double CalculateStdDev(const double &price[], int period, double mean, int shift)
   {
      if(shift + period >= ArraySize(price)) return 0.0;
      
      double variance = 0.0;
      for(int i = shift; i < shift + period; i++)
         variance += MathPow(price[i] - mean, 2);
      
      return MathSqrt(variance / period);
   }
   
   bool IsVolumeDeclining(const long &volume[])
   {
      if(ArraySize(volume) < 5) return false;
      
      // 直近3本の出来高が減少傾向か
      double recent_avg = ((double)volume[0] + (double)volume[1] + (double)volume[2]) / 3.0;
      double prev_avg = ((double)volume[3] + (double)volume[4] + (double)volume[5]) / 3.0;
      
      return (recent_avg < prev_avg * 0.8);  // 20%以上減少
   }
};

//+------------------------------------------------------------------+
