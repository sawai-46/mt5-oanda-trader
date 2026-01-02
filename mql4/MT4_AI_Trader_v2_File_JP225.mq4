//+------------------------------------------------------------------+
//|                                 MT4_AI_Trader_v2_File_JP225.mq4 |
//|                    Phase 6 ファイルベース版 (JP225専用)          |
//|   推論サーバーとファイル経由で通信 + PullbackEntry完全統合       |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "3.00"
#property strict

// Market Sentinel連携（経済指標・要人発言による売買制御）
// #include <MarketSentinel.mqh>  // サービス削除済み - 不要

// マジックナンバー自動生成
#include <MagicNumberGenerator.mqh>

// ※PullbackEntryロジックはPython推論サーバーに統合済み
// シグナル生成: Python側
// ポジション管理: EA側（このファイル）

//--- ファイル通信設定
input string MT4_ID = "10900k-A";               // MT4識別ID（10900k-A, 10900k-B, matsu-A, matsu-B）
input bool   AutoAppendSymbol = true;           // MT4_IDにSymbolを自動追加
input string DataDirectory = "OneDriveLogs\\data";            // データディレクトリ
input int    ResponseTimeout = 30;              // レスポンス待機時間(秒)

//--- 推論サーバー戦略プリセット（MT4入力でプルダウン選択）
enum PresetOption
{
   PRESET_antigravity_pullback = 0,
   PRESET_antigravity_only,
   PRESET_antigravity_hedge,
   PRESET_quantitative_pure,
   PRESET_full,
   PRESET_custom
};
input PresetOption Preset = PRESET_antigravity_pullback;
// PRESET_custom を選んだ時に送るプリセット名（strategy_presets.py のキー）
input string CustomPresetName = "";

string GetPresetName()
{
   switch(Preset)
   {
      case PRESET_antigravity_only:        return "antigravity_only";
      case PRESET_antigravity_hedge:       return "antigravity_hedge";
      case PRESET_quantitative_pure:      return "quantitative_pure";
      case PRESET_full:                   return "full";
      case PRESET_custom:
      {
         string name = CustomPresetName;
         StringTrimLeft(name);
         StringTrimRight(name);
         if(StringLen(name) > 0)
            return name;
         return "antigravity_pullback";
      }
      case PRESET_antigravity_pullback:
      default:                            return "antigravity_pullback";
   }
}

//--- SignalManager設定
input int    MinConfirmations = 2;      // 最小確認数
input double MinConfidence = 0.60;      // 最小信頼度
input bool   UseCandlePatterns = true;  // ローソク足パターン使用
input bool   UseIndicators = true;      // テクニカル指標使用
input bool   UseChartPatterns = true;   // チャートパターン使用

//--- 基本トレード設定
input double RiskPercent = 1.0;         // リスク率(%)
input double BaseLotSize = 0.1;         // 基本ロット（基準）
input double MaxLotSize = 1.0;          // 最大ロットサイズ（上限）
input bool   EnableLotAdjustment = true; // ロット自動調整有効化
input double MaxSlippagePips = 50.0;      // 最大スリッページ(円) ※推奨
input int    MaxSlippagePoints = 0;       // 最大スリッページ(points) ※互換用、0=SlippagePips使用
input double MaxSpreadPoints = 10.0;    // 最大スプレッド(円) ※通常5-10円
input int    DefaultSLPoints = 200;     // デフォルトSL(points) ※JP225推奨値
input int    DefaultTPPoints = 400;     // デフォルトTP(points) ※JP225推奨値
input bool   AutoMagicNumber = true;    // マジックナンバー自動生成
input int    MagicNumber = 20250124;    // マジックナンバー（自動生成時は無視）

//--- 時間フィルター設定
input bool   Enable_Time_Filter = true;         // 時間フィルター有効化
input int    GMT_Offset = 3;                     // GMTオフセット（サーバー時間-GMT）
input bool   Use_DST = false;                    // 夏時間適用（+1時間）
input int    Custom_Start_Hour = 8;              // 稼働開始時(日本時間)
input int    Custom_Start_Minute = 0;            // 稼働開始分
input int    Custom_End_Hour = 21;               // 稼働終了時(日本時間)
input int    Custom_End_Minute = 0;              // 稼働終了分
input bool   TradeOnFriday = true;               // 金曜取引許可

//--- フィルター設定
input int    MaxPositions = 2;          // 最大ポジション数
input int    MinBarsSinceLastTrade = 10; // 最小バー間隔
input double MinConfidenceForEntry = 0.65; // エントリー最小信頼度

//--- ※Strong Trend Mode、ADX、ATRフィルターはPython側に統合済み（削除）

//--- Partial Close設定（現在ロットに対する%、合計100%になるよう設定）
input bool   EnablePartialClose = true;     // 部分決済有効化
input int    PartialCloseStages = 2;        // 段階数(2=二段階, 3=三段階)
input double PartialClose1Points = 100.0;   // 1段階目(points) ※JP225推奨値
input double PartialClose1Percent = 50.0;   // 1段階目決済率(%) ※二段階:50, 三段階:30
input double PartialClose2Points = 200.0;   // 2段階目(points) ※JP225推奨値
input double PartialClose2Percent = 100.0;  // 2段階目決済率(%) ※二段階:100, 三段階:50
input double PartialClose3Points = 300.0;   // 3段階目(points) ※JP225推奨値
input double PartialClose3Percent = 100.0;  // 3段階目決済率(%) ※三段階:100(残り全部)
input bool   MoveToBreakEvenAfterLevel1 = true; // Level1後にSL移動(建値へ)
input bool   MoveSLAfterLevel2 = true;      // Level2後にSL移動(Level1利益位置へ) ※三段階時

