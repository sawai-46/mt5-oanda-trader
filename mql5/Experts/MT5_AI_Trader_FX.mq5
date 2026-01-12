//+------------------------------------------------------------------+
//|                                          MT5_AI_Trader_FX.mq5    |
//|              Phase 6 HTTP API版 (MQL5 OANDA対応) - FX専用          |
//|   推論サーバーとHTTP経由で通信 + 16モジュールAI統合               |
//|   単位: pips (1pip = 10points for 5-digit brokers)               |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "2.17"
#property strict

#include <Trade\Trade.mqh>
#include <Integration/Logger.mqh>
#include <Integration/AccountStatusCsv.mqh>
#include <Utils/JsonLite.mqh>

//--- 推論サーバー戦略プリセット
enum PresetOption
{
   PRESET_antigravity_pullback = 0,   // antigravity_pullback (推奨)
   PRESET_antigravity_only,           // antigravity_only
   PRESET_antigravity_hedge,          // antigravity_hedge
   PRESET_quantitative_pure,          // quantitative_pure
   PRESET_full,                       // full (全モジュール)
   PRESET_custom                      // custom (カスタム)
};

//--- HTTP設定
input string InpMT5_ID = "10900k-mt5-fx";              // MT5識別ID（10900k-mt5-fx, 10900k-mt5-index, matsu-mt5-fx, matsu-mt5-index）
input string InpTerminalId = "";                       // 口座状態CSV用の端末固定ID（空なら InpMT5_ID を使用。例: 10900k-mt5-fx）
input bool   InpAutoAppendSymbol = true;              // MT5_IDにSymbolを自動追加
input string InpInferenceServerURL = "http://127.0.0.1:5001";  // 推論サーバーURL
input int    InpServerTimeout = 30000;                          // タイムアウト(ms)

string GetAccountStatusTerminalId()
{
   if(StringLen(InpTerminalId) > 0)
      return InpTerminalId;
   return InpMT5_ID;
}

//--- プリセット設定
input PresetOption InpPreset = PRESET_antigravity_pullback;  // 戦略プリセット
input string InpCustomPresetName = "";                        // カスタムプリセット名

//--- 基本トレード設定
input double InpRiskPercent = 1.0;         // リスク率(%)
input double InpBaseLotSize = 0.10;        // 基本ロット
input double InpMaxLotSize = 1.0;          // 最大ロット（上限）
input bool   InpEnableLotAdjustment = true; // ロット自動調整有効化
input double InpMaxSlippagePips = 5.0;     // 最大スリッページ(pips) ※M15推奨: 3-5pips
input int    InpMaxSpreadPips = 20;        // 最大スプレッド(pips)
input double InpStopLossPips = 15.0;       // SL(pips)
input double InpTakeProfitPips = 30.0;     // TP(pips)
input bool   InpAutoMagicNumber = true;    // マジックナンバー自動生成
input ulong  InpMagicNumber = 20251224;    // マジックナンバー（自動生成時は無視）

//--- 時間フィルター設定
input bool   InpEnable_Time_Filter = true;         // 時間フィルター有効化
input int    InpGMT_Offset = 3;                    // GMTオフセット
input bool   InpUse_DST = false;                   // 夏時間適用（+1時間）
input int    InpCustom_Start_Hour = 8;             // 稼働開始時(JST)
input int    InpCustom_Start_Minute = 0;           // 稼働開始分
input int    InpCustom_End_Hour = 21;              // 稼働終了時(JST)
input int    InpCustom_End_Minute = 0;             // 稼働終了分
input bool   InpTradeOnFriday = true;              // 金曜取引許可

//--- フィルター設定
input int    InpMaxPositions = 2;          // 最大ポジション数
input int    InpMinBarsSinceLastTrade = 10; // 最小バー間隔
input double InpMinConfidence = 0.65;      // 最小信頼度
input bool   InpShowDebugLog = false;      // デバッグログを出力する

//--- ATR設定
input int    InpATRPeriod = 14;            // ATR期間
input double InpATRThresholdPips = 3.0;    // ATR最低閾値(pips。ログは price units / MT5pt を併記)

//--- Partial Close設定
input bool   InpEnablePartialClose = true;     // 部分決済有効化
input int    InpPartialCloseStages = 2;        // 段階数(2=二段階, 3=三段階)
input double InpPartialClose1Pips = 15.0;      // 1段階目(pips)
input double InpPartialClose1Percent = 50.0;   // 1段階目決済率(%)
input double InpPartialClose2Pips = 30.0;      // 2段階目(pips)
input double InpPartialClose2Percent = 50.0;   // 2段階目決済率(%)
input double InpPartialClose3Pips = 45.0;      // 3段階目(pips)
input double InpPartialClose3Percent = 100.0;  // 3段階目決済率(%)
input bool   InpMoveToBreakEvenAfterLevel1 = true; // Level1後にSL移動(建値へ)
input bool   InpMoveSLAfterLevel2 = true;      // Level2後にSL移動(Level1利益位置へ)

