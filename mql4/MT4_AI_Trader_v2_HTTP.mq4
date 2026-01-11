//+------------------------------------------------------------------+
//|                                      MT4_AI_Trader_v2_HTTP.mq4 |
//|                           Phase 6 HTTP API版 (DLL不要)          |
//|   推論サーバーとHTTP経由で通信 + PullbackEntry統合機能           |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "2.10"
#property strict

// AIポートフォリオマネージャー連携（口座状態CSV）
#include <AccountStatusCsv.mqh>

// Market Sentinel連携（サービス削除済み - 無効）
// #include <MarketSentinel.mqh>

// ※PullbackEntryロジックはPython推論サーバーに統合済み
// シグナル生成: Python側
// ポジション管理: EA側（このファイル）

//--- HTTP設定
input string MT4_ID = "HTTP-Bot";               // MT4識別ID
input string InpTerminalId = "HTTP-Bot";        // 論理ターミナルID（例: 10900k-mt4-fx）
input string InferenceServerURL = "http://localhost:5555";  // 推論サーバーURL
input int    ServerTimeout = 30000;                          // タイムアウト(ms)

//--- SignalManager設定
input int    MinConfirmations = 2;      // 最小確認数
input double MinConfidence = 0.60;      // 最小信頼度
input bool   UseCandlePatterns = true;  // ローソク足パターン使用
input bool   UseIndicators = true;      // テクニカル指標使用
input bool   UseChartPatterns = true;   // チャートパターン使用

//--- 基本トレード設定
input double RiskPercent = 1.0;         // リスク率(%)
input double BaseLotSize = 0.1;         // 基本ロット
input int    MaxSlippagePips = 50;       // 最大スリッページ(pips/points) ※FX=3pips, JP225=50points
input int    MaxSpreadPips = 5;         // 最大スプレッド(pips/points) ※FX=5pips, JP225=10points
input int    DefaultSLPips = 20;        // デフォルトSL(pips)
input int    DefaultTPPips = 40;        // デフォルトTP(pips)
input int    MagicNumber = 20250124;    // マジックナンバー

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

//--- Strong Trend Mode設定（PullbackEntry統合）
input bool   EnableStrongTrendMode = true;  // 強トレンドモード有効化
input double ADXThreshold = 30.0;           // ADX閾値
input double ATRSpikeMultiplier = 1.5;      // ATRスパイク倍率
input double VolumeSpikeMultiplier = 2.0;   // 出来高スパイク倍率
input int    ADXPeriod = 14;                // ADX期間
input int    ATRPeriod = 14;                // ATR期間
input double ATRThresholdPips = 7.0;        // ATR最低閾値（price units。ログは price units / MT4pt を併記）

//--- Partial Close設定（現在ロットに対する%、合計100%になるよう設定）
input bool   EnablePartialClose = true;     // 部分決済有効化
input int    PartialCloseStages = 2;        // 段階数(2=二段階, 3=三段階)
input double PartialClose1Pips = 15.0;      // 1段階目(pips/points)
input double PartialClose1Percent = 50.0;   // 1段階目決済率(%) ※二段階:50, 三段階:30
input double PartialClose2Pips = 30.0;      // 2段階目(pips/points)
input double PartialClose2Percent = 100.0;  // 2段階目決済率(%) ※二段階:100, 三段階:50
input double PartialClose3Pips = 45.0;      // 3段階目(pips/points) ※三段階時のみ
input double PartialClose3Percent = 100.0;  // 3段階目決済率(%) ※三段階:100(残り全部)
input bool   MoveToBreakEvenAfterLevel1 = true; // Level1後にSL移動(建値へ)
input bool   MoveSLAfterLevel2 = true;      // Level2後にSL移動(Level1利益位置へ) ※三段階時
//--- CSV Logging設定
input bool   EnableCsvLogging = false;      // CSVログ有効化
input string LogDirectory = "OneDriveLogs\\AI_Trader_Logs"; // ログディレクトリ
input bool   EnableDebugLog = false;        // デバッグログ有効化

