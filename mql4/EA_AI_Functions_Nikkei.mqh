//+------------------------------------------------------------------+
//|                                       EA_AI_Functions_Nikkei.mqh |
//|                          AI対応関数群（日経225版、GPU不要軽量版）  |
//+------------------------------------------------------------------+
#property copyright "AI Adaptive Trading Functions - Nikkei225"
#property strict

//+------------------------------------------------------------------+
//| マイクロボラティリティフィルター（HFTノイズ除外）                    |
//+------------------------------------------------------------------+
bool CheckMicroVolatility()
{
   if (!g_Use_Micro_Volatility_Filter) return true;
   
   double total_range = 0;
   int noise_count = 0;
   
   for (int i = 1; i <= g_Noise_Detection_Period; i++) {
      double bar_range = iHigh(Symbol(), 0, i) - iLow(Symbol(), 0, i);
      total_range += bar_range;
      
      if (bar_range < g_Min_Bar_Range_Points) {
         noise_count++;
      }
   }
   
   double avg_range = total_range / g_Noise_Detection_Period;
   double noise_ratio = (double)noise_count / g_Noise_Detection_Period;
   
   if (noise_ratio > g_Noise_Ratio_Threshold) {
      if (EnableDebugLog) {
         Print("HFTノイズ検出: ", DoubleToString(noise_ratio * 100, 1), 
               "% (閾値: ", DoubleToString(g_Noise_Ratio_Threshold * 100, 1), "%)");
      }
      return false;
   }
   
   if (EnableDebugLog) {
      Print("✓ マイクロボラ分析: 平均=", DoubleToString(avg_range, 2), 
            " Points, ノイズ率=", DoubleToString(noise_ratio * 100, 1), "%");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| アルゴリズム的価格レベル検出                                        |
//+------------------------------------------------------------------+
bool CheckAlgoPriceLevels(bool is_long, double &detected_level)
{
   if (!g_Use_Algo_Price_Levels) return true;
   
   double current_price = is_long ? Ask : Bid;
   
   // 1. 前日高値/安値（AIがよく参照）
   double yesterday_high = iHigh(Symbol(), PERIOD_D1, 1);
   double yesterday_low = iLow(Symbol(), PERIOD_D1, 1);
   double yesterday_close = iClose(Symbol(), PERIOD_D1, 1);
   
   // 2. 当日VWAP近似値
   double today_high = iHigh(Symbol(), PERIOD_D1, 0);
   double today_low = iLow(Symbol(), PERIOD_D1, 0);
   double today_close = iClose(Symbol(), PERIOD_D1, 0);
   double today_vwap = (today_high + today_low + today_close) / 3.0;
   
   // 3. 0.25刻みレベル（AIの好む価格帯）
   double quarter_level = 0;
   if (g_Use_Quarter_Levels) {
      double increment = 0.25;
      quarter_level = MathRound(current_price / increment) * increment;
   }
   
   // レベル配列
   double levels[5];
   levels[0] = yesterday_high;
   levels[1] = yesterday_low;
   levels[2] = yesterday_close;
   levels[3] = today_vwap;
   levels[4] = quarter_level;
   
   // 価格集中度チェック
   for (int i = 0; i < ArraySize(levels); i++) {
      if (levels[i] == 0) continue;
      
      double distance = MathAbs(current_price - levels[i]);
      
      if (distance < g_Algo_Price_Clustering) {
         detected_level = levels[i];
         string level_name = "";
         if (i == 0) level_name = "前日高値";
         else if (i == 1) level_name = "前日安値";
         else if (i == 2) level_name = "前日終値";
         else if (i == 3) level_name = "VWAP";
         else if (i == 4) level_name = "0.25刻み";
         
         if (EnableDebugLog) {
            Print("★ アルゴ価格レベル検出: ", level_name, " @ ", 
                  DoubleToString(detected_level, Digits),
                  " (現在価格から", DoubleToString(distance, 1), " Points)");
         }
         return true;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| オーダーフロー検出（ティックボリューム分析）                         |
//+------------------------------------------------------------------+
bool DetectAlgoOrderFlow(bool is_long)
{
   if (!g_Use_OrderFlow_Detection) return true;
   
   long current_volume = iVolume(Symbol(), 0, 1);
   long avg_volume = 0;
   
   for (int i = 2; i <= g_OrderFlow_Avg_Period + 1; i++) {
      avg_volume += iVolume(Symbol(), 0, i);
   }
   avg_volume /= g_OrderFlow_Avg_Period;
   
   if (current_volume > avg_volume * g_OrderFlow_Volume_Multi) {
      if (EnableDebugLog) {
         Print("★ アルゴ大量注文検出: Vol=", current_volume, 
               " (平均の", DoubleToString(g_OrderFlow_Volume_Multi, 1), "倍: ", avg_volume, ")");
      }
      return true;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| アルゴ活発時間帯チェック                                           |
//+------------------------------------------------------------------+
bool IsAlgoActiveHours()
{
   if (!g_Use_Algo_TimeFilter) return true;
   
   int hour = TimeHour(TimeCurrent());
   
   if (g_Algo_Active_Start_Hour <= g_Algo_Active_End_Hour) {
      if (hour >= g_Algo_Active_Start_Hour && hour <= g_Algo_Active_End_Hour) {
         return true;
      }
   } else {
      if (hour >= g_Algo_Active_Start_Hour || hour <= g_Algo_Active_End_Hour) {
         return true;
      }
   }
   
   if (EnableDebugLog) {
      Print("アルゴ非活発時間帯: ", hour, "時");
   }
   return false;
}

//+------------------------------------------------------------------+
//| AI学習データログ出力（DLL推論EA用データ収集）                       |
//+------------------------------------------------------------------+
void LogAILearningData(bool is_long, double entry_price, string pattern_type)
{
   if (!g_Enable_AI_Learning_Log) return;
   
   string log_path = g_AI_Learning_Folder + "\\" + g_AI_Learning_LogFile;
   int file_handle = FileOpen(log_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   
   if (file_handle == INVALID_HANDLE) {
      file_handle = FileOpen(log_path, FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (file_handle != INVALID_HANDLE) {
         FileWrite(file_handle, "Timestamp", "Symbol", "Timeframe", "Direction", 
                   "EntryPrice", "PatternType", "EMA12", "EMA25", "EMA100", 
                   "ATR", "ADX", "ChannelWidth", "TickVolume", "BarRange", 
                   "Hour", "DayOfWeek", "AlgoLevel", "NoiseRatio",
                   "Spread", "SpreadMax", "TickVolSurge", "ATRSpikeRatio", "SpoofingSuspect", "PriceChangePct");
         FileClose(file_handle);
      }
   } else {
      FileClose(file_handle);
   }
   
   file_handle = FileOpen(log_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if (file_handle != INVALID_HANDLE) {
      FileSeek(file_handle, 0, SEEK_END);
      
      string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
      string direction = is_long ? "LONG" : "SHORT";
      double bar_range = iHigh(Symbol(), 0, 1) - iLow(Symbol(), 0, 1);
      double adx_value = iADX(Symbol(), 0, 14, PRICE_CLOSE, MODE_MAIN, 1);
      double channel_width = ema12_current - ema100_current;
      long tick_volume = iVolume(Symbol(), 0, 1);
      int hour = TimeHour(TimeCurrent());
      int day_of_week = DayOfWeek();
      
      double algo_level = 0;
      CheckAlgoPriceLevels(is_long, algo_level);
      
      double noise_ratio = 0;
      int noise_count = 0;
      for (int i = 1; i <= 10; i++) {
         double range = iHigh(Symbol(), 0, i) - iLow(Symbol(), 0, i);
         if (range < g_Min_Bar_Range_Points) noise_count++;
      }
      noise_ratio = (double)noise_count / 10.0;
      
      // ✅ レポート2.3節対応: スプレッド変動記録
      int spread_current = (int)MarketInfo(Symbol(), MODE_SPREAD);
      static int spread_max_session = 0;
      if (spread_current > spread_max_session) spread_max_session = spread_current;
      
      // ✅ レポート5.1節対応: ティックボリューム急増検知
      long prev_volume = iVolume(Symbol(), 0, 2);
      double tick_vol_surge = (prev_volume > 0) ? (double)tick_volume / prev_volume : 1.0;
      
      // ✅ レポート4.1節対応: ATRスパイク検知
      double atr_5bars_ago = iATR(Symbol(), 0, 14, 5);
      double atr_spike_ratio = (atr_5bars_ago > 0) ? current_atr / atr_5bars_ago : 1.0;
      
      // ✅ レポート7.2A節対応: スプーフィング疑い検知
      double price_change = MathAbs(Close[1] - Open[1]);
      bool is_doji = (price_change < current_atr * 0.3);  // 実体が小さい
      bool high_volume_doji = (is_doji && tick_vol_surge > 2.0);  // 価格動かず+大量注文
      string spoofing_flag = high_volume_doji ? "YES" : "NO";
      
      // ✅ 価格変動率（%）
      double price_change_pct = (Close[2] > 0) ? MathAbs((Close[1] - Close[2]) / Close[2] * 100) : 0;
      
      FileWrite(file_handle, timestamp, Symbol(), IntegerToString(Period()), direction,
                DoubleToString(entry_price, Digits), pattern_type,
                DoubleToString(ema12_current, Digits), 
                DoubleToString(ema25_current, Digits),
                DoubleToString(ema100_current, Digits),
                DoubleToString(current_atr, 2),
                DoubleToString(adx_value, 2),
                DoubleToString(channel_width, 2),
                IntegerToString(tick_volume),
                DoubleToString(bar_range, 2),
                IntegerToString(hour),
                IntegerToString(day_of_week),
                DoubleToString(algo_level, Digits),
                DoubleToString(noise_ratio, 3),
                IntegerToString(spread_current),
                IntegerToString(spread_max_session),
                DoubleToString(tick_vol_surge, 2),
                DoubleToString(atr_spike_ratio, 2),
                spoofing_flag,
                DoubleToString(price_change_pct, 4));
      
      FileClose(file_handle);
      
      ai_pattern_count++;
      if (EnableDebugLog) {
         Print("AI学習データ記録 #", ai_pattern_count, ": ", pattern_type);
      }
   }
}