//--- Partial Close 永続化（再起動/再アタッチ耐性）
input bool   InpEnablePersistentTpState = true;      // 部分決済レベルを端末GVへ保存/復元
input bool   InpLogPersistentTpStateEvents = false;  // 保存/復元/削除イベントをログ出力

//--- SL/TP設定
input bool   InpUse_ATR_SLTP = false;          // ATR倍率使用
input double InpStopLoss_ATR_Multi = 1.5;      // SL用ATR倍率
input double InpTakeProfit_ATR_Multi = 2.0;    // TP用ATR倍率

//--- AI学習データ記録設定
input bool   InpEnable_AI_Learning_Log = true; // AI学習データ記録有効化

//--- Logging (optional)
input bool   InpEnableLogging = true;                // ログ出力有効化
input ENUM_LOG_LEVEL InpLogMinLevel = LOG_INFO;      // 最小ログレベル
input bool   InpLogToFile = true;                   // ファイルへのログ出力
input bool   InpLogUseCommonFolder = false;           // Commonフォルダ使用（OneDriveLogs配下に出したい場合はfalse推奨）
input string InpLogFileName = "OneDriveLogs\\logs\\MT5_AI_Trader.log";   // ログファイル名（MQL5/Files配下）
input int    InpSkipLogCooldown = 60;                 // 同一スキップログの抑制秒数
input int    InpMainLogicIntervalSec = 60;            // メインロジック実行間隔(秒)

//--- グローバル変数
datetime g_lastBarTime = 0;
int g_lastTradeBar = 100;  // 初回起動時に即座にリクエスト送信可能にするため大きな値で初期化
ulong g_ActiveMagicNumber = 0;
int g_partialCloseLevel[];
string g_uniqueId = "";
string g_inferenceServerUrl = "";
CTrade m_trade;

// Partial Close永続化: クールダウン管理
datetime g_lastPersistCleanup = 0;

// Pips→Points変換値（OnInitで計算）
double g_pipMultiplier = 10.0;  // 5桁ブローカー: 1pip = 10points
double g_MaxSpreadPoints = 0;
double g_StopLossPoints = 0;
double g_TakeProfitPoints = 0;
double g_ATRThresholdPoints = 0;
double g_PartialClose1Points = 0;
double g_PartialClose2Points = 0;
double g_PartialClose3Points = 0;

string BoolStr(const bool v)
{
   return v ? "true" : "false";
}

string AccountModeTag()
{
   const long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(mode == ACCOUNT_TRADE_MODE_REAL)
      return "LIVE";
   if(mode == ACCOUNT_TRADE_MODE_DEMO)
      return "DEMO";
   if(mode == ACCOUNT_TRADE_MODE_CONTEST)
      return "CONTEST";
   return "UNKNOWN";
}

void DumpEffectiveConfig_AI_HTTP()
{
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][AI_FX] Magic=%lld ID=%s URL=%s", g_ActiveMagicNumber, InpMT5_ID, g_inferenceServerUrl));
}

void LogSkipReason(string reason)
{
   static datetime last_skip_log_time = 0;
   static string last_skip_reason = "";
   if (InpSkipLogCooldown > 0) {
      if (last_skip_reason == reason && TimeCurrent() - last_skip_log_time < InpSkipLogCooldown) return;
   }
   last_skip_reason = reason;
   last_skip_log_time = TimeCurrent();
   CLogger::Log(LOG_INFO, ">>> スキップ: " + reason);
}

//+------------------------------------------------------------------+
//| プリセット名取得                                                  |
//+------------------------------------------------------------------+
string GetPresetName()
{
   switch(InpPreset)
   {
      case PRESET_antigravity_only:   return "antigravity_only";
      case PRESET_antigravity_hedge:  return "antigravity_hedge";
      case PRESET_quantitative_pure:  return "quantitative_pure";
      case PRESET_full:               return "full";
      case PRESET_custom:
      {
         string name = InpCustomPresetName;
         StringTrimLeft(name);
         StringTrimRight(name);
         if(StringLen(name) > 0)
            return name;
         return "antigravity_pullback";
      }
      case PRESET_antigravity_pullback:
      default: return "antigravity_pullback";
   }
}