//--- AI学習データ記録設定
input bool   Enable_AI_Learning_Log = true; // AI学習データ記録有効化
input string AI_Learning_Folder = "OneDriveLogs\\data\\AI_Learning"; // 学習データ保存フォルダ

//--- SL/TP設定（ポジション管理用）
input double StopLoss_Fixed_Pips = 15.0;    // 固定SL(pips)
input double TakeProfit_Fixed_Pips = 30.0;  // 固定TP(pips)
input bool   Use_ATR_SLTP = false;          // ATR倍率使用
input double StopLoss_ATR_Multi = 1.5;      // SL用ATR倍率
input double TakeProfit_ATR_Multi = 2.0;    // TP用ATR倍率

// ※プルバック検出、EMA設定、ラウンドナンバー等はPython推論サーバーで処理

//--- グローバル変数
datetime g_lastTradeTime = 0;
int g_lastTradeBar = 0;
bool g_strongTrendActive = false;

// pip値（銘柄に応じた変換用）
double g_pipValue = 0.0001;

// Partial Close状態管理
int g_partialCloseLevel[];  // 各ポジションのレベル（0-3）
int g_partialCloseTicket[]; // g_partialCloseLevel の対応チケット
int g_logFileHandle = -1;
string g_currentLogFile = "";

// AI学習データ記録用
string g_AI_Learning_LogFile = "";
int g_ai_pattern_count = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Market Sentinel初期化（サービス削除済み - 無効）
   // MS_Init();
   
   // pip値初期化（ポジション管理用）
   InitializePipValue();
   
   Print("=== MT4 AI Trader v4.0 HTTP (Lightweight) ===");
   Print("シグナル生成: Python推論サーバー");
   Print("ポジション管理: EA側");
   Print("Inference Server: ", InferenceServerURL);
   Print("Strong Trend Mode: ", EnableStrongTrendMode ? "ON" : "OFF");
   Print("Partial Close: ", EnablePartialClose ? "ON" : "OFF");
   Print("CSV Logging: ", EnableCsvLogging ? "ON" : "OFF");
   
   // Partial Close配列初期化
   if(EnablePartialClose)
   {
      ArrayResize(g_partialCloseLevel, 200);
      ArrayResize(g_partialCloseTicket, 200);
      ArrayInitialize(g_partialCloseLevel, 0);
      ArrayInitialize(g_partialCloseTicket, 0);
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
   
   // HTTP接続テスト
   if(!TestServerConnection())
   {
      Alert("推論サーバーへの接続に失敗しました: ", InferenceServerURL);
      return(INIT_FAILED);
   }
   
   Print("初期化完了");
   ExportAccountStatusWithTerminalId(InpTerminalId);
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
   static datetime last_export = 0;
   datetime now = TimeCurrent();
   if(now - last_export >= 60)
   {
      ExportAccountStatusWithTerminalId(InpTerminalId);
      last_export = now;
   }

   // Market Sentinelによる売買許可チェック（サービス削除済み - 無効）
   
   // 新しいバーでのみ実行
   if(Bars <= g_lastTradeBar)
      return;
   
   g_lastTradeBar = Bars;
   
   // Partial Close チェック
   if(EnablePartialClose)
   {
      CheckPartialClose();
   }
   
   // メインロジック
   AnalyzeAndTrade();
}

