//+------------------------------------------------------------------+
//|                                              AIDefenseCore.mqh   |
//|                                   AI Defense Library - Core      |
//|                          CPU-based AI countermeasure framework   |
//+------------------------------------------------------------------+
#property copyright "AI Defense System"
#property strict

//+------------------------------------------------------------------+
//| AI Defense Signal Structure                                      |
//+------------------------------------------------------------------+
struct AIDefenseSignal
{
   bool     TrapDetected;           // AI罠検出フラグ
   bool     TrapCleared;            // 罠解除フラグ
   bool     EmergencyHalt;          // 緊急停止フラグ
   double   ConfidenceAdjustment;   // 信頼度調整 (-1.0 to +1.0)
   int      WaitBars;               // 待機バー数
   int      WaitMinutes;            // 待機分数
   string   TrapType;               // 罠のタイプ
   string   Reason;                 // 検出理由
};

//+------------------------------------------------------------------+
//| AI Defense Module Base Class                                     |
//+------------------------------------------------------------------+
class CAIDefenseModule
{
protected:
   string            m_name;
   double            m_sensitivity;   // 感度 (0.5 = 低, 1.0 = 標準, 2.0 = 高)
   
public:
   CAIDefenseModule(string name = "AIDefense", double sensitivity = 1.0)
   {
      m_name = name;
      m_sensitivity = sensitivity;
   }
   
   virtual ~CAIDefenseModule() {}
   
   // 純粋仮想関数 - 各モジュールで実装
   virtual AIDefenseSignal Analyze(const double &high[], const double &low[], 
                                   const double &close[], const long &volume[]) = 0;
   
   // ユーティリティ関数
   double CalculateATR(const double &high[], const double &low[], 
                       const double &close[], int period = 14, int shift = 0)
   {
      if(shift + period >= ArraySize(high)) return 0.0;
      
      double atr = 0.0;
      for(int i = shift; i < shift + period; i++)
      {
         double tr = MathMax(high[i] - low[i],
                     MathMax(MathAbs(high[i] - close[i+1]),
                            MathAbs(low[i] - close[i+1])));
         atr += tr;
      }
      return atr / period;
   }
   
   double CalculateVolatility(const double &close[], int period = 20, int shift = 0)
   {
      if(shift + period >= ArraySize(close)) return 0.0;
      
      // 標準偏差を計算
      double mean = 0.0;
      for(int i = shift; i < shift + period; i++)
         mean += close[i];
      mean /= period;
      
      double variance = 0.0;
      for(int i = shift; i < shift + period; i++)
         variance += MathPow(close[i] - mean, 2);
      
      return MathSqrt(variance / period);
   }
   
   double CalculateSMA(const double &price[], int period, int shift = 0)
   {
      if(shift + period >= ArraySize(price)) return 0.0;
      
      double sum = 0.0;
      for(int i = shift; i < shift + period; i++)
         sum += price[i];
      
      return sum / period;
   }
   
   double CalculateRSI(const double &close[], int period = 14, int shift = 0)
   {
      if(shift + period + 1 >= ArraySize(close)) return 50.0;
      
      double gains = 0.0, losses = 0.0;
      
      for(int i = shift; i < shift + period; i++)
      {
         double change = close[i] - close[i+1];
         if(change > 0) gains += change;
         else losses -= change;
      }
      
      if(losses == 0.0) return 100.0;
      
      double rs = (gains / period) / (losses / period);
      return 100.0 - (100.0 / (1.0 + rs));
   }
   
   bool IsRoundNumber(double price, int pip_precision = 2)
   {
      // ラウンドナンバー判定（例: 140.00, 140.50など）
      double multiplier = MathPow(10, pip_precision);
      double normalized = price * multiplier;
      double remainder = MathMod(normalized, 50);
      
      return (remainder < 5 || remainder > 45);
   }
   