//+------------------------------------------------------------------+
//| マジックナンバー生成（簡易版）                                    |
//+------------------------------------------------------------------+
ulong GenerateMagicNumber()
{
   // Symbol + Timeframe からハッシュ生成
   string key = _Symbol + "_" + PeriodToString((ENUM_TIMEFRAMES)_Period);
   ulong hash = 0;
   for(int i = 0; i < StringLen(key); i++)
   {
      hash = hash * 31 + StringGetCharacter(key, i);
   }
   // OANDA MT5 用プレフィックス (50) + ハッシュ
   return 50000000 + (hash % 1000000);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_inferenceServerUrl = InpInferenceServerURL;

   // Pips→Points変換（5桁ブローカー: 1pip = 10points）
   // JPY pairs: 3 digits = 1pip = 1point, non-JPY 5 digits = 1pip = 10points
   if(_Digits == 3 || _Digits == 5)
      g_pipMultiplier = 10.0;
   else if(_Digits == 2 || _Digits == 4)
      g_pipMultiplier = 1.0;
   else
      g_pipMultiplier = 10.0;  // デフォルト
   
   g_MaxSpreadPoints = InpMaxSpreadPips * g_pipMultiplier;
   g_StopLossPoints = InpStopLossPips * g_pipMultiplier;
   g_TakeProfitPoints = InpTakeProfitPips * g_pipMultiplier;
   g_ATRThresholdPoints = InpATRThresholdPips * g_pipMultiplier;
   g_PartialClose1Points = InpPartialClose1Pips * g_pipMultiplier;
   g_PartialClose2Points = InpPartialClose2Pips * g_pipMultiplier;
   g_PartialClose3Points = InpPartialClose3Pips * g_pipMultiplier;
   
   Print("★ Pips→Points変換: multiplier=", g_pipMultiplier, 
         " SL=", InpStopLossPips, "pips→", g_StopLossPoints, "pts",
         " TP=", InpTakeProfitPips, "pips→", g_TakeProfitPoints, "pts");

   // マジックナンバー初期化
   if(InpAutoMagicNumber)
   {
      g_ActiveMagicNumber = GenerateMagicNumber();
      Print("マジックナンバー自動生成: ", g_ActiveMagicNumber);
   }
   else
   {
      g_ActiveMagicNumber = InpMagicNumber;
      Print("マジックナンバー手動設定: ", g_ActiveMagicNumber);
   }
   
   // Trade設定
   m_trade.SetExpertMagicNumber(g_ActiveMagicNumber);
   m_trade.SetDeviationInPoints((int)(InpMaxSlippagePips * g_pipMultiplier));
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Logger instanceId finalized after magic is set
   {
      string instanceId = MQLInfoString(MQL_PROGRAM_NAME) + "|" + _Symbol + "|Acct:" + AccountModeTag() + "|Magic:" + (string)g_ActiveMagicNumber + "|CID:" + (string)ChartID();
      ENUM_LOG_LEVEL minLevel = InpLogMinLevel;
      if(InpShowDebugLog) minLevel = LOG_DEBUG;
      CLogger::Configure(instanceId, InpEnableLogging, minLevel, InpLogToFile, InpLogFileName, InpLogUseCommonFolder);
   }
   
   // ユニークID生成
   g_uniqueId = InpMT5_ID;
   if(InpAutoAppendSymbol || StringLen(InpMT5_ID) == 0)
   {
      string tfStr = PeriodToString((ENUM_TIMEFRAMES)_Period);
      if(StringLen(InpMT5_ID) == 0)
         g_uniqueId = _Symbol + "_" + tfStr;
      else
         g_uniqueId = InpMT5_ID + "_" + _Symbol + "_" + tfStr;
   }
   
   CLogger::Log(LOG_INFO, "MT5 AI Trader v2.13 (OANDA)");

   DumpEffectiveConfig_AI_HTTP();
   
   // Partial Close配列初期化
   if(InpEnablePartialClose)
   {
      ArrayResize(g_partialCloseLevel, 1000);
      ArrayInitialize(g_partialCloseLevel, 0);
   }
   
   // HTTP接続テスト
   if(!TestServerConnection())
   {
      Alert("推論サーバーへの接続に失敗しました: ", g_inferenceServerUrl);
      Print("URLを'ツール > オプション > エキスパートアドバイザ > WebRequestを許可するURLリスト'に追加してください");
      return(INIT_FAILED);
   }
   
   CLogger::Log(LOG_INFO, "初期化完了");
   ExportAccountStatusWithTerminalId(GetAccountStatusTerminalId());
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CLogger::Log(LOG_INFO, "EA終了 - 理由: " + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   static datetime last_export = 0;
   datetime now_export = TimeCurrent();
   if(now_export - last_export >= 60)
   {
      ExportAccountStatusWithTerminalId(GetAccountStatusTerminalId());
      last_export = now_export;
   }

   // 1. ポジション監視（利確・SL移動）は常に実行
   if(InpEnablePartialClose)
   {
      if(InpEnablePersistentTpState)
         CleanupPersistIfFlat();
      CheckPartialClose();
   }

   // New Bar検出と間隔カウント
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(current_bar_time != last_bar_time)
   {
      if(last_bar_time != 0) g_lastTradeBar++;
      last_bar_time = current_bar_time;
   }

   // 2. メインロジック（分析・エントリー）はタイマー制御
   static datetime last_logic_exec = 0;
   datetime now = TimeCurrent();
   if(now - last_logic_exec < InpMainLogicIntervalSec)
      return;
      
   last_logic_exec = now;
   AnalyzeAndTrade();
}

void AnalyzeAndTrade()
{
   // デバッグログ用のタイマー
   static datetime lastDebugTime = 0;
   datetime now = TimeCurrent();
   bool showStatus = InpShowDebugLog && (now - lastDebugTime >= 60);
   
   if(showStatus)
   {
      CLogger::Log(LOG_DEBUG, "AnalyzeAndTrade 開始 - フィルタチェック中...");
      lastDebugTime = now;
   }
   
   // フィルターチェック
   if(!PassesTimeFilter())
   {
      if(InpShowDebugLog && showStatus) CLogger::Log(LOG_DEBUG, "スキップ: 稼働時間外");
      return;
   }
   
   int openPos = CountOpenPositions();
   if(openPos >= InpMaxPositions)
   {
      if(InpShowDebugLog && showStatus) CLogger::Log(LOG_DEBUG, StringFormat("スキップ: 最大ポジション数に到達 (%d)", openPos));
      return;
   }
   
   if(g_lastTradeBar < InpMinBarsSinceLastTrade)
   {
      if(showStatus) LogSkipReason(StringFormat("前回のトレードから間隔不足 (%d bars)", g_lastTradeBar));
      return;
   }
   
   // スプレッドチェック
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > g_MaxSpreadPoints)
   {
      LogSkipReason(StringFormat("スプレッド過大: %.1f pts (上限: %.1f)", spread, g_MaxSpreadPoints));
      return;
   }
   
   // シンボル名のクリーンアップ（OANDA等のアンダースコア対応はサーバー側で行うが、EA側でもログ出力を整える）
   string currentSymbol = _Symbol;
   
   // OHLCV データ準備 (100本)
   string jsonData = PrepareOHLCVJson(100);
   if(StringLen(jsonData) == 0)
   {
      Print("OHLCVデータの準備に失敗");
      return;
   }
   
   if(InpShowDebugLog && showStatus) CLogger::Log(LOG_DEBUG, StringFormat("推論リクエスト送信中... Sym:%s", currentSymbol));

   // HTTP POSTリクエスト送信
   string responseStr = "";
   if(!SendHttpRequest(g_inferenceServerUrl + "/analyze", jsonData, responseStr))
   {
      // SendHttpRequest内でもログは出るが、ここで上位の文脈を追加
      Print("推論サーバーとの通信に失敗しました (", g_inferenceServerUrl, ")");
      return;
   }
   
   // レスポンス解析
   int signal = 0;
   double confidence = 0.0;
   bool entryAllowed = false;
   string reason = "";
   
   if(!ParseAnalyzeResponse(responseStr, signal, confidence, entryAllowed, reason))
   {
      Print("レスポンスの解析に失敗しました: ", StringSubstr(responseStr, 0, 200));
      return;
   }
   
   // レスポンス出力
   if(InpShowDebugLog || signal != 0)
   {
      CLogger::Log(LOG_DEBUG, StringFormat("Response: sig=%d conf=%s reason=%s", signal, DoubleToString(confidence, 3), reason));
   }
   
   // エントリー判定
   if(!entryAllowed || signal == 0)
   {
      // No signal
      return;
   }
   
   if(confidence < InpMinConfidence)
   {
      if(InpShowDebugLog) CLogger::Log(LOG_DEBUG, StringFormat("信頼度不足でスキップ: %s < %s", DoubleToString(confidence, 3), DoubleToString(InpMinConfidence, 2)));
      return;
   }
   
   // ATR閾値チェック
   double atr = GetATR(InpATRPeriod);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double atr_points = atr / point;
   
   if(atr_points < g_ATRThresholdPoints)
   {
      LogSkipReason(StringFormat("ATR不足: %.1f pts < %.1f pts", atr_points, g_ATRThresholdPoints));
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
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry_price = is_long ? ask : bid;
   
   double sl, tp;
   CalculateSLTP(is_long, entry_price, sl, tp);
   
   double lotSize = CalculateLotSize();
   string comment = "AI_" + (is_long ? "BUY" : "SELL") + "_" + DoubleToString(confidence, 2) + "_" + GetPresetName();
   
   bool result = false;
   if(is_long)
   {
      result = m_trade.Buy(lotSize, _Symbol, ask, sl, tp, comment);
   }
   else
   {
      result = m_trade.Sell(lotSize, _Symbol, bid, sl, tp, comment);
   }
   
   if(result)
   {
      Print("★ ", (is_long ? "BUY" : "SELL"), "注文成功: Conf=", DoubleToString(confidence, 3),
            " SL=", DoubleToString(sl, _Digits), " TP=", DoubleToString(tp, _Digits),
            " Preset=", GetPresetName());
      g_lastTradeBar = 0;
   }
   else
   {
      string err = "ENTRY_FAILED: " + (is_long ? "BUY" : "SELL") + " failure. Error=" + (string)GetLastError();
      Print((is_long ? "BUY" : "SELL"), "注文失敗: Error=", GetLastError());
      CLogger::Log(LOG_ERROR, err);
   }
}

//+------------------------------------------------------------------+
//| OHLCV データをJSON形式で準備                                     |
//+------------------------------------------------------------------+
string PrepareOHLCVJson(int bars)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, bars, rates);
   
   if(copied <= 0)
   {
      Print("データの取得に失敗: ", GetLastError());
      return "";
   }
   
   string json = "{";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"timeframe\":\"" + PeriodToString((ENUM_TIMEFRAMES)_Period) + "\",";
   json += "\"preset\":\"" + GetPresetName() + "\",";
   json += "\"ohlcv\":{";
   
   // Open
   json += "\"open\":[";
   for(int i = 0; i < copied; i++)
   {
      json += DoubleToString(rates[i].open, _Digits);
      if(i < copied - 1) json += ",";
   }
   json += "],";
   
   // High
   json += "\"high\":[";
   for(int i = 0; i < copied; i++)
   {
      json += DoubleToString(rates[i].high, _Digits);
      if(i < copied - 1) json += ",";
   }
   json += "],";
   
   // Low
   json += "\"low\":[";
   for(int i = 0; i < copied; i++)
   {
      json += DoubleToString(rates[i].low, _Digits);
      if(i < copied - 1) json += ",";
   }
   json += "],";
   
   // Close
   json += "\"close\":[";
   for(int i = 0; i < copied; i++)
   {
      json += DoubleToString(rates[i].close, _Digits);
      if(i < copied - 1) json += ",";
   }
   json += "],";
   
   // Volume
   json += "\"volume\":[";
   for(int i = 0; i < copied; i++)
   {
      json += IntegerToString(rates[i].tick_volume);
      if(i < copied - 1) json += ",";
   }
   json += "]";
   
   json += "},";
   json += "\"current_price\":" + DoubleToString(rates[copied-1].close, _Digits);
   json += "}";
   
   return json;
}