//--- CSV Logging設定（PullbackEntry統合）
input bool   EnableCsvLogging = false;      // CSVログ有効化
input string LogDirectory = "OneDriveLogs\\AI_Trader_Logs"; // ログディレクトリ
input bool   EnableDebugLog = false;        // デバッグログ有効化

//--- AI学習データ記録設定
input bool   Enable_AI_Learning_Log = true; // AI学習データ記録有効化
input string AI_Learning_Folder = "OneDriveLogs\\data\\AI_Learning"; // 学習データ保存フォルダ

//--- SL/TP設定（ポジション管理用）
input double StopLoss_Fixed_Points = 100.0;   // 固定SL(points) ※JP225推奨値
input double TakeProfit_Fixed_Points = 200.0; // 固定TP(points) ※JP225推奨値
input bool   Use_ATR_SLTP = false;          // ATR倍率使用
input double StopLoss_ATR_Multi = 1.5;      // SL用ATR倍率
input double TakeProfit_ATR_Multi = 2.0;    // TP用ATR倍率

// ※プルバック検出、EMA設定、ラウンドナンバー等はPython推論サーバーで処理

//--- グローバル変数
datetime g_lastTradeTime = 0;
int g_lastTradeBar = 0;
// ※g_strongTrendActiveはPython側に統合済み（削除）

// 実際に使用するマジックナンバー（自動生成または手動設定）
int g_ActiveMagicNumber = 0;

// ファイルパス
string g_requestFile = "";
string g_responseFile = "";
string g_statusFile = "";

// Partial Close状態管理
int g_partialCloseLevel[];  // 各ポジションのレベル（0-3）
int g_logFileHandle = -1;
string g_currentLogFile = "";

// AI学習データ記録用
string g_AI_Learning_LogFile = "";
int g_ai_pattern_count = 0;

