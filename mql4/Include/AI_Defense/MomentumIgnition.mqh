//+------------------------------------------------------------------+
//|                                        MomentumIgnition.mqh      |
//|                        Momentum Ignition Detection Module        |
//|                 Detects AI-induced rapid price manipulation      |
//+------------------------------------------------------------------+
#property copyright "AI Defense System"
#property strict

#include "AIDefenseCore.mqh"

//+------------------------------------------------------------------+
//| Momentum Ignition Detector Class                                 |
//+------------------------------------------------------------------+
class CMomentumIgnitionDetector : public CAIDefenseModule
{
private:
   int      m_time_window;          // 検出時間窓（バー数）
   double   m_atr_multiplier;       // ATR倍率閾値
   double   m_volume_multiplier;    // 出来高倍率閾値
   bool     m_last_ignition;        // 前回イグニッション検出状態
   int      m_ignition_start_bar;   // イグニッション開始バー
   
public:
   CMomentumIgnitionDetector(int time_window = 10,
                            double atr_mult = 2.0,
                            double vol_mult = 3.0,
                            double sensitivity = 1.0)
      : CAIDefenseModule("MomentumIgnition", sensitivity)
   {
      m_time_window = time_window;
      m_atr_multiplier = atr_mult * sensitivity;
      m_volume_multiplier = vol_mult * sensitivity;
      m_last_ignition = false;
      m_ignition_start_bar = -1;
   }
   
   virtual AIDefenseSignal Analyze(const double &high[], const double &low[],
                                   const double &close[], const long &volume[])
   {
      AIDefenseSignal signal = CreateNeutralSignal();
      
      if(ArraySize(close) < 50) return signal;
      
      // ATR計算
      double atr = CalculateATR(high, low, close, 14, 0);
      if(atr <= 0) return signal;
      
      // 時間窓内の価格変動率
      double price_change = MathAbs(close[0] - close[m_time_window]);
      double price_change_rate = price_change / close[m_time_window];
      
      // ATRとの比較
      double atr_threshold = atr * m_atr_multiplier;
      
      // 出来高分析
      double avg_volume = CalculateAverageVolume(volume, 50, m_time_window);
      double recent_volume = CalculateAverageVolume(volume, m_time_window, 0);
      
      bool abnormal_price_move = (price_change > atr_threshold);
      bool abnormal_volume = (recent_volume > avg_volume * m_volume_multiplier);
      
      // モメンタム・イグニッション検出
      if(abnormal_price_move && abnormal_volume)
      {
         // ニュース時間帯チェック（簡易版: 時間帯ベース。外部ファンダ連携はしない）
         bool likely_news_time = IsLikelyNewsTime();
         
         if(!likely_news_time)
         {
            // AI誘発の可能性が高い
            signal.TrapDetected = true;
            signal.TrapType = "Momentum_Ignition";
            signal.ConfidenceAdjustment = -0.7;  // エントリー信頼度を大幅減少
            signal.WaitBars = 5;  // 5バー待機
            
            string direction = (close[0] > close[m_time_window]) ? "PUMP" : "DUMP";
            signal.Reason = StringFormat("AI %s detected: Price=%+.1f pips (%.1f ATR), Vol=%.1fx",
                                       direction,
                                       price_change / _Point,
                                       price_change / atr,
                                       recent_volume / avg_volume);
            
            m_last_ignition = true;
            m_ignition_start_bar = 0;
         }
      }
      // 平均回帰の兆候検出
      else if(m_last_ignition && m_ignition_start_bar >= 0)
      {
         int bars_since_ignition = 0 - m_ignition_start_bar;
         
         if(bars_since_ignition <= 20)
         {
            // 価格が元の水準に戻り始めているか
            bool reversion_detected = DetectMeanReversion(close, m_ignition_start_bar);
            
            if(reversion_detected)
            {
               // 罠解除 - 逆張りチャンス
               signal.TrapCleared = true;
               signal.ConfidenceAdjustment = +0.5;  // 逆張りエントリー推奨
               signal.Reason = "Mean reversion after AI ignition - Counter opportunity";
               
               m_last_ignition = false;
               m_ignition_start_bar = -1;
            }
         }
         else
         {
            // 時間経過でリセット
            m_last_ignition = false;
            m_ignition_start_bar = -1;
         }
      }
      
      return signal;
   }
   
private:
   double CalculateAverageVolume(const long &volume[], int period, int shift)
   {
      if(shift + period >= ArraySize(volume)) return 0.0;
      
      double sum = 0.0;
      for(int i = shift; i < shift + period; i++)
         sum += (double)volume[i];
      
      return sum / period;
   }
   
   bool IsLikelyNewsTime()
   {
      // 主要な経済指標発表時間帯の簡易判定
      // 本格的にはニュースカレンダーAPIと連携すべき
      
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      // UTCベースでの主要時間帯
      // 8:30-9:30 (欧州オープン)
      // 13:30-14:30 (米国雇用統計など)
      // 21:30-22:30 (FOMC声明など)
      
      if((dt.hour == 8 || dt.hour == 9) ||
         (dt.hour == 13 || dt.hour == 14) ||
         (dt.hour == 21 || dt.hour == 22))
      {
         return true;
      }
      
      return false;
   }
   
   bool DetectMeanReversion(const double &close[], int ignition_bar)
   {
      // イグニッション前の価格水準
      int pre_ignition_bar = ignition_bar + m_time_window;
      if(pre_ignition_bar >= ArraySize(close)) return false;
      
      double pre_ignition_price = close[pre_ignition_bar];
      double peak_price = close[ignition_bar];
      double current_price = close[0];
      
      // 価格移動の方向
      bool was_pump = (peak_price > pre_ignition_price);
      
      if(was_pump)
      {
         // PUMPからの回帰: 価格が下落し始めている
         double retracement = (peak_price - current_price) / (peak_price - pre_ignition_price);
         return (retracement > 0.5);  // 50%以上戻している
      }
      else
      {
         // DUMPからの回帰: 価格が上昇し始めている
         double retracement = (current_price - peak_price) / (pre_ignition_price - peak_price);
         return (retracement > 0.5);  // 50%以上戻している
      }
   }
};

//+------------------------------------------------------------------+