//+------------------------------------------------------------------+
//| メイン分析・トレードロジック                                      |
//+------------------------------------------------------------------+
void AnalyzeAndTrade()
{
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
   
   // スプレッドチェック
   double spread_pips = (Ask - Bid) / g_pipValue;
   if(spread_pips > MaxSpreadPips)
   {
      Print("スプレッドが広すぎます: ", DoubleToString(spread_pips, 1), " pips/points");
      return;
   }
   
   // Strong Trend Mode判定
   bool isStrongTrend = false;
   if(EnableStrongTrendMode)
   {
      isStrongTrend = ShouldActivateStrongTrendMode();
      if(isStrongTrend != g_strongTrendActive)
      {
         g_strongTrendActive = isStrongTrend;
         if(isStrongTrend)
            Print("★ Strong Trend Mode ACTIVATED");
         else
            Print("Strong Trend Mode deactivated");
      }
   }
   
   // OHLCV データ準備 (100本)
   int bars = 100;
   string jsonData = PrepareOHLCVJson(bars);
   
   // HTTP POSTリクエスト送信
   string responseStr = "";
   if(!SendHttpRequest(InferenceServerURL + "/analyze", jsonData, responseStr))
   {
      Print("推論サーバーとの通信に失敗しました");
      return;
   }
   
   // レスポンス解析
   int signal = 0;
   double confidence = 0.0;
   bool entryAllowed = false;
   
   if(!ParseAnalyzeResponse(responseStr, signal, confidence, entryAllowed))
   {
      Print("レスポンスの解析に失敗しました");
      return;
   }
   
   // Strong Trend Modeで信頼度ブースト
   if(isStrongTrend && entryAllowed)
   {
      double originalConf = confidence;
      confidence = MathMin(0.95, confidence + 0.10);  // +10%ブースト
      Print("Strong Trend Boost: ", DoubleToString(originalConf, 3), " → ", DoubleToString(confidence, 3));
   }
   
   // エントリー判定
   if(!entryAllowed || signal == 0)
   {
      if(EnableCsvLogging)
         LogTradeEvent("SKIP", 0, 0, signal, confidence, "Entry not allowed or no clear signal");
      return;
   }
   
   if(confidence < MinConfidenceForEntry)
   {
      if(EnableCsvLogging)
         LogTradeEvent("SKIP", 0, 0, signal, confidence, "Confidence too low");
      return;
   }
   
   // ATR閾値チェック
   double atr_current = iATR(Symbol(), 0, ATRPeriod, 0);
   double atr_pips = atr_current / g_pipValue;
   double atr_mt4pt = (Point > 0.0) ? (atr_current / Point) : 0.0;
   double thr_price = ATRThresholdPips * g_pipValue;
   double thr_mt4pt = (Point > 0.0) ? (thr_price / Point) : 0.0;
   string unit_name = "pips/points";
   
   if(atr_pips < ATRThresholdPips)
   {
      Print(StringFormat("ATR不足: %s (price units) / %s MT4pt (%s %s) < %s (price units) / %s MT4pt (%s %s) (エントリー見送り)",
                         DoubleToString(atr_current, Digits),
                         DoubleToString(atr_mt4pt, 0),
                         DoubleToString(atr_pips, 1),
                         unit_name,
                         DoubleToString(thr_price, Digits),
                         DoubleToString(thr_mt4pt, 0),
                         DoubleToString(ATRThresholdPips, 1),
                         unit_name));
      if(EnableCsvLogging)
         LogTradeEvent("SKIP", 0, 0, signal, confidence, "ATR too low: " + DoubleToString(atr_pips, 1));
      return;
   }
   
   // エントリー実行
   ExecuteTrade(signal, confidence);
}

