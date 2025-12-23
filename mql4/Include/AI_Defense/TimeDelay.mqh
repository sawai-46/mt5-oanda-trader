//+------------------------------------------------------------------+
//|                                            TimeDelay.mqh         |
//|                          Time Delay Filter Module                |
//|              Avoids AI initial reaction by waiting               |
//+------------------------------------------------------------------+
#property copyright "AI Defense System"
#property strict

#include "AIDefenseCore.mqh"

//+------------------------------------------------------------------+
//| Time Delay Filter Class                                          |
//+------------------------------------------------------------------+
class CTimeDelayFilter : public CAIDefenseModule
{
private:
   struct DelayedSignal
   {
      datetime signal_time;
      int      signal_bar;
      string   signal_type;
      double   signal_price;
      int      wait_bars;
      bool     active;
   };
   
   DelayedSignal m_delayed_signals[];
   int           m_max_delayed_signals;
   
   // 遅延ルール
   int      m_breakout_delay_bars;
   int      m_reversal_confirm_bars;
   int      m_news_delay_minutes;
   
public:
   CTimeDelayFilter(int breakout_delay = 5,
                   int reversal_confirm = 3,
                   int news_delay_min = 10,
                   double sensitivity = 1.0)
      : CAIDefenseModule("TimeDelay", sensitivity)
   {
      m_breakout_delay_bars = breakout_delay;
      m_reversal_confirm_bars = reversal_confirm;
      m_news_delay_minutes = news_delay_min;
      m_max_delayed_signals = 10;
      
      ArrayResize(m_delayed_signals, m_max_delayed_signals);
      for(int i = 0; i < m_max_delayed_signals; i++)
      {
         m_delayed_signals[i].active = false;
      }
   }
   
   virtual AIDefenseSignal Analyze(const double &high[], const double &low[],
                                   const double &close[], const long &volume[])
   {
      AIDefenseSignal signal = CreateNeutralSignal();
      
      // 既存の遅延シグナルをチェック
      CheckDelayedSignals(signal, close);
      
      // 新しいシグナルに遅延を適用（外部から呼ばれる想定）
      // このモジュール自体は遅延管理のみ
      
      return signal;
   }
   
   // 外部から呼ばれるメソッド
   bool ShouldDelayEntry(string signal_type, double price, int &wait_bars_out)
   {
      wait_bars_out = 0;
      
      // ブレイクアウトシグナル
      if(StringFind(signal_type, "Breakout") >= 0 || 
         StringFind(signal_type, "Break") >= 0)
      {
         wait_bars_out = m_breakout_delay_bars;
         return true;
      }
      
      // 反転シグナル
      if(StringFind(signal_type, "Reversal") >= 0 ||
         StringFind(signal_type, "Reverse") >= 0)
      {
         wait_bars_out = m_reversal_confirm_bars;
         return true;
      }
      
      // ニュース後のシグナル（時間ベース判定）
      if(IsRecentNewsTime())
      {
         // バー数に変換（1分足想定）
         wait_bars_out = m_news_delay_minutes;
         return true;
      }
      
      return false;
   }
   
   void RegisterDelayedSignal(string signal_type, double price, int wait_bars)
   {
      // 空きスロットを探す
      for(int i = 0; i < m_max_delayed_signals; i++)
      {
         if(!m_delayed_signals[i].active)
         {
            m_delayed_signals[i].signal_time = TimeCurrent();
            m_delayed_signals[i].signal_bar = 0;
            m_delayed_signals[i].signal_type = signal_type;
            m_delayed_signals[i].signal_price = price;
            m_delayed_signals[i].wait_bars = wait_bars;
            m_delayed_signals[i].active = true;
            break;
         }
      }
   }
   
private:
   void CheckDelayedSignals(AIDefenseSignal &signal, const double &close[])
   {
      for(int i = 0; i < m_max_delayed_signals; i++)
      {
         if(!m_delayed_signals[i].active) continue;
         
         // 経過時間チェック
         int bars_elapsed = iBarShift(_Symbol, PERIOD_CURRENT, m_delayed_signals[i].signal_time, false);
         
         if(bars_elapsed >= m_delayed_signals[i].wait_bars)
         {
            // 遅延完了 - 再評価推奨
            signal.WaitBars = 0;
            signal.Reason = StringFormat("Delay completed for %s - Revalidate entry",
                                       m_delayed_signals[i].signal_type);
            
            // シグナル削除
            m_delayed_signals[i].active = false;
         }
         else
         {
            // まだ待機中
            signal.WaitBars = m_delayed_signals[i].wait_bars - bars_elapsed;
            signal.Reason = StringFormat("Waiting %d more bars for %s signal",
                                       signal.WaitBars,
                                       m_delayed_signals[i].signal_type);
         }
      }
   }
   
   bool IsRecentNewsTime()
   {
      // 最近10分以内にニュース発表があったか判定（簡易版）
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      // 00分、30分ちょうどから10分以内
      int minutes_since_news = 999;
      
      if(dt.min >= 0 && dt.min < 10)
         minutes_since_news = dt.min;
      else if(dt.min >= 30 && dt.min < 40)
         minutes_since_news = dt.min - 30;
      
      return (minutes_since_news < m_news_delay_minutes);
   }
};

//+------------------------------------------------------------------+