//+------------------------------------------------------------------+
//| HTTP POSTリクエスト送信                                          |
//+------------------------------------------------------------------+
bool SendHttpRequest(string url, string postData, string &response)
{
   uchar post[];
   uchar result[];
   string headers = "Content-Type: application/json\r\n";
   string result_headers;

   ResetLastError();
   int postLen = StringToCharArray(postData, post, 0, StringLen(postData), CP_UTF8);
   if(postLen < 0) postLen = 0;
   // StringToCharArray may append a terminating 0 byte; do not send it.
   if(postLen > 0 && post[postLen - 1] == 0)
      postLen--;
   ArrayResize(post, postLen);

   int res = WebRequest(
      "POST",
      url,
      headers,
      InpServerTimeout,
      post,
      result,
      result_headers
   );

   response = CharArrayToString(result, 0, ArraySize(result), CP_UTF8);

   if(res == -1)
   {
      int err = GetLastError();
      CLogger::Log(LOG_ERROR, StringFormat("WebRequest failed. err=%d url=%s", err, url));
      if(err == 4014)
      {
         CLogger::Log(LOG_ERROR, "MT5のWebRequest許可URLに推論サーバーURLを追加してください（ツール→オプション→エキスパートアドバイザ）");
         CLogger::Log(LOG_ERROR, StringFormat("許可URL例: %s", g_inferenceServerUrl));
      }
      return false;
   }

   if(res != 200)
   {
      string body = response;
      if(StringLen(body) > 500)
         body = StringSubstr(body, 0, 500) + "...";
      CLogger::Log(LOG_ERROR, StringFormat("HTTP error. status=%d url=%s body=%s", res, url, body));
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| サーバー接続テスト                                               |
//+------------------------------------------------------------------+
bool TestServerConnection()
{
   string response = "";
   uchar post[];
   uchar result[];
   string headers = "";
   string result_headers;
   
   ArrayResize(post, 0);
   
   string url = g_inferenceServerUrl + "/health";

   int res = WebRequest("GET", url, headers, 5000, post, result, result_headers);
   if(res == -1)
   {
      int err = GetLastError();
      Print("Health check failed: ", err, " url=", url);

      // 4014: WebRequestが許可されていない（URLリスト不一致が多い）
      if(err == 4014)
      {
         string altBase = g_inferenceServerUrl;
         if(StringFind(altBase, "localhost") >= 0)
            StringReplace(altBase, "localhost", "127.0.0.1");
         else if(StringFind(altBase, "127.0.0.1") >= 0)
            StringReplace(altBase, "127.0.0.1", "localhost");

         if(altBase != g_inferenceServerUrl)
         {
            string altUrl = altBase + "/health";
            Print("Retrying health with alt url=", altUrl);
            ArrayResize(result, 0);
            result_headers = "";

            int res2 = WebRequest("GET", altUrl, headers, 5000, post, result, result_headers);
            if(res2 != -1)
            {
               response = CharArrayToString(result, 0, ArraySize(result));
               if(StringFind(response, "ok") >= 0 || StringFind(response, "status") >= 0)
               {
                  g_inferenceServerUrl = altBase;
                  Print("✓ 推論サーバー接続OK (using ", g_inferenceServerUrl, ")");
                  return true;
               }
            }
            else
            {
               Print("Health retry failed: ", GetLastError(), " url=", altUrl);
            }
         }
      }

      return false;
   }

   response = CharArrayToString(result, 0, ArraySize(result));
   if(StringFind(response, "ok") >= 0 || StringFind(response, "status") >= 0)
   {
      Print("✓ 推論サーバー接続OK (using ", g_inferenceServerUrl, ")");
      return true;
   }

   Print("Health check returned unexpected body. url=", url, " body=", response);
   return false;
}

//+------------------------------------------------------------------+
//| 分析レスポンス解析                                               |
//+------------------------------------------------------------------+
bool ParseAnalyzeResponse(string response, int &signal, double &confidence, bool &entryAllowed, string &reason)
{
   if(!CJsonLite::TryGetInt(response, "signal", signal))
      return false;
   if(!CJsonLite::TryGetDouble(response, "confidence", confidence))
      return false;
   if(!CJsonLite::TryGetBool(response, "entry_allowed", entryAllowed))
      return false;
   
   // reasonはオプション（なくても失敗にしない）
   CJsonLite::TryGetString(response, "reason", reason);
   
   return true;
}

//+------------------------------------------------------------------+
//| Partial Close 永続化（端末Global Variables）                      |
//+------------------------------------------------------------------+
string PersistPrefix()
{
   return "PERSIST|MT5_AIT_FX|" + _Symbol + "|" + (string)g_ActiveMagicNumber + "|";
}

string PersistKey(long identifier, const string field)
{
   return PersistPrefix() + (string)identifier + "|" + field;
}

double GVGetD(const string key, const double defaultValue = 0.0)
{
   if(GlobalVariableCheck(key))
      return GlobalVariableGet(key);
   return defaultValue;
}

bool HasAnyPositionForSymbolMagic()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != g_ActiveMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      return true;
   }
   return false;
}