//+------------------------------------------------------------------+
//| トレード実行                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal, double confidence)
{
   bool is_long = (signal == 1);
   double entry_price = is_long ? Ask : Bid;
   
   double lotSize = CalculateLotSize();
   
   // Market Sentinelによるロットサイズ調整（サービス削除済み - 無効）
   
   // SL/TP計算
   double sl = 0, tp = 0;
   CalculateSLTP(is_long, entry_price, sl, tp);
   
   int ticket = 0;
   int slippage = (int)(MaxSlippagePips * g_pipValue / Point);
   
   if(is_long)  // BUY
   {
      ticket = OrderSend(Symbol(), OP_BUY, lotSize, Ask, slippage, 
                         NormalizeDouble(sl, Digits), 
                         NormalizeDouble(tp, Digits), 
                         "AI_BUY_" + DoubleToString(confidence, 2), 
                         MagicNumber, 0, clrBlue);
      
      if(ticket > 0)
      {
         Print("★ BUY注文成功: Ticket=", ticket, " Conf=", DoubleToString(confidence, 3),
               " SL=", DoubleToString(sl, Digits), " TP=", DoubleToString(tp, Digits));
         g_lastTradeTime = TimeCurrent();
         g_lastTradeBar = Bars;
         
         if(EnablePartialClose)
         {
            int slot = GetPartialCloseIndex(ticket);
            if(slot >= 0)
               g_partialCloseLevel[slot] = 0;
         }
         
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
                         MagicNumber, 0, clrRed);
      
      if(ticket > 0)
      {
         Print("★ SELL注文成功: Ticket=", ticket, " Conf=", DoubleToString(confidence, 3),
               " SL=", DoubleToString(sl, Digits), " TP=", DoubleToString(tp, Digits));
         g_lastTradeTime = TimeCurrent();
         g_lastTradeBar = Bars;
         
         if(EnablePartialClose)
         {
            int slot = GetPartialCloseIndex(ticket);
            if(slot >= 0)
               g_partialCloseLevel[slot] = 0;
         }
         
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
//| Partial Close状態スロット取得（ticketベース）                    |
//+------------------------------------------------------------------+
int GetPartialCloseIndex(int ticket)
{
   if(ticket <= 0)
      return -1;

   int n = ArraySize(g_partialCloseTicket);
   if(n <= 0)
      return -1;

   for(int i = 0; i < n; i++)
   {
      if(g_partialCloseTicket[i] == ticket)
         return i;
   }

   for(int j = 0; j < n; j++)
   {
      if(g_partialCloseTicket[j] == 0)
      {
         g_partialCloseTicket[j] = ticket;
         g_partialCloseLevel[j] = 0;
         return j;
      }
   }

   g_partialCloseTicket[0] = ticket;
   g_partialCloseLevel[0] = 0;
   return 0;
}

//+------------------------------------------------------------------+
//| OHLCV データをJSON形式で準備                                     |
//+------------------------------------------------------------------+
string PrepareOHLCVJson(int bars)
{
   string json = "{";
   json += "\"ohlcv\":{";
   
   // Open
   json += "\"open\":[";
   for(int i=bars-1; i>=0; i--)
   {
      json += DoubleToString(Open[i], Digits);
      if(i > 0) json += ",";
   }
   json += "],";
   
   // High
   json += "\"high\":[";
   for(int i=bars-1; i>=0; i--)
   {
      json += DoubleToString(High[i], Digits);
      if(i > 0) json += ",";
   }
   json += "],";
   
   // Low
   json += "\"low\":[";
   for(int i=bars-1; i>=0; i--)
   {
      json += DoubleToString(Low[i], Digits);
      if(i > 0) json += ",";
   }
   json += "],";
   
   // Close
   json += "\"close\":[";
   for(int i=bars-1; i>=0; i--)
   {
      json += DoubleToString(Close[i], Digits);
      if(i > 0) json += ",";
   }
   json += "],";
   
   // Volume
   json += "\"volume\":[";
   for(int i=bars-1; i>=0; i--)
   {
      json += DoubleToString(Volume[i], 0);
      if(i > 0) json += ",";
   }
   json += "]";
   
   json += "},";
   json += "\"current_price\":" + DoubleToString(Close[0], Digits) + ",";
   json += "\"current_time\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\"";
   json += "}";
   
   return json;
}

//+------------------------------------------------------------------+
//| HTTP POSTリクエスト送信                                          |
//+------------------------------------------------------------------+
bool SendHttpRequest(string url, string postData, string &response)
{
   char post[];
   char result[];
   string headers = "Content-Type: application/json\r\n";
   
   StringToCharArray(postData, post, 0, StringLen(postData));
   
   int res = WebRequest(
      "POST",
      url,
      headers,
      ServerTimeout,
      post,
      result,
      headers
   );
   
   if(res == -1)
   {
      Print("WebRequest Error: ", GetLastError());
      Print("URLを'ツール > オプション > エキスパートアドバイザー > WebRequestを許可するURLリスト'に追加してください");
      return false;
   }
   
   response = CharArrayToString(result, 0, ArraySize(result));
   return true;
}

//+------------------------------------------------------------------+
//| サーバー接続テスト                                               |
//+------------------------------------------------------------------+
bool TestServerConnection()
{
   string response = "";
   if(!SendHttpRequest(InferenceServerURL + "/health", "{}", response))
   {
      return false;
   }
   
   // レスポンスに"ok"が含まれるか確認
   if(StringFind(response, "ok") >= 0)
   {
      Print("✓ 推論サーバー接続OK");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 分析レスポンス解析                                               |
//+------------------------------------------------------------------+
bool ParseAnalyzeResponse(string response, int &signal, double &confidence, bool &entryAllowed)
{
   // 簡易JSONパーサー（本番では専用ライブラリ推奨）
   int signalPos = StringFind(response, "\"signal\":");
   int confPos = StringFind(response, "\"confidence\":");
   int entryPos = StringFind(response, "\"entry_allowed\":");
   
   if(signalPos < 0 || confPos < 0 || entryPos < 0)
      return false;
   
   // signal抽出
   string signalStr = StringSubstr(response, signalPos + 9, 2);
   signalStr = StringTrimLeft(signalStr);
   signalStr = StringTrimRight(signalStr);
   signal = (int)StringToInteger(signalStr);
   
   // confidence抽出
   string confStr = StringSubstr(response, confPos + 14, 10);
   int commaPos = StringFind(confStr, ",");
   if(commaPos > 0)
      confStr = StringSubstr(confStr, 0, commaPos);
   confidence = StringToDouble(confStr);
   
   // entry_allowed抽出
   string entryStr = StringSubstr(response, entryPos + 17, 5);
   entryAllowed = (StringFind(entryStr, "true") >= 0);
   
   return true;
}

//+------------------------------------------------------------------+
//| Partial Close チェック（PullbackEntry統合）                      |
//+------------------------------------------------------------------+
void CheckPartialClose()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      
      if(OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol())
         continue;
      
      int ticket = OrderTicket();
      int slot = GetPartialCloseIndex(ticket);
      if(slot < 0)
         continue;
      int currentLevel = g_partialCloseLevel[slot];
      
      // 最大レベル判定（二段階 or 三段階）
      int maxLevel = (PartialCloseStages >= 3) ? 3 : 2;
      
      if(currentLevel >= maxLevel)
         continue;  // 全レベル完了
      
      double openPrice = OrderOpenPrice();
      double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
      double profitPips = 0;
      
      // g_pipValueを使用して銘柄に応じたpips計算
      if(OrderType() == OP_BUY)
         profitPips = (currentPrice - openPrice) / g_pipValue;
      else
         profitPips = (openPrice - currentPrice) / g_pipValue;
      
      // レベル判定
      double targetPips = 0;
      double closePercent = 0;
      int newLevel = currentLevel;
      
      if(currentLevel == 0 && profitPips >= PartialClose1Pips)
      {
         targetPips = PartialClose1Pips;
         closePercent = PartialClose1Percent;  // 二段階: 50%, 三段階: 30%
         newLevel = 1;
      }
      else if(currentLevel == 1 && profitPips >= PartialClose2Pips)
      {
         targetPips = PartialClose2Pips;
         // 二段階モード: 残り全部決済（元の50%）
         // 三段階モード: 現在ロットの一部を決済
         if(maxLevel == 2)
            closePercent = 100.0;  // 残りポジション全決済 = 元の50%
         else
            closePercent = PartialClose2Percent;
         newLevel = 2;
      }
      else if(maxLevel >= 3 && currentLevel == 2 && profitPips >= PartialClose3Pips)
      {
         // 三段階モードのみ
         targetPips = PartialClose3Pips;
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
      
      // スリッページをパラメータから計算
      int slippage = (int)(MaxSlippagePips * g_pipValue / Point);
      
      bool closeResult = false;
      if(OrderType() == OP_BUY)
         closeResult = OrderClose(ticket, lotsToClose, Bid, slippage, clrGreen);
      else
         closeResult = OrderClose(ticket, lotsToClose, Ask, slippage, clrOrange);
      
      // 銘柄タイプに応じた単位表示
      string unit = (iClose(NULL, 0, 0) >= 1000) ? "points" : "pips";
      
      if(closeResult)
      {
         Print("★ Partial Close Level ", newLevel, ": Ticket=", ticket, 
               " Lots=", DoubleToString(lotsToClose, 2), 
               " Profit=", DoubleToString(profitPips, 1), " ", unit);
         
         g_partialCloseLevel[slot] = newLevel;
         
         if(EnableCsvLogging)
            LogTradeEvent("PARTIAL_CLOSE", ticket, OrderType(), newLevel, profitPips, 
                          "Level " + IntegerToString(newLevel) + " closed");
         
         // 部分決済後のSL移動などは「同一ticket」にのみ適用（別ポジション誤適用を防ぐ）
         Sleep(100);
         if(OrderSelect(ticket, SELECT_BY_TICKET))
         {
            if(newLevel == 1 && MoveToBreakEvenAfterLevel1)
            {
               double newSL = NormalizeDouble(openPrice, Digits);
               double currentSL = OrderStopLoss();

               bool shouldModify = false;
               if(orderType == OP_BUY && (currentSL == 0 || currentSL < openPrice))
                  shouldModify = true;
               else if(orderType == OP_SELL && (currentSL == 0 || currentSL > openPrice))
                  shouldModify = true;

               if(shouldModify)
               {
                  if(OrderModify(ticket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrYellow))
                     Print(">>> SLを建値へ移動: ", DoubleToString(newSL, Digits), " (ticket=", ticket, ")");
                  else
                     Print("!!! SL移動失敗: Error=", GetLastError());
               }
            }

            if(newLevel == 2 && maxLevel >= 3 && MoveSLAfterLevel2)
            {
               double level1Price;
               if(orderType == OP_BUY)
                  level1Price = openPrice + PartialClose1Pips * g_pipValue;
               else
                  level1Price = openPrice - PartialClose1Pips * g_pipValue;

               level1Price = NormalizeDouble(level1Price, Digits);

               if(OrderModify(ticket, OrderOpenPrice(), level1Price, OrderTakeProfit(), 0, clrAqua))
                  Print(">>> SLをLevel1利益位置へ移動: ", DoubleToString(level1Price, Digits), " (ticket=", ticket, ")");
               else
                  Print("!!! SL移動失敗: Error=", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Strong Trend Mode判定（PullbackEntry統合）                       |
//+------------------------------------------------------------------+
bool ShouldActivateStrongTrendMode()
{
   // 1. ADX判定
   double adx = iADX(Symbol(), 0, ADXPeriod, PRICE_CLOSE, MODE_MAIN, 0);
   bool adxCondition = (adx >= ADXThreshold);
   
   // 2. ATRスパイク判定
   double atr_current = iATR(Symbol(), 0, ATRPeriod, 0);
   double atr_prev = iATR(Symbol(), 0, ATRPeriod, 1);
   double atr_avg = 0;
   for(int i=2; i<22; i++)
      atr_avg += iATR(Symbol(), 0, ATRPeriod, i);
   atr_avg /= 20.0;
   
   bool atrSpike = (atr_current >= atr_avg * ATRSpikeMultiplier);
   
   // 3. 出来高スパイク判定
   double vol_current = (double)Volume[0];
   double vol_avg = 0;
   for(int i=1; i<21; i++)
      vol_avg += (double)Volume[i];
   vol_avg /= 20.0;
   
   bool volumeSpike = (vol_current >= vol_avg * VolumeSpikeMultiplier);
   
   // いずれか1つでも満たせばOK
   return (adxCondition || atrSpike || volumeSpike);
}

//+------------------------------------------------------------------+
//| CSV ログ初期化（PullbackEntry統合）                              |
//+------------------------------------------------------------------+
void InitializeCsvLog()
{
   // ログフォルダ作成
   string logFolder = LogDirectory + "\\" + Symbol() + "_" + GetTimeframeString();
   CreateLogDirectory(logFolder);
   
   // ログファイル名
   g_currentLogFile = logFolder + "\\" + MT4_ID + "_" + Symbol() + "_" + 
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
                "Signal", "Confidence", "Level", "Pips", "Reason");
   }
   
   Print("CSV Log initialized: ", g_currentLogFile);
}

//+------------------------------------------------------------------+
//| ログディレクトリ作成                                             |
//+------------------------------------------------------------------+
void CreateLogDirectory(string path)
{
   // MQL4ではFolderCreate不可のため、ダミーファイル作成で代用
   string dummyFile = path + "\\dummy.txt";
   int handle = FileOpen(dummyFile, FILE_WRITE|FILE_TXT);
   if(handle != -1)
   {
      FileWrite(handle, "Log directory");
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| トレードイベントログ記録                                         |
//+------------------------------------------------------------------+
void LogTradeEvent(string eventType, int ticket, int orderType, 
                   int signalOrLevel, double confidenceOrPips, string reason)
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
             DoubleToString(confidenceOrPips, 3),
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
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol())
            count++;
      }
   }
   return count;
}

double CalculateLotSize()
{
   double balance = AccountBalance();
   double riskAmount = balance * RiskPercent / 100.0;
   double stopLossPips = DefaultSLPips;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   
   double lotSize = riskAmount / (stopLossPips * tickValue);
   lotSize = NormalizeDouble(lotSize, 2);
   
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| pip値初期化（銘柄に応じた変換用）                                |
//+------------------------------------------------------------------+
void InitializePipValue()
{
   double current_price = iClose(NULL, 0, 0);
   
   // 指数系（JP225, DAX等）: 価格が1000以上
   if(current_price >= 1000)
   {
      g_pipValue = 1.0;  // 1 point = 1円/ポイント
   }
   // FX通貨ペア: Digits 3/5桁
   else if(Digits == 3 || Digits == 5)
   {
      g_pipValue = Point * 10;  // 1 pip = 0.0001 or 0.001
   }
   // その他（2桁FX等）
   else
   {
      g_pipValue = Point;
   }
   
   Print("pip値初期化: g_pipValue=", DoubleToString(g_pipValue, 5), " (", Symbol(), ")");
}

//+------------------------------------------------------------------+
//| SL/TP計算                                                        |
//+------------------------------------------------------------------+
void CalculateSLTP(bool is_long, double entry_price, double &sl, double &tp)
{
   double atr = iATR(Symbol(), 0, ATRPeriod, 0);
   
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
      // 固定pipsモード
      if(is_long)
      {
         sl = entry_price - StopLoss_Fixed_Pips * g_pipValue;
         tp = entry_price + TakeProfit_Fixed_Pips * g_pipValue;
      }
      else
      {
         sl = entry_price + StopLoss_Fixed_Pips * g_pipValue;
         tp = entry_price - TakeProfit_Fixed_Pips * g_pipValue;
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
   CreateLogDirectory(AI_Learning_Folder);
   
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
   double channel_width = (ema12 - ema100) / g_pipValue;
   long tick_volume = iVolume(Symbol(), 0, 1);
   double bar_range = (iHigh(Symbol(), 0, 1) - iLow(Symbol(), 0, 1)) / g_pipValue;
   int hour = TimeHour(TimeCurrent());
   int day_of_week = DayOfWeek();
   int spread_current = (int)MarketInfo(Symbol(), MODE_SPREAD);
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
             DoubleToString(atr / g_pipValue, 2),
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