// スリッページ変換関数（円からpointsへ）
int EffectiveSlippagePoints(){
   // MaxSlippagePips（円）が0より大きければ優先使用
   if(MaxSlippagePips > 0.0){
      // JP225: 1円 = 100 points (Point = 0.01)
      return (int)MathRound(MaxSlippagePips * 1.0 / Point);
   }
   // 互換用: MaxSlippagePointsをそのまま使用
   return MaxSlippagePoints;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Market Sentinel初期化
   // MS_Init();  // サービス削除済み - 不要
   
   // マジックナンバー初期化（AI Traderはプリセット00）
   if (AutoMagicNumber) {
      g_ActiveMagicNumber = GenerateMagicNumber(EA_TYPE_AI_TRADER_FILE, Symbol(), PRESET_AI_TRADER);
      Print("マジックナンバー自動生成: ", g_ActiveMagicNumber);
      PrintMagicNumberInfo(g_ActiveMagicNumber);
   } else {
      g_ActiveMagicNumber = MagicNumber;
      Print("マジックナンバー手動設定: ", g_ActiveMagicNumber);
   }
   
   Print("=== MT4 AI Trader v4.0 File-based (JP225専用) ===");
   Print("シグナル生成: Python推論サーバー");
   Print("ポジション管理: EA側");
   Print("MT4 ID: ", MT4_ID);
   Print("Data Directory: ", DataDirectory);
   Print("Magic Number: ", g_ActiveMagicNumber, AutoMagicNumber ? " (自動生成)" : " (手動設定)");
   Print("Partial Close: ", EnablePartialClose ? "ON" : "OFF");
   Print("CSV Logging: ", EnableCsvLogging ? "ON" : "OFF");
   
   // ユニークID生成（Symbol自動追加）
   string uniqueId = MT4_ID;
   if(AutoAppendSymbol || StringLen(MT4_ID) == 0)
   {
      // PC1_JP225_M5 のような形式
      string tfStr = "";
      switch(Period())
      {
         case PERIOD_M1:  tfStr = "M1"; break;
         case PERIOD_M5:  tfStr = "M5"; break;
         case PERIOD_M15: tfStr = "M15"; break;
         case PERIOD_M30: tfStr = "M30"; break;
         case PERIOD_H1:  tfStr = "H1"; break;
         case PERIOD_H4:  tfStr = "H4"; break;
         case PERIOD_D1:  tfStr = "D1"; break;
         default:         tfStr = IntegerToString(Period()); break;
      }
      if(StringLen(MT4_ID) == 0)
         uniqueId = Symbol() + "_" + tfStr;
      else
         uniqueId = MT4_ID + "_" + Symbol() + "_" + tfStr;
   }
   Print("Unique ID: ", uniqueId);
   
   // ファイルパス設定
   g_requestFile = DataDirectory + "\\request_" + uniqueId + ".csv";
   g_responseFile = DataDirectory + "\\response_" + uniqueId + ".csv";
   g_statusFile = DataDirectory + "\\server_status.txt";
   
   Print("Request File: ", g_requestFile);
   Print("Response File: ", g_responseFile);
   
   // データディレクトリ作成
   if(!CreateDataDirectory())
   {
      Print("[ERROR] データディレクトリの作成に失敗しました");
      return(INIT_FAILED);
   }
   
   // Partial Close配列初期化
   if(EnablePartialClose)
   {
      ArrayResize(g_partialCloseLevel, 100);
      ArrayInitialize(g_partialCloseLevel, 0);
   }
   
   // CSVログ初期化
   if(EnableCsvLogging)
   {
      InitializeCsvLog();
   }
   
   // AI学習データ記録初期化
   if(Enable_AI_Learning_Log)
   {
      InitializeAILearningLog();
   }
   
   // サーバー接続テスト
   if(!CheckServerStatus())
   {
      Print("[WARNING] 推論サーバーが起動していない可能性があります");
      Print("  python inference_server_file.py を起動してください");
   }
   else
   {
      Print("✓ 推論サーバー接続OK");
   }
   
   Print("初期化完了");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ログファイルクローズ
   if(g_logFileHandle != -1)
   {
      FileClose(g_logFileHandle);
      g_logFileHandle = -1;
   }
   
   Print("EA終了 - 理由: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Market Sentinelによる売買許可チェック（毎分更新）
   // Market Sentinelによる売買許可チェック（毎分更新）
   // サービス削除済み - 不要
   
   // 新しいバーでのみ実行
   static datetime lastBarTime = 0;
   if(Time[0] == lastBarTime)
      return;
   lastBarTime = Time[0];
   
   // Partial Close チェック
   if(EnablePartialClose)
   {
      CheckPartialClose();
   }
   
   // Market Sentinelで取引停止中ならエントリーしない
   // サービス削除済み - 常にエントリー許可
   
   // メインロジック
   AnalyzeAndTrade();
}

//+------------------------------------------------------------------+
//| データディレクトリ作成                                           |
//+------------------------------------------------------------------+
bool CreateDataDirectory()
{
   string testFile = DataDirectory + "\\test.txt";
   int handle = FileOpen(testFile, FILE_WRITE|FILE_TXT);
   if(handle == INVALID_HANDLE)
   {
      Print("[ERROR] ディレクトリ作成失敗: ", DataDirectory);
      return false;
   }
   FileClose(handle);
   FileDelete(testFile);
   return true;
}

//+------------------------------------------------------------------+
//| サーバーステータス確認                                           |
//+------------------------------------------------------------------+
bool CheckServerStatus()
{
   int handle = FileOpen(g_statusFile, FILE_READ|FILE_TXT);
   if(handle == INVALID_HANDLE)
      return false;
   
   string status = FileReadString(handle);
   FileClose(handle);
   
   return (StringFind(status, "running") >= 0);
}

//+------------------------------------------------------------------+
//| メイン分析・トレードロジック（軽量版）                            |
//| シグナル生成: Python推論サーバーに委譲                         |
//| ポジション管理: EA側で実施                                     |
//+------------------------------------------------------------------+
void AnalyzeAndTrade()
{
   // サーバーチェック
   if(!CheckServerStatus())
   {
      static datetime lastWarning = 0;
      if(TimeCurrent() - lastWarning > 60)  // 1分に1回警告
      {
         Print("[WARNING] 推論サーバーが起動していません");
         lastWarning = TimeCurrent();
      }
      return;
   }
   
   // フィルターチェック
   if(!PassesTimeFilter())
   {
      return;
   }
   
   if(CountOpenPositions() >= MaxPositions)
   {
      return;
   }
   
   if(Bars - g_lastTradeBar < MinBarsSinceLastTrade)
   {
      return;
   }
   
   // スプレッドチェック（日経225: 1ポイント=1円なので直接計算）
   double spread_points = Ask - Bid;  // 日経225では直接差分がポイント値
   if(spread_points > MaxSpreadPoints)
   {
      Print("スプレッドが広すぎます: ", DoubleToString(spread_points, 1), " points (閾値: ", MaxSpreadPoints, " points)");
      return;
   }
   
   // ※Strong Trend ModeはPython側に統合済み
   
   // リクエストファイル書き込み
   if(!WriteRequestFile())
   {
      Print("[ERROR] リクエストファイルの書き込みに失敗");
      return;
   }
   
   // レスポンス待機
   int signal = 0;
   double confidence = 0.0;
   string reason = "";
   
   if(!WaitForResponse(signal, confidence, reason))
   {
      Print("[ERROR] レスポンスの取得に失敗");
      return;
   }
      // ※信頼度ブーストはPython側に統合済み   
   // エントリー判定
   if(signal == 0)
   {
      if(EnableCsvLogging)
         LogTradeEvent("SKIP", 0, 0, signal, confidence, "No clear signal");
      return;
   }
   
   if(confidence < MinConfidenceForEntry)
   {
      if(EnableCsvLogging)
         LogTradeEvent("SKIP", 0, 0, signal, confidence, "Confidence too low");
      return;
   }
      // ※ATR閾値チェックはPython側に統合済み   
   // エントリー実行
   ExecuteTrade(signal, confidence);
}

//+------------------------------------------------------------------+
//| リクエストファイル書き込み                                        |
//+------------------------------------------------------------------+
bool WriteRequestFile()
{
   // NOTE: Python推論サーバーはセミコロン区切りで入出力するため、区切り文字を明示する
   int handle = FileOpen(g_requestFile, FILE_WRITE|FILE_CSV, ';');
   if(handle == INVALID_HANDLE)
   {
      Print("[ERROR] リクエストファイルを開けません: ", g_requestFile);
      return false;
   }
   
   // ヘッダー（推論サーバーが期待するフォーマット）
   // NOTE: Python側は `prices`(最新→過去の終値CSV) を主要入力として使用する
   FileWrite(handle, "symbol", "timeframe", "preset", "ema12", "ema25", "ema100", "atr", "close", "prices");
   
   // インジケーター
   double ema12 = iMA(Symbol(), 0, 12, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ema25 = iMA(Symbol(), 0, 25, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ema100 = iMA(Symbol(), 0, 100, 0, MODE_EMA, PRICE_CLOSE, 0);
   double atr = iATR(Symbol(), 0, 14, 0);
   double close = Close[0];

   // 終値履歴（最新→過去）
   string prices = "";
   int pricesCount = MathMin(120, Bars);
   for(int i = 0; i < pricesCount; i++)
   {
      if(i > 0) prices += ",";
      prices += DoubleToString(Close[i], Digits);
   }
   
   // データ行
   FileWrite(handle, 
             Symbol(), 
             GetTimeframeString(),
             GetPresetName(),
             DoubleToString(ema12, Digits),
             DoubleToString(ema25, Digits),
             DoubleToString(ema100, Digits),
             DoubleToString(atr, Digits),
             DoubleToString(close, Digits),
             prices);
   
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
//| レスポンス待機・読み込み                                          |
//+------------------------------------------------------------------+
bool WaitForResponse(int &signal, double &confidence, string &reason)
{
   datetime startTime = TimeCurrent();
   
   while(TimeCurrent() - startTime < ResponseTimeout)
   {
      if(FileIsExist(g_responseFile))
      {
         Sleep(100);  // ファイル書き込み完了待ち
         
         // NOTE: サーバー出力に合わせてセミコロン区切りを明示する
         int handle = FileOpen(g_responseFile, FILE_READ|FILE_CSV, ';');
         if(handle == INVALID_HANDLE)
         {
            Sleep(100);
            continue;
         }
         
         // Pythonサーバー出力CSV形式:
         // header: signal;confidence;reason;timestamp
         // data  : <int>;<float>;<string>;<iso>
         // ヘッダー行（4フィールド）をスキップ
         for(int i = 0; i < 4 && !FileIsEnding(handle); i++)
            FileReadString(handle);
         
         // データ読み込み（4フィールド）
         signal = (int)FileReadNumber(handle);
         confidence = FileReadNumber(handle);
         reason = FileReadString(handle);
         string timestamp = FileReadString(handle);
         
         FileClose(handle);
         FileDelete(g_responseFile);
         
         Print("Response: signal=", signal, " conf=", DoubleToString(confidence, 3), " reason=", reason);
         return true;
      }
      
      Sleep(100);
   }
   
   Print("[ERROR] レスポンスタイムアウト");
   return false;
}

//+------------------------------------------------------------------+
//| トレード実行（軽量版）                                            |
//| シグナル生成はPython側、ポジション管理はEA側                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal, double confidence)
{
   bool is_long = (signal == 1);
   double entry_price = is_long ? Ask : Bid;
   
   double lotSize = CalculateLotSize();
   
   // Market Sentinelによるロットサイズ調整
   // サービス削除済み - 調整なし
   
   // SL/TP計算
   double sl = 0, tp = 0;
   CalculateSLTP(is_long, entry_price, sl, tp);
   
   int ticket = 0;
   int slippage = EffectiveSlippagePoints();
   
   if(is_long)  // BUY
   {
      ticket = OrderSend(Symbol(), OP_BUY, lotSize, Ask, slippage, 
                         NormalizeDouble(sl, Digits), 
                         NormalizeDouble(tp, Digits), 
                         "AI_BUY_" + DoubleToString(confidence, 2), 
                         g_ActiveMagicNumber, 0, clrBlue);
      
      if(ticket > 0)
      {
         Print("★ BUY注文成功: Ticket=", ticket, " Conf=", DoubleToString(confidence, 3),
               " SL=", DoubleToString(sl, Digits), " TP=", DoubleToString(tp, Digits));
         g_lastTradeTime = TimeCurrent();
         g_lastTradeBar = Bars;
         
         if(EnablePartialClose)
            g_partialCloseLevel[ticket % 100] = 0;
         
         if(EnableCsvLogging)
            LogTradeEvent("ENTRY", ticket, OP_BUY, signal, confidence, "BUY executed");
         
         // AI学習データ記録
         if(Enable_AI_Learning_Log)
            LogAILearningData(true, Ask, "AI_SIGNAL", confidence);
      }
      else
      {
         Print("BUY注文失敗: Error=", GetLastError());
      }
   }
   else  // SELL
   {
      ticket = OrderSend(Symbol(), OP_SELL, lotSize, Bid, slippage, 
                         NormalizeDouble(sl, Digits), 
                         NormalizeDouble(tp, Digits),
                         "AI_SELL_" + DoubleToString(confidence, 2),
                         g_ActiveMagicNumber, 0, clrRed);
      
      if(ticket > 0)
      {
         Print("★ SELL注文成功: Ticket=", ticket, " Conf=", DoubleToString(confidence, 3),
               " SL=", DoubleToString(sl, Digits), " TP=", DoubleToString(tp, Digits));
         g_lastTradeTime = TimeCurrent();
         g_lastTradeBar = Bars;
         
         if(EnablePartialClose)
            g_partialCloseLevel[ticket % 100] = 0;
         
         if(EnableCsvLogging)
            LogTradeEvent("ENTRY", ticket, OP_SELL, signal, confidence, "SELL executed");
         
         // AI学習データ記録
         if(Enable_AI_Learning_Log)
            LogAILearningData(false, Bid, "AI_SIGNAL", confidence);
      }
      else
      {
         Print("SELL注文失敗: Error=", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Partial Close チェック                                           |
//+------------------------------------------------------------------+
void CheckPartialClose()
{
   static datetime lastDebugTime = 0;
   bool showDebug = (TimeCurrent() - lastDebugTime >= 10);  // 10秒ごとにデバッグ出力
   
   if(showDebug && OrdersTotal() > 0)
      Print("[DEBUG] CheckPartialClose開始: OrdersTotal=", OrdersTotal(), ", MagicNumber=", g_ActiveMagicNumber, ", Symbol=", Symbol());
   
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      
      if(showDebug)
         Print("[DEBUG] Order[", i, "]: Magic=", OrderMagicNumber(), ", Sym=", OrderSymbol(), ", Ticket=", OrderTicket());
      
      if(OrderMagicNumber() != g_ActiveMagicNumber || OrderSymbol() != Symbol())
         continue;
      
      int ticket = OrderTicket();
      int ticketIndex = ticket % 100;
      int currentLevel = g_partialCloseLevel[ticketIndex];
      
      // 最大レベル判定（二段階 or 三段階）
      int maxLevel = (PartialCloseStages >= 3) ? 3 : 2;
      
      if(currentLevel >= maxLevel)
         continue;  // 全レベル完了
      
      double openPrice = OrderOpenPrice();
      double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
      double profitPoints = 0;
      
      // points単位で計算
      if(OrderType() == OP_BUY)
         profitPoints = (currentPrice - openPrice) / Point;
      else
         profitPoints = (openPrice - currentPrice) / Point;
      
      if(showDebug)
      {
         Print("[DEBUG] Ticket #", ticket, ": Level=", currentLevel, ", ProfitPoints=", DoubleToString(profitPoints, 1), 
               ", Target1=", PartialClose1Points, " points");
         lastDebugTime = TimeCurrent();
      }
      
      // レベル判定
      double targetPoints = 0;
      double closePercent = 0;
      int newLevel = currentLevel;
      
      if(currentLevel == 0 && profitPoints >= PartialClose1Points)
      {
         targetPoints = PartialClose1Points;
         closePercent = PartialClose1Percent;  // 二段階: 50%, 三段階: 30%
         newLevel = 1;
      }
      else if(currentLevel == 1 && profitPoints >= PartialClose2Points)
      {
         targetPoints = PartialClose2Points;
         // 二段階モード: 残り全部決済（元の50%）
         // 三段階モード: 現在ロットの一部を決済
         if(maxLevel == 2)
            closePercent = 100.0;  // 残りポジション全決済 = 元の50%
         else
            closePercent = PartialClose2Percent;
         newLevel = 2;
      }
      else if(maxLevel >= 3 && currentLevel == 2 && profitPoints >= PartialClose3Points)
      {
         // 三段階モードのみ
         targetPoints = PartialClose3Points;
         closePercent = PartialClose3Percent;
         newLevel = 3;
      }
      else
      {
         continue;  // 条件未達
      }
      
      // 部分決済実行
      int orderType = OrderType();  // SL移動用に保存
      double currentLots = OrderLots();
      double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
      if(lotStep <= 0) lotStep = 0.01;
      double minLot = MarketInfo(Symbol(), MODE_MINLOT);

      double lotsToClose = currentLots * closePercent / 100.0;
      // 余計に閉じてしまうのを避けるため、ロットは切り捨てでステップに合わせる
      lotsToClose = MathFloor(lotsToClose / lotStep) * lotStep;
      lotsToClose = NormalizeDouble(lotsToClose, 2);
      if(lotsToClose < minLot)
         lotsToClose = minLot;

      // 三段階運用で中間レベルの場合、次のレベル用に最小ロットを必ず残す
      if(maxLevel >= 3 && newLevel < maxLevel)
      {
         double remainingLots = currentLots - lotsToClose;
         if(remainingLots < minLot)
         {
            lotsToClose = currentLots - minLot;
            lotsToClose = MathFloor(lotsToClose / lotStep) * lotStep;
            lotsToClose = NormalizeDouble(lotsToClose, 2);

            if(lotsToClose < minLot)
            {
               Print("!!! Partial Close Level ", newLevel, " skipped: lots too small for staging (current=", DoubleToString(currentLots, 2), ", minLot=", DoubleToString(minLot, 2), ", step=", DoubleToString(lotStep, 2), ")");
               continue;
            }
         }
      }
      
      // スリッページ
      int slippage = EffectiveSlippagePoints();
      
      bool closeResult = false;
      if(OrderType() == OP_BUY)
         closeResult = OrderClose(ticket, lotsToClose, Bid, slippage, clrGreen);
      else
         closeResult = OrderClose(ticket, lotsToClose, Ask, slippage, clrOrange);
      
      if(closeResult)
      {
         Print("★ Partial Close Level ", newLevel, ": Ticket=", ticket, 
               " Lots=", DoubleToString(lotsToClose, 2), 
               " Profit=", DoubleToString(profitPoints, 1), " points");
         
         g_partialCloseLevel[ticketIndex] = newLevel;
         
         if(EnableCsvLogging)
            LogTradeEvent("PARTIAL_CLOSE", ticket, OrderType(), newLevel, profitPoints, 
                          "Level " + IntegerToString(newLevel) + " closed");
         
         // ========== EA_PullbackEntry方式：部分決済後の処理 ==========
         // サーバー処理待機
         Sleep(100);
         
         // 新しいチケット番号を取得（MagicNumberとSymbolのみで検索）
         int remainingTicket = -1;
         for(int j = OrdersTotal() - 1; j >= 0; j--)
         {
            if(OrderSelect(j, SELECT_BY_POS, MODE_TRADES))
            {
               if(OrderSymbol() == Symbol() && OrderMagicNumber() == g_ActiveMagicNumber)
               {
                  remainingTicket = OrderTicket();
                  Print("★ 一部決済後の新チケット: #", remainingTicket, ", 残ロット: ", DoubleToString(OrderLots(), 2));
                  break;
               }
            }
         }
         
         if(remainingTicket > 0)
         {
            // 新しいチケット番号でレベルを更新
            int newTicketIndex = remainingTicket % 100;
            g_partialCloseLevel[newTicketIndex] = newLevel;
            
            // Level 1後にBreakEven移動
            if(newLevel == 1 && MoveToBreakEvenAfterLevel1)
            {
               if(OrderSelect(remainingTicket, SELECT_BY_TICKET))
               {
                  double newSL = NormalizeDouble(openPrice, Digits);
                  double currentSL = OrderStopLoss();
                  
                  // SLが建値より不利な位置にある場合のみ移動
                  bool shouldModify = false;
                  if(orderType == OP_BUY && (currentSL == 0 || currentSL < openPrice))
                     shouldModify = true;
                  else if(orderType == OP_SELL && (currentSL == 0 || currentSL > openPrice))
                     shouldModify = true;
                  
                  if(shouldModify)
                  {
                     if(OrderModify(remainingTicket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrYellow))
                        Print(">>> SLを建値へ移動: ", DoubleToString(newSL, Digits), " (ticket=", remainingTicket, ")");
                     else
                        Print("!!! SL移動失敗: Error=", GetLastError());
                  }
               }
            }
            
            // 三段階モード: Level 2後にSLを1段階目の利益位置に移動
            if(newLevel == 2 && maxLevel >= 3 && MoveSLAfterLevel2)
            {
               if(OrderSelect(remainingTicket, SELECT_BY_TICKET))
               {
                  double level1Price;
                  if(orderType == OP_BUY)
                     level1Price = openPrice + PartialClose1Points * Point;
                  else
                     level1Price = openPrice - PartialClose1Points * Point;
                  
                  level1Price = NormalizeDouble(level1Price, Digits);
                  
                  if(OrderModify(remainingTicket, OrderOpenPrice(), level1Price, OrderTakeProfit(), 0, clrAqua))
                     Print(">>> SLをLevel1利益位置へ移動: ", DoubleToString(level1Price, Digits), " (ticket=", remainingTicket, ")");
                  else
                     Print("!!! SL移動失敗: Error=", GetLastError());
               }
            }
         }
         else
         {
            Print("!!! 残ポジションが見つかりません");
         }
      }
   }
}

// ※ShouldActivateStrongTrendModeはPython側に統合済み（削除）

//+------------------------------------------------------------------+
//| CSV ログ初期化（PullbackEntry統合）                              |
//+------------------------------------------------------------------+
void InitializeCsvLog()
{
   // ログフォルダ作成
   string logFolder = LogDirectory + "\\" + Symbol() + "_" + GetTimeframeString();
   EnsureFolderPath(logFolder);
   
   // ログファイル名
   g_currentLogFile = logFolder + "\\" + Symbol() + "_" + 
                      TimeToString(TimeCurrent(), TIME_DATE) + ".csv";
   
   // ファイルオープン
   g_logFileHandle = FileOpen(g_currentLogFile, FILE_WRITE|FILE_CSV|FILE_READ, ",");
   
   if(g_logFileHandle == -1)
   {
      Print("CSVログファイルを開けません: ", g_currentLogFile);
      return;
   }
   
   // ヘッダー書き込み
   if(FileSize(g_logFileHandle) == 0)
   {
      FileWrite(g_logFileHandle, "Timestamp", "Event", "Ticket", "OrderType", 
                "Signal", "Confidence", "Level", "Points", "Reason");
   }
   
   Print("CSV Log initialized: ", g_currentLogFile);
}

//+------------------------------------------------------------------+
//| ログフォルダ作成（階層対応）                                     |
//+------------------------------------------------------------------+
bool EnsureFolderPath(string folderPath)
{
   string path = folderPath;
   StringReplace(path, "/", "\\");
   while(StringLen(path) > 0 && StringSubstr(path, StringLen(path) - 1, 1) == "\\")
      path = StringSubstr(path, 0, StringLen(path) - 1);

   // MQL4のファイルI/Oは通常 MQL4\\Files 配下の相対パスが前提
   if(StringLen(path) >= 2 && StringSubstr(path, 1, 1) == ":")
   {
      Print("[ERROR] LogDirectoryは相対パスにしてください: ", path);
      return false;
   }

   string parts[];
   int n = StringSplit(path, '\\', parts);
   if(n <= 0)
      return false;

   string current = "";
   for(int i = 0; i < n; i++)
   {
      if(StringLen(parts[i]) == 0)
         continue;
      current = (StringLen(current) == 0) ? parts[i] : (current + "\\" + parts[i]);
      FolderCreate(current);
   }
   return true;
}

//+------------------------------------------------------------------+
//| トレードイベントログ記録                                         |
//+------------------------------------------------------------------+
void LogTradeEvent(string eventType, int ticket, int orderType, 
                   int signalOrLevel, double confidenceOrPoints, string reason)
{
   if(g_logFileHandle == -1)
      return;
   
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string orderTypeStr = (orderType == OP_BUY) ? "BUY" : (orderType == OP_SELL) ? "SELL" : "N/A";
   
   FileWrite(g_logFileHandle, 
             timestamp, 
             eventType, 
             IntegerToString(ticket),
             orderTypeStr,
             IntegerToString(signalOrLevel),
             DoubleToString(confidenceOrPoints, 3),
             "",
             "",
             reason);
   
   FileFlush(g_logFileHandle);
}

//+------------------------------------------------------------------+
//| タイムフレーム文字列取得                                         |
//+------------------------------------------------------------------+
string GetTimeframeString()
{
   switch(Period())
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| ユーティリティ関数群                                             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 取引時間チェック（日本時間ベース）                                |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   // 時間フィルター無効の場合は常にtrue
   if (!Enable_Time_Filter)
      return true;
   
   datetime server_time = TimeCurrent();
   int server_hour = TimeHour(server_time);
   int server_minute = TimeMinute(server_time);
   
   // サーバー時間からGMTへ変換
   int gmt_offset_seconds = GMT_Offset * 3600;
   if (Use_DST) gmt_offset_seconds += 3600;  // 夏時間は+1時間
   datetime gmt_time = server_time - gmt_offset_seconds;
   
   // GMTから日本時間へ変換 (GMT+9)
   datetime jst_time = gmt_time + (9 * 3600);
   int jst_hour = TimeHour(jst_time);
   int jst_minute = TimeMinute(jst_time);
   
   // 時間範囲チェック（分単位）
   int start_minutes = Custom_Start_Hour * 60 + Custom_Start_Minute;
   int end_minutes = Custom_End_Hour * 60 + Custom_End_Minute;
   int current_minutes = jst_hour * 60 + jst_minute;
   
   if (start_minutes <= end_minutes) {
      // 通常パターン (例: 8:00 - 21:00)
      return (current_minutes >= start_minutes && current_minutes <= end_minutes);
   } else {
      // 深夜をまたぐパターン (例: 22:00 - 6:00)
      return (current_minutes >= start_minutes || current_minutes <= end_minutes);
   }
}

bool PassesTimeFilter()
{
   int dayOfWeek = TimeDayOfWeek(TimeCurrent());
   
   // 金曜日チェック
   if(dayOfWeek == 5 && !TradeOnFriday)
      return false;
   
   // 時間フィルターチェック
   if(!IsWithinTradingHours())
      return false;
   
   return true;
}

int CountOpenPositions()
{
   int count = 0;
   for(int i=0; i<OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == g_ActiveMagicNumber && OrderSymbol() == Symbol())
            count++;
      }
   }
   return count;
}

double CalculateLotSize()
{
   double lotSize = BaseLotSize;
   
   // ロット自動調整が有効な場合、リスク率から計算
   if(EnableLotAdjustment)
   {
      double balance = AccountBalance();
      double riskAmount = balance * RiskPercent / 100.0;
      double stopLossYen = DefaultSLPoints;  // 円で計算
      double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
      
      if(tickValue > 0 && stopLossYen > 0)
      {
         // JP225: stopLossYenは円単位、tickValueは1ポイントあたりの価値
         lotSize = riskAmount / (stopLossYen * tickValue / Point);
      }
   }
   
   lotSize = NormalizeDouble(lotSize, 2);
   
   // 最小・最大制限
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double brokerMaxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > MaxLotSize) lotSize = MaxLotSize;           // ユーザー設定の上限
   if(lotSize > brokerMaxLot) lotSize = brokerMaxLot;       // ブローカー上限
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| SL/TP計算                                                        |
//+------------------------------------------------------------------+
void CalculateSLTP(bool is_long, double entry_price, double &sl, double &tp)
{
   double atr = iATR(Symbol(), 0, 14, 0);  // ATR期間は14固定
   
   if(Use_ATR_SLTP)
   {
      // ATR倍率モード
      if(is_long)
      {
         sl = entry_price - atr * StopLoss_ATR_Multi;
         tp = entry_price + atr * TakeProfit_ATR_Multi;
      }
      else
      {
         sl = entry_price + atr * StopLoss_ATR_Multi;
         tp = entry_price - atr * TakeProfit_ATR_Multi;
      }
   }
   else
   {
      // 固定pointsモード（JP225用）
      // JP225では設定値がそのまま円単位（Point=0.01を掛けない）
      if(is_long)
      {
         sl = entry_price - StopLoss_Fixed_Points;
         tp = entry_price + TakeProfit_Fixed_Points;
      }
      else
      {
         sl = entry_price + StopLoss_Fixed_Points;
         tp = entry_price - TakeProfit_Fixed_Points;
      }
   }
   
   sl = NormalizeDouble(sl, Digits);
   tp = NormalizeDouble(tp, Digits);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| AI学習データログ初期化                                           |
//+------------------------------------------------------------------+
string AccountModeTagMT4()
{
   return IsDemo() ? "DEMO" : "LIVE";
}

string EffectiveTerminalIdMT4()
{
   string id = MT4_ID;
   string id_l = StringToLower(id);
   if(StringFind(id_l, "demo") >= 0)
      return id;
   if(StringFind(id_l, "live") >= 0)
      return id;
   return id + "-" + AccountModeTagMT4();
}

void InitializeAILearningLog()
{
   // フォルダ作成
   EnsureFolderPath(AI_Learning_Folder);
   
   // ファイル名生成
   string symbol_name = Symbol();
   string timeframe = GetTimeframeString();
   g_AI_Learning_LogFile = "AI_Learning_Data_" + EffectiveTerminalIdMT4() + "_" + symbol_name + "_" + timeframe + ".csv";
   
   string log_path = AI_Learning_Folder + "\\" + g_AI_Learning_LogFile;
   
   // ヘッダー書き込み（ファイルが存在しない場合）
   int file_handle = FileOpen(log_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ",");
   if(file_handle == INVALID_HANDLE)
   {
      file_handle = FileOpen(log_path, FILE_WRITE | FILE_CSV | FILE_ANSI, ",");
      if(file_handle != INVALID_HANDLE)
      {
         FileWrite(file_handle, "Timestamp", "Symbol", "Timeframe", "Direction", 
                   "EntryPrice", "PatternType", "EMA12", "EMA25", "EMA100", 
                   "ATR", "ADX", "ChannelWidth", "TickVolume", "BarRange", 
                   "Hour", "DayOfWeek", "Confidence", "Spread", "SpreadMax");
         FileClose(file_handle);
         Print("AI学習データログ初期化: ", log_path);
      }
   }
   else
   {
      FileClose(file_handle);
   }
}

//+------------------------------------------------------------------+
//| AI学習データログ出力                                             |
//+------------------------------------------------------------------+
void LogAILearningData(bool is_long, double entry_price, string pattern_type, double confidence)
{
   if(!Enable_AI_Learning_Log) return;
   
   string log_path = AI_Learning_Folder + "\\" + g_AI_Learning_LogFile;
   int file_handle = FileOpen(log_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ",");
   
   if(file_handle == INVALID_HANDLE)
   {
      Print("[ERROR] AI学習データファイルを開けません: ", log_path);
      return;
   }
   
   FileSeek(file_handle, 0, SEEK_END);
   
   // インジケーター計算
   double ema12 = iMA(Symbol(), 0, 12, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ema25 = iMA(Symbol(), 0, 25, 0, MODE_EMA, PRICE_CLOSE, 0);
   double ema100 = iMA(Symbol(), 0, 100, 0, MODE_EMA, PRICE_CLOSE, 0);
   double atr = iATR(Symbol(), 0, 14, 0);
   double adx_value = iADX(Symbol(), 0, 14, PRICE_CLOSE, MODE_MAIN, 0);
   double channel_width = ema12 - ema100;  // JP225: points
   long tick_volume = iVolume(Symbol(), 0, 1);
   double bar_range = iHigh(Symbol(), 0, 1) - iLow(Symbol(), 0, 1);  // JP225: points
   int hour = TimeHour(TimeCurrent());
   int day_of_week = DayOfWeek();
   int spread_current = (int)((Ask - Bid) / Point);
   static int spread_max_session = 0;
   if(spread_current > spread_max_session) spread_max_session = spread_current;
   
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
   string direction = is_long ? "LONG" : "SHORT";
   
   FileWrite(file_handle, 
             timestamp, 
             Symbol(), 
             GetTimeframeString(), 
             direction,
             DoubleToString(entry_price, Digits), 
             pattern_type,
             DoubleToString(ema12, Digits), 
             DoubleToString(ema25, Digits),
             DoubleToString(ema100, Digits),
             DoubleToString(atr, 2),
             DoubleToString(adx_value, 2),
             DoubleToString(channel_width, 2),
             IntegerToString(tick_volume),
             DoubleToString(bar_range, 2),
             IntegerToString(hour),
             IntegerToString(day_of_week),
             DoubleToString(confidence, 3),
             IntegerToString(spread_current),
             IntegerToString(spread_max_session));
   
   FileClose(file_handle);
   
   g_ai_pattern_count++;
   Print("AI学習データ記録 #", g_ai_pattern_count, ": ", pattern_type, " ", direction, " @ ", DoubleToString(entry_price, Digits));
}
//+------------------------------------------------------------------+