void PersistClearAllForSymbolMagic()
{
   string prefix = PersistPrefix();
   int total = GlobalVariablesTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) == 0)
         GlobalVariableDel(name);
   }

   if(InpLogPersistentTpStateEvents)
      CLogger::Log(LOG_INFO, StringFormat("[PERSIST][MT5_AIT_FX] cleared GV for %s magic=%lld", _Symbol, g_ActiveMagicNumber));
}

void CleanupPersistIfFlat()
{
   if(!InpEnablePersistentTpState)
      return;
   if(HasAnyPositionForSymbolMagic())
      return;

   datetime now = TimeCurrent();
   // クールダウン: 一度削除したら300秒（5分）は再削除しない
   if(g_lastPersistCleanup != 0 && (now - g_lastPersistCleanup) < 300)
      return;

   g_lastPersistCleanup = now;
   PersistClearAllForSymbolMagic();
}

void PersistSaveByTicket(const ulong ticket, const int stage)
{
   if(!InpEnablePersistentTpState)
      return;
   if(ticket == 0)
      return;
   if(!PositionSelectByTicket(ticket))
      return;

   long identifier = (long)PositionGetInteger(POSITION_IDENTIFIER);
   int posType = (int)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

   GlobalVariableSet(PersistKey(identifier, "stage"), (double)stage);
   GlobalVariableSet(PersistKey(identifier, "type"), (double)posType);
   GlobalVariableSet(PersistKey(identifier, "openPrice"), openPrice);
   GlobalVariableSet(PersistKey(identifier, "lastUpdate"), (double)TimeCurrent());

   if(InpLogPersistentTpStateEvents)
      CLogger::Log(LOG_INFO, StringFormat("[PERSIST][MT5_AIT_FX] saved ident=%lld ticket=%lld stage=%d", identifier, ticket, stage));
}