   string GetName() { return m_name; }
   void SetSensitivity(double sens) { m_sensitivity = MathMax(0.1, MathMin(3.0, sens)); }
};

//+------------------------------------------------------------------+
//| AI Defense Aggregator - 複数モジュールの統合                      |
//+------------------------------------------------------------------+
class CAIDefenseAggregator
{
private:
   CAIDefenseModule* m_modules[];
   int               m_module_count;
   
public:
   CAIDefenseAggregator()
   {
      m_module_count = 0;
      ArrayResize(m_modules, 0);
   }
   
   ~CAIDefenseAggregator()
   {
      // モジュールの解放は呼び出し側で管理
      ArrayFree(m_modules);
   }
   
   bool AddModule(CAIDefenseModule* module)
   {
      if(module == NULL) return false;
      
      int new_size = ArraySize(m_modules) + 1;
      ArrayResize(m_modules, new_size);
      m_modules[new_size - 1] = module;
      m_module_count++;
      
      return true;
   }
   
   AIDefenseSignal AggregateSignals(const double &high[], const double &low[],
                                    const double &close[], const long &volume[])
   {
      AIDefenseSignal aggregated;
      aggregated.TrapDetected = false;
      aggregated.TrapCleared = false;
      aggregated.EmergencyHalt = false;
      aggregated.ConfidenceAdjustment = 0.0;
      aggregated.WaitBars = 0;
      aggregated.WaitMinutes = 0;
      aggregated.TrapType = "None";
      aggregated.Reason = "";
      
      if(m_module_count == 0) return aggregated;
      
      double total_adjustment = 0.0;
      int max_wait_bars = 0;
      int max_wait_minutes = 0;
      string combined_reasons = "";
      
      // 各モジュールからシグナルを取得
      for(int i = 0; i < m_module_count; i++)
      {
         if(m_modules[i] == NULL) continue;
         
         AIDefenseSignal signal = m_modules[i].Analyze(high, low, close, volume);
         
         // 緊急停止は最優先
         if(signal.EmergencyHalt)
         {
            aggregated.EmergencyHalt = true;
            aggregated.Reason = signal.Reason;
            return aggregated;
         }
         
         // 罠検出フラグ
         if(signal.TrapDetected)
         {
            aggregated.TrapDetected = true;
            aggregated.TrapType = signal.TrapType;
         }
         
         // 罠解除フラグ
         if(signal.TrapCleared)
         {
            aggregated.TrapCleared = true;
         }
         
         // 信頼度調整を累積
         total_adjustment += signal.ConfidenceAdjustment;
         
         // 最大待機時間を取得
         if(signal.WaitBars > max_wait_bars)
            max_wait_bars = signal.WaitBars;
         if(signal.WaitMinutes > max_wait_minutes)
            max_wait_minutes = signal.WaitMinutes;
         
         // 理由を結合
         if(signal.Reason != "")
         {
            if(combined_reasons != "") combined_reasons += " | ";
            combined_reasons += m_modules[i].GetName() + ": " + signal.Reason;
         }
      }
      
      // 統合結果
      aggregated.ConfidenceAdjustment = total_adjustment / m_module_count;
      aggregated.WaitBars = max_wait_bars;
      aggregated.WaitMinutes = max_wait_minutes;
      aggregated.Reason = combined_reasons;
      
      return aggregated;
   }
   
   int GetModuleCount() { return m_module_count; }
};

//+------------------------------------------------------------------+
//| グローバル関数 - 簡易インターフェース                             |
//+------------------------------------------------------------------+
AIDefenseSignal CreateNeutralSignal()
{
   AIDefenseSignal signal;
   signal.TrapDetected = false;
   signal.TrapCleared = false;
   signal.EmergencyHalt = false;
   signal.ConfidenceAdjustment = 0.0;
   signal.WaitBars = 0;
   signal.WaitMinutes = 0;
   signal.TrapType = "None";
   signal.Reason = "";
   return signal;
}

//+------------------------------------------------------------------+