void RestoreForSelectedPosition(const ulong ticket)
{
   if(!InpEnablePersistentTpState)
      return;
   if(ticket == 0)
      return;
   if(!PositionSelectByTicket(ticket))
      return;

   long identifier = (long)PositionGetInteger(POSITION_IDENTIFIER);
   string stageKey = PersistKey(identifier, "stage");
   if(!GlobalVariableCheck(stageKey))
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) point = 0.00001;

   int persistedStage = (int)GVGetD(stageKey, 0.0);
   int persistedType = (int)GVGetD(PersistKey(identifier, "type"), -1.0);
   double persistedOpen = GVGetD(PersistKey(identifier, "openPrice"), 0.0);

   int currentType = (int)PositionGetInteger(POSITION_TYPE);
   double currentOpen = PositionGetDouble(POSITION_PRICE_OPEN);

   // Guard: type match + open price near match
   if(persistedType != currentType)
      return;
   if(MathAbs(currentOpen - persistedOpen) > (point * 2))
      return;

   int ticketIndex = (int)(ticket % 1000);
   int merged = g_partialCloseLevel[ticketIndex];
   if(persistedStage > merged)
      merged = persistedStage;

   if(merged != g_partialCloseLevel[ticketIndex])
   {
      g_partialCloseLevel[ticketIndex] = merged;
      if(InpLogPersistentTpStateEvents)
         CLogger::Log(LOG_INFO, StringFormat("[PERSIST][MT5_AIT_FX] restored ident=%lld ticket=%lld stage=%d", identifier, ticket, merged));
   }
}

//+------------------------------------------------------------------+
//| Partial Close チェック                                            |
//+------------------------------------------------------------------+
void CheckPartialClose()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int maxLevel = (InpPartialCloseStages >= 3) ? 3 : 2;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != g_ActiveMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      if(InpEnablePersistentTpState)
         RestoreForSelectedPosition(ticket);
      
      int ticketIndex = (int)(ticket % 1000);
      int currentLevel = g_partialCloseLevel[ticketIndex];
      if(currentLevel >= maxLevel) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      double profitPoints = 0;
      if(posType == POSITION_TYPE_BUY)
         profitPoints = (currentPrice - openPrice) / point;
      else
         profitPoints = (openPrice - currentPrice) / point;
      
      // レベル判定
      int newLevel = currentLevel;
      double closePercent = 0;
      double targetPoints = 0;
      
      if(currentLevel == 0 && profitPoints >= g_PartialClose1Points)
      {
         targetPoints = g_PartialClose1Points;
         closePercent = InpPartialClose1Percent;
         newLevel = 1;
      }
      else if(currentLevel == 1 && profitPoints >= g_PartialClose2Points)
      {
         targetPoints = g_PartialClose2Points;
         closePercent = (maxLevel == 2) ? 100.0 : InpPartialClose2Percent;
         newLevel = 2;
      }
      else if(maxLevel >= 3 && currentLevel == 2 && profitPoints >= g_PartialClose3Points)
      {
         targetPoints = g_PartialClose3Points;
         closePercent = InpPartialClose3Percent;
         newLevel = 3;
      }
      else
      {
         continue;
      }
      
      // 部分決済実行
      double currentLots = PositionGetDouble(POSITION_VOLUME);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotStep <= 0) lotStep = 0.01;
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      
      double lotsToClose = currentLots * closePercent / 100.0;
      // 余計に閉じてしまうのを避けるため、ロットは切り捨てでステップに合わせる
      lotsToClose = MathFloor(lotsToClose / lotStep) * lotStep;
      lotsToClose = NormalizeDouble(lotsToClose, 2);
      if(lotsToClose < minLot) lotsToClose = minLot;
      
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
      
      if(m_trade.PositionClosePartial(ticket, lotsToClose))
      {
         long identifier = PositionGetInteger(POSITION_IDENTIFIER);
         CLogger::Log(LOG_INFO, StringFormat("[TP_PARTIAL] Level %d: #%lld Lots=%.2f Profit=%.1f pts Identifier=%lld", 
               newLevel, ticket, lotsToClose, profitPoints, identifier));
         
         g_partialCloseLevel[ticketIndex] = newLevel;

         if(InpEnablePersistentTpState)
            PersistSaveByTicket(ticket, newLevel);
         
         // Level1後にBreakEven移動 / Level2後にSL移動（3段階モード）
         if((newLevel == 1 && InpMoveToBreakEvenAfterLevel1) || (newLevel == 2 && maxLevel >= 3 && InpMoveSLAfterLevel2))
         {
            Sleep(100);
            ulong newTicket = FindPositionByIdentifier(identifier);
            if(newTicket > 0)
            {
               g_partialCloseLevel[(int)(newTicket % 1000)] = newLevel;
               if(InpEnablePersistentTpState)
                  PersistSaveByTicket(newTicket, newLevel);

               if(newLevel == 1)
               {
                  SafePositionModifySL(newTicket, openPrice, PositionGetDouble(POSITION_TP), "BE");
                  CLogger::Log(LOG_INFO, StringFormat("[SL_MOVE] Level 1: Moved to Break-even @ %.5f (Ticket #%lld)", openPrice, newTicket));
               }
               else // newLevel == 2
               {
                  double level1Price;
                  if(posType == POSITION_TYPE_BUY)
                     level1Price = openPrice + g_PartialClose1Points * point;
                  else
                     level1Price = openPrice - g_PartialClose1Points * point;
                  
                  SafePositionModifySL(newTicket, level1Price, PositionGetDouble(POSITION_TP), "L1");
                  CLogger::Log(LOG_INFO, StringFormat("[SL_MOVE] Level 2: Moved to Level1 profit @ %.5f (Ticket #%lld)", level1Price, newTicket));
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ポジション識別子によるポジション検索                                |
//+------------------------------------------------------------------+
ulong FindPositionByIdentifier(long identifier)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && 
         PositionGetInteger(POSITION_MAGIC) == g_ActiveMagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_IDENTIFIER) == identifier)
      {
         return ticket;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| SL safety helper                                                 |
//+------------------------------------------------------------------+
bool IsFinitePrice(const double v)
{
   if(v != v) return false;
   if(MathAbs(v) > 1e10) return false;
   return true;
}

bool SafePositionModifySL(ulong ticket, double desiredSL, double tp, const string tag)
{
   if(!PositionSelectByTicket(ticket)) return false;

   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double currentSL = PositionGetDouble(POSITION_SL);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0) point = _Point;

   double newSL = NormalizeDouble(desiredSL, digits);
   if(!IsFinitePrice(newSL) || newSL <= 0.0)
   {
      CLogger::Log(LOG_WARN, StringFormat("[SAFE_SL] Skip PositionModify(%s): invalid SL=%.10f ticket=%lld", tag, newSL, ticket));
      return false;
   }

   // Disallow worsening SL changes (never loosen risk)
   double tol = point * 2.0;
   if(currentSL > 0.0)
   {
      if(posType == POSITION_TYPE_BUY && newSL < currentSL - tol)
      {
         CLogger::Log(LOG_WARN, StringFormat("[SAFE_SL] Skip PositionModify(%s): worsening BUY SL %.5f -> %.5f ticket=%lld", tag, currentSL, newSL, ticket));
         return false;
      }
      if(posType == POSITION_TYPE_SELL && newSL > currentSL + tol)
      {
         CLogger::Log(LOG_WARN, StringFormat("[SAFE_SL] Skip PositionModify(%s): worsening SELL SL %.5f -> %.5f ticket=%lld", tag, currentSL, newSL, ticket));
         return false;
      }
   }

   return m_trade.PositionModify(ticket, newSL, tp);
}

//+------------------------------------------------------------------+
//| ユーティリティ関数                                                |
//+------------------------------------------------------------------+
bool PassesTimeFilter()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day_of_week == 5 && !InpTradeOnFriday)
      return false;
   
   if(!InpEnable_Time_Filter)
      return true;
   
   // JST変換
   int gmt_offset_seconds = InpGMT_Offset * 3600;
   if(InpUse_DST) gmt_offset_seconds += 3600;
   datetime jst_time = TimeCurrent() - gmt_offset_seconds + (9 * 3600);
   MqlDateTime jst_dt;
   TimeToStruct(jst_time, jst_dt);
   
   int current_minutes = jst_dt.hour * 60 + jst_dt.min;
   int start_minutes = InpCustom_Start_Hour * 60 + InpCustom_Start_Minute;
   int end_minutes = InpCustom_End_Hour * 60 + InpCustom_End_Minute;
   
   if(start_minutes <= end_minutes)
   {
      // 通常パターン (例: 8:00 - 21:00)
      return (current_minutes >= start_minutes && current_minutes <= end_minutes);
   }
   else
   {
      // 深夜をまたぐパターン (例: 22:00 - 6:00)
      return (current_minutes >= start_minutes || current_minutes <= end_minutes);
   }
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == g_ActiveMagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return count;
}

double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   double lotSize;
   if(InpEnableLotAdjustment && tickValue > 0)
   {
      lotSize = riskAmount / (g_StopLossPoints * tickValue);
      lotSize = NormalizeDouble(lotSize, 2);
   }
   else
   {
      lotSize = InpBaseLotSize;
   }
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   if(lotSize > InpMaxLotSize) lotSize = InpMaxLotSize;
   
   return MathMax(lotSize, minLot);
}

void CalculateSLTP(bool is_long, double entry_price, double &sl, double &tp)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slPoints = g_StopLossPoints;
   double tpPoints = g_TakeProfitPoints;
   
   if(InpUse_ATR_SLTP)
   {
      double atr = GetATR(InpATRPeriod);
      slPoints = atr / point * InpStopLoss_ATR_Multi;
      tpPoints = atr / point * InpTakeProfit_ATR_Multi;
   }
   
   if(is_long)
   {
      sl = entry_price - slPoints * point;
      tp = entry_price + tpPoints * point;
   }
   else
   {
      sl = entry_price + slPoints * point;
      tp = entry_price - tpPoints * point;
   }
   
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
}

double GetATR(int period)
{
   if(period <= 0) return 0.0;
   double atr[];
   ArraySetAsSeries(atr, true);
   int handle = iATR(_Symbol, PERIOD_CURRENT, period);
   if(handle == INVALID_HANDLE) return 0.0;
   if(CopyBuffer(handle, 0, 0, 1, atr) != 1)
   {
      IndicatorRelease(handle);
      return 0.0;
   }
   IndicatorRelease(handle);
   if(ArraySize(atr) < 1) return 0.0;
   return atr[0];
}

string PeriodToString(ENUM_TIMEFRAMES period)
{
   switch(period)
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
      default: return "M15";
   }
}
//+------------------------------------------------------------------+
