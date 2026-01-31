//+------------------------------------------------------------------+
//|                                  EA_PullbackEntry_v5_JP225.mq5   |
//|                    MQL5 OOP Version - Pullback Entry Strategy    |
//|                    日経225専用 単位: 円 (1point=1円)               |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "5.17"
#property strict

#include <Trade\Trade.mqh>
#include <Strategies/Pullback/PullbackConfig.mqh>
#include <Strategies/Pullback/PullbackPresets.mqh>
#include <Strategies/Pullback/PullbackStrategy.mqh>
#include <Position/PositionManager.mqh>
#include <Filters/FilterManager.mqh>
#include <Integration/Logger.mqh>
#include <Integration/AccountStatusCsv.mqh>

//=== INPUT PARAMETERS ===

//--- Preset Selection
input ENUM_STRATEGY_PRESET InpPreset = PRESET_STANDARD;  // 戦略プリセット
input int InpPresetApplyMode = 1;  // Preset適用モード: 0=使わない(Input優先), 1=未設定のみ補完★推奨, 2=全上書き

//--- Basic Settings
input double InpLotSize = 0.10;              // ロットサイズ
input bool   InpAutoMagicNumber = false;     // マジックナンバー自動生成（true時、下の値は無視）
input long   InpMagicNumber = 55000001;      // マジックナンバー
input double InpDeviationYen = 20.0;         // 最大スリッページ(円) ※M15推奨: 20円

//--- EMA Settings
input int    InpEmaShort = 12;               // 短期EMA
input bool   InpUseEmaShort = true;          // 短期EMA使用
input int    InpEmaMid = 25;                 // 中期EMA
input bool   InpUseEmaMid = true;            // 中期EMA使用
input int    InpEmaLong = 100;               // 長期EMA
input bool   InpUseEmaLong = true;           // 長期EMA使用
input bool   InpRequirePerfectOrder = true;  // パーフェクトオーダー必須（MT4非OOP版準拠）
input bool   InpUseTouchPullback = true;     // タッチプルバック
input bool   InpUseCrossPullback = true;     // クロスプルバック
input bool   InpUseBreakPullback = false;    // ブレイクプルバック
input ENUM_PULLBACK_EMA_REF InpPullbackEmaRef = PULLBACK_EMA_25;  // プルバック基準EMA
input int    InpPullbackLookback = 5;        // プルバック検出Lookback本数（MT4非OOP互換）

//--- 確認足設定 (MT4非OOP互換: Use_Confirmation_Bar)
input bool   InpUseConfirmationBar = false;  // 確認足検証を有効化
input double InpConfirmBarMinYen = 10.0;     // 確認足最小サイズ(円)
input double InpConfirmBarMaxYen = 0.0;      // 確認足最大サイズ(円) 0=無制限
input bool   InpRequirePriceBreak = false;   // 価格ブレイク待機モード
input double InpEntryBreakBufferYen = 5.0;   // エントリーバッファ(円)

//--- EMA傾きフィルター (MT4非OOP互換: CheckEMASlope)
input bool   InpUseEmaSlopeFilter = true;    // EMA傾きフィルター有効
input double InpEmaMinSlopeFast = 0.0;       // 短期EMA最小傾き（0=無効）
input double InpEmaMinSlopeSlow = 0.0;       // 長期EMA最小傾き（0=無効）
input int    InpEmaSlopeBars = 3;            // 傾き計算バー数

//--- ローソク足条件 (MT4非OOP互換: CheckCandleCondition)
input bool   InpUseCandleCondition = true;   // ローソク足条件チェック有効
input double InpMinCandleBodyPercent = 20.0; // 最小実体比率(%)

//--- 強トレンドモード (MT4非OOP互換 + Al Brooks理論拡張)
input bool   InpUseStrongTrendMode = false;  // 強トレンドモード有効
input double InpStrongTrendADXLevel = 30.0;  // 強トレンドADX閾値
input bool   InpStrongTrendAutoActivate = false; // 自動判定モード

//--- Al Brooks強トレンド理論
input int    InpConsecutiveBarsCount = 3;       // 連続陽線/陰線の最小本数
input double InpLargeCandleMultiplier = 1.5;    // 大陽線/大陰線判定 (ATR倍率)
input double InpShallowPullbackPercent = 40.0;  // 浅いプルバック許容率(%)
input bool   InpUseBreakoutBarEntry = false;    // ブレイクアウトバー即エントリー
input double InpMinBarBodyRatio = 60.0;         // 最小ボディ比率(%, ヒゲ少)

//--- トレンドライン/チャネルモード (設計書セクション12-13)
input ENUM_TL_CHANNEL_MODE InpTLChannelMode = MODE_EMA_ONLY;  // トレンドライン/チャネルモード
input int    InpTrendLineLookbackBars = 100;      // トレンドライン検出バー数
input int    InpTrendLineMinTouches = 3;          // トレンドライン最小タッチ回数
input int    InpTrendLineTolerancePoints = 100;   // トレンドライン許容誤差(円)
input bool   InpTrendLineAutoUpdate = true;       // トレンドライン自動更新
input bool   InpChannelReversalOnly = true;       // チャネル逆張りのみ
input double InpChannelMinWidth = 100.0;          // チャネル最小幅(円)
input double InpChannelMaxWidth = 1000.0;         // チャネル最大幅(円)
input bool   InpChannelRequireParallel = true;    // 平行チャネル必須
input double InpChannelParallelTolerance = 0.5;   // 平行許容誤差

//--- AIノイズ対策 (AI_MARKET_TRANSFORMATION.md準拠)
input bool   InpUseATRSpikeFilter = true;         // ATRスパイク検出（モメンタム・イグニッション回避）
input double InpATRSpikeMultiplier = 2.0;         // ATRスパイク判定倍率（平均比）
input int    InpATRSpikeAvgBars = 10;             // ATR平均計算期間
input int    InpATRSpikeWaitBars = 3;             // スパイク後の待機本数
input bool   InpUseSecondWaveEntry = false;       // 2度目の動きを狙う
input int    InpSecondWaveMinBars = 3;            // 1回目から2回目の最小間隔
input int    InpSecondWaveMaxBars = 10;           // 1回目から2回目の最大間隔
input bool   InpUsePostStopHuntEntry = false;     // ストップ狩り後エントリー
input double InpStopHuntSpikeYen = 50.0;          // ストップ狩りスパイク幅(円)
input int    InpStopHuntRecoveryBars = 2;         // 回復確認バー数

//--- ラウンドナンバー (1000/500円) 設定
input bool   InpUseRoundNumberLines = false;      // ラウンドナンバーライン使用
input bool   InpRN_Use_00_Line = true;            // 1000円ライン使用
input bool   InpRN_Use_50_Line = true;            // 500円ライン使用
input double InpRN_TouchBufferYen = 20.0;         // タッチ判定バッファ(円)
input int    InpRN_LookbackBars = 3;              // 検出期間(バー数)
input bool   InpRN_CounterTrend = false;          // 逆張りモード（反転狙い）
input int    InpRN_DigitLevel = 0;                // 桁数レベル（0=整数, 日索225）
input bool   InpRN_AvoidEntryNear = false;        // ラウンドナンバー付近でのエントリー回避
input double InpRN_AvoidBufferYen = 50.0;         // 回避範囲(円)

//--- Time Filter (JST)
input bool   InpEnableTimeFilter = true;     // 時間フィルター有効
input int    InpGMTOffset = 3;               // GMTオフセット
input int    InpStartHour = 8;               // 開始時刻(JST)
input int    InpStartMinute = 0;             // 開始分(JST)
input int    InpEndHour = 21;                // 終了時刻(JST)
input int    InpEndMinute = 0;               // 終了分(JST)
input bool   InpUseDST = false;              // 夏時間有効
input bool   InpTradeOnFriday = true;        // 金曜取引

//--- 毎日指定時間の全決済（JST）
input bool   InpEnableFridayCloseJST = true;  // 毎日指定時間の全決済
input int    InpFridayCloseStartHour = 23;    // 開始時(時) JST
input int    InpFridayCloseStartMinute = 0;   // 開始時(分) JST
input int    InpFridayCloseEndHour = 4;       // 終了時(時) JST
input int    InpFridayCloseEndMinute = 30;    // 終了時(分) JST

//--- MTF Filter
input bool            InpEnableMTFFilter = false;   // MTFフィルター有効
input ENUM_TIMEFRAMES InpMTFTimeframe = PERIOD_H1;  // MTF時間足
input int             InpMTFEmaShort = 12;          // MTF EMA短期
input bool            InpUseMTFEmaShort = true;     // MTF短期EMA使用
input int             InpMTFEmaMid = 25;            // MTF EMA中期
input bool            InpUseMTFEmaMid = true;       // MTF中期EMA使用
input int             InpMTFEmaLong = 100;          // MTF EMA長期
input bool            InpUseMTFEmaLong = true;      // MTF長期EMA使用

//--- Spread/ADX/ATR Filter
input int    InpMaxSpreadYen = 20;           // 最大スプレッド(円) ※OANDA推奨: 20円
input bool   InpUseADXFilter = true;         // ADXフィルター
input int    InpADXPeriod = 14;              // ADX期間
input double InpADXMinLevel = 20.0;          // ADX最小値（MT4非OOP版準拠）
input int    InpATRPeriod = 14;              // ATR期間
input double InpATRMinYen = 70.0;            // ATR最小値(円)（ドキュメント推奨: 70円）

//--- SL/TP Settings
input ENUM_SLTP_MODE InpSLTPMode = SLTP_FIXED;  // SL/TPモード
input double InpSLFixedYen = 50.0;           // SL(円) ※M15推奨: 40-60円
input double InpTPFixedYen = 100.0;          // TP(円) ※M15推奨: 80-120円
input double InpSLAtrMulti = 1.5;            // SL ATR倍率
input double InpTPAtrMulti = 2.0;            // TP ATR倍率

//--- Partial Close
input bool   InpEnablePartialClose = true;   // 部分決済有効
input int    InpPartialStages = 2;           // 段階数(2/3)
input double InpPartial1Yen = 15.0;          // 1段階目(円)
input double InpPartial1Percent = 50.0;      // 1段階目決済率(%)
input double InpPartial2Yen = 30.0;          // 2段階目(円)
input double InpPartial2Percent = 50.0;      // 2段階目決済率(%)
input double InpPartial3Yen = 45.0;          // 3段階目(円)
input double InpPartial3Percent = 100.0;     // 3段階目決済率(%)
input bool   InpMoveToBreakEven = true;      // Level1後に建値移動
input bool   InpMoveSLAfterLevel2 = true;    // Level2後にSL移動(Level1利益位置へ)

//--- Persistent TP State (Terminal Global Variables)
input bool   InpEnablePersistentTpState = true;       // 段階利確(部分決済レベル)を永続化
input bool   InpLogPersistentTpStateEvents = false;   // 永続化イベントをログ出力

//--- Trailing Stop
input ENUM_TRAILING_MODE InpTrailingMode = TRAILING_DISABLED;  // トレーリングモード
input double InpTrailStartYen = 20.0;        // トレーリング開始(円)
input double InpTrailStepYen = 5.0;          // トレーリングステップ(円)

//--- Logging
input bool   InpShowDebugLog = false;                 // デバッグログを出力する
input bool   InpEnableLogging = true;                 // ログ出力有効
input ENUM_LOG_LEVEL InpLogMinLevel = LOG_INFO;       // 最小ログレベル
input bool   InpLogToFile = true;                     // ファイル出力
input bool   InpLogUseCommonFolder = false;           // Commonフォルダ使用（OneDriveLogs配下に出したい場合はfalse推奨）
input string InpLogFileName = "OneDriveLogs\\logs\\EA_PullbackEntry_v5.log"; // ログファイル名（MQL5/Files配下）
input int    InpSkipLogCooldown = 60;                 // 同一スキップログの抑制秒数
input int    InpMainLogicIntervalSec = 60;            // メインロジック実行間隔(秒)

//--- Data collection (MT4 log sync compatible)
input bool   InpEnableAiLearningCsv = true;                    // AI学習CSV出力（DB同期用）
input string InpTerminalId = "10900k-mt5-index";              // 端末固定ID（例: 10900k-mt5-index, matsu-mt5-index）
input bool   InpAutoAppendSymbol = true;                       // TerminalIDにシンボルを自動追加
input string InpAiLearningFolder = "OneDriveLogs\\data\\AI_Learning"; // MQL5/Files配下

//=== GLOBAL OBJECTS ===
CPullbackStrategy *g_strategy = NULL;
CPositionManager  *g_posManager = NULL;
CFilterManager    *g_filterManager = NULL;

// 円→Points変換値（OnInitで計算）
double g_yenMultiplier = 1.0;
double g_MaxSpreadPoints = 0;
double g_StopLossPoints = 0;
double g_TakeProfitPoints = 0;
double g_ATRMinPoints = 0;
double g_SLFixedPoints = 0;
double g_TPFixedPoints = 0;
double g_Partial1Points = 0;
double g_Partial2Points = 0;
double g_Partial3Points = 0;
double g_TrailStartPoints = 0;
double g_TrailStepPoints = 0;

string BoolStr(const bool v){ return v ? "true" : "false"; }

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

string BuildLogFileName(const string baseName)
{
   string name = (StringLen(baseName) > 0) ? baseName : "EA_PullbackEntry_v5.log";

   int lastDot = -1;
   for(int i = 0; i < StringLen(name); i++)
   {
      if(StringGetCharacter(name, i) == '.')
         lastDot = i;
   }

   string ext = (lastDot >= 0) ? StringSubstr(name, lastDot) : ".log";
   string stem = (lastDot >= 0) ? StringSubstr(name, 0, lastDot) : name;

   string tfStr = EnumToString((ENUM_TIMEFRAMES)_Period);
   return stem + "_" + _Symbol + "_" + tfStr + "_" + AccountModeTag() + ext;
}
//+------------------------------------------------------------------+
//| フォルダパスの作成を保証する                                     |
//+------------------------------------------------------------------+
bool EnsureFolderPath(string folderPath)
{
   if(StringLen(folderPath) <= 0)
      return false;

   string parts[];
   int n = StringSplit(folderPath, '\\', parts);
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
//| パスからフォルダ部分を抽出                                       |
//+------------------------------------------------------------------+
string FolderPart(const string path)
{
   int lastSep = -1;
   for(int i = 0; i < StringLen(path); i++)
   {
      const ushort ch = (ushort)StringGetCharacter(path, i);
      if(ch == '\\' || ch == '/')
         lastSep = i;
   }
   if(lastSep < 0)
      return "";
   return StringSubstr(path, 0, lastSep);
}

long GenerateMagicNumber()
{
   // EA名 + Symbol + TF + 口座モード から安定ハッシュ（衝突を減らす）
   string key = MQLInfoString(MQL_PROGRAM_NAME) + "|" + _Symbol + "|" + EnumToString((ENUM_TIMEFRAMES)Period()) + "|" + AccountModeTag();
   ulong hash = 0;
   for(int i = 0; i < StringLen(key); i++)
      hash = hash * 31 + (ulong)StringGetCharacter(key, i);
   return (long)(55000000 + (hash % 1000000));
}

void DumpEffectiveConfig(const ENUM_STRATEGY_PRESET preset,
                         const CPullbackConfig &cfg)
{
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBE_JP] Symbol=%s Magic=%lld Preset=%s", _Symbol, cfg.MagicNumber, GetPresetName(preset)));
}

void LogSkipReason(string reason)
{
   // テスター内ではスキップログを抑制（高速進行で大量出力されるため）
   if(MQLInfoInteger(MQL_TESTER)) return;
   
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
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   const long activeMagic = InpAutoMagicNumber ? GenerateMagicNumber() : InpMagicNumber;
   string instanceId = "EA_PullbackEntry_v5_JP225|" + _Symbol + "|Acct:" + AccountModeTag() + "|Magic:" + (string)activeMagic + "|CID:" + (string)ChartID();
   string logFileName = BuildLogFileName(InpLogFileName);
   if(!InpLogUseCommonFolder)
      EnsureFolderPath(FolderPart(logFileName));

   ENUM_LOG_LEVEL minLevel = InpLogMinLevel;
   if(InpShowDebugLog) minLevel = LOG_DEBUG;
   CLogger::Configure(instanceId, InpEnableLogging, minLevel, InpLogToFile, logFileName, InpLogUseCommonFolder);

    // 円→Points変換（JP225: 1円 ≈ 1point / 0.1 / 0.01 dependiendo del broker）
    double symbolPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(symbolPoint > 0)
       g_yenMultiplier = 1.0 / symbolPoint;  // 例: point=0.1 → multiplier=10
    else
       g_yenMultiplier = 1.0;  // デフォルト
 
    g_MaxSpreadPoints = (int)(InpMaxSpreadYen * g_yenMultiplier);
    g_ATRMinPoints = InpATRMinYen * g_yenMultiplier;
    g_SLFixedPoints = InpSLFixedYen * g_yenMultiplier;
    g_TPFixedPoints = InpTPFixedYen * g_yenMultiplier;
    g_Partial1Points = InpPartial1Yen * g_yenMultiplier;
    g_Partial2Points = InpPartial2Yen * g_yenMultiplier;
    g_Partial3Points = InpPartial3Yen * g_yenMultiplier;
    g_TrailStartPoints = InpTrailStartYen * g_yenMultiplier;
    g_TrailStepPoints = InpTrailStepYen * g_yenMultiplier;
    
    CLogger::Log(LOG_INFO, StringFormat("★ 円→Points変換: multiplier=%.0f SL=%.1f円→%.0fpts TP=%.1f円→%.0fpts",
                 g_yenMultiplier, InpSLFixedYen, g_SLFixedPoints, InpTPFixedYen, g_TPFixedPoints));

   CLogger::Log(LOG_INFO, "PullbackEntry v5.12 JP225 (MQL5)");
   
   // Build Config
   CPullbackConfig cfg;
   
   // ★★★ 3レイヤーモデル: InpPresetApplyModeによる制御 ★★★
   // mode=0: Input優先（Preset適用なし）- 常にInputを使用
   // mode=1: Input優先（未設定のみ補完）- 常にInputを使用
   // mode=2: Preset全上書き（旧互換）- Presetを先に適用、CUSTOMの時のみInput
   
   if(InpPresetApplyMode == 2)
   {
      // 旧互換モード: Preset先適用
      ApplyPreset(cfg, InpPreset);
      CLogger::Log(LOG_INFO, "PresetApplyMode=2: Preset全上書き（旧互換モード）");
   }
   else
   {
      // mode=0/1: Input優先（Preset適用なし）
      CLogger::Log(LOG_INFO, StringFormat("PresetApplyMode=%d: Input優先（.set尊重）", InpPresetApplyMode));
   }
   
   // 常にInput値を適用（mode=0/1ではこれがメイン、mode=2ではCUSTOM用上書き）
   cfg.MagicNumber = activeMagic;
   cfg.LotSize = InpLotSize;
   cfg.DeviationPoints = (int)(InpDeviationYen * g_yenMultiplier);

   // Data collection
   cfg.EnableAiLearningLog = InpEnableAiLearningCsv;
   // TerminalIdにシンボル自動追加
   if(InpAutoAppendSymbol)
   {
      string tfStr = EnumToString((ENUM_TIMEFRAMES)_Period);
      StringReplace(tfStr, "PERIOD_", "");
      cfg.TerminalId = InpTerminalId + "_" + _Symbol + "_" + tfStr;
   }
   else
   {
      cfg.TerminalId = InpTerminalId;
   }
   cfg.AiLearningFolder = InpAiLearningFolder;
   
   // mode=0/1 または PRESET_CUSTOM: Inputから全パラメータを読み込み
   if(InpPresetApplyMode != 2 || InpPreset == PRESET_CUSTOM)
   {
      cfg.EmaShortPeriod = InpEmaShort;
      cfg.EmaMidPeriod = InpEmaMid;
      cfg.EmaLongPeriod = InpEmaLong;
      cfg.UseEmaShort = InpUseEmaShort;
      cfg.UseEmaMid = InpUseEmaMid;
      cfg.UseEmaLong = InpUseEmaLong;
      cfg.RequirePerfectOrder = InpRequirePerfectOrder;  // MT4互換
      cfg.UseTouchPullback = InpUseTouchPullback;
      cfg.UseCrossPullback = InpUseCrossPullback;
      cfg.UseBreakPullback = InpUseBreakPullback;
      cfg.PullbackEmaRef = InpPullbackEmaRef;
      cfg.PullbackLookback = InpPullbackLookback;

      // 確認足設定 (MT4非OOP互換) - JP225は円単位をポイントに変換
      cfg.UseConfirmationBar = InpUseConfirmationBar;
      cfg.ConfirmationBarMinPips = InpConfirmBarMinYen / _Point;  // 円→Points
      cfg.ConfirmationBarMaxPips = InpConfirmBarMaxYen / _Point;
      cfg.RequirePriceBreak = InpRequirePriceBreak;
      cfg.EntryBreakBufferPips = InpEntryBreakBufferYen / _Point;

      // EMA傾きフィルター (MT4非OOP互換)
      cfg.UseEmaSlopeFilter = InpUseEmaSlopeFilter;
      cfg.EmaMinSlopeFast = InpEmaMinSlopeFast;
      cfg.EmaMinSlopeSlow = InpEmaMinSlopeSlow;
      cfg.EmaSlopeBars = InpEmaSlopeBars;

      // ローソク足条件 (MT4非OOP互換)
      cfg.UseCandleCondition = InpUseCandleCondition;
      cfg.MinCandleBodyPercent = InpMinCandleBodyPercent;

      // 強トレンドモード (MT4非OOP互換 + Al Brooks理論拡張)
      cfg.UseStrongTrendMode = InpUseStrongTrendMode;
      cfg.StrongTrendADXLevel = InpStrongTrendADXLevel;
      cfg.StrongTrendAutoActivate = InpStrongTrendAutoActivate;
      cfg.ConsecutiveBarsCount = InpConsecutiveBarsCount;
      cfg.LargeCandleMultiplier = InpLargeCandleMultiplier;
      cfg.ShallowPullbackPercent = InpShallowPullbackPercent;
      cfg.UseBreakoutBarEntry = InpUseBreakoutBarEntry;
      cfg.MinBarBodyRatio = InpMinBarBodyRatio;

      // トレンドライン/チャネルモード (設計書セクション12-13)
      cfg.TLChannelMode = InpTLChannelMode;
      cfg.TrendLineLookbackBars = InpTrendLineLookbackBars;
      cfg.TrendLineMinTouches = InpTrendLineMinTouches;
      cfg.TrendLineTolerancePoints = InpTrendLineTolerancePoints;
      cfg.TrendLineAutoUpdate = InpTrendLineAutoUpdate;
      cfg.ChannelReversalOnly = InpChannelReversalOnly;
      cfg.ChannelMinWidthPoints = InpChannelMinWidth;
      cfg.ChannelMaxWidthPoints = InpChannelMaxWidth;
      cfg.ChannelRequireParallel = InpChannelRequireParallel;
      cfg.ChannelParallelTolerance = InpChannelParallelTolerance;

      // AIノイズ対策 (AI_MARKET_TRANSFORMATION.md準拠)
      cfg.UseATRSpikeFilter = InpUseATRSpikeFilter;
      cfg.ATRSpikeMultiplier = InpATRSpikeMultiplier;
      cfg.ATRSpikeAvgBars = InpATRSpikeAvgBars;
      cfg.ATRSpikeWaitBars = InpATRSpikeWaitBars;
      cfg.UseSecondWaveEntry = InpUseSecondWaveEntry;
      cfg.SecondWaveMinBars = InpSecondWaveMinBars;
      cfg.SecondWaveMaxBars = InpSecondWaveMaxBars;
      cfg.UsePostStopHuntEntry = InpUsePostStopHuntEntry;
      cfg.StopHuntSpikePoints = InpStopHuntSpikeYen;  // JP225は1point=1円
      cfg.StopHuntRecoveryBars = InpStopHuntRecoveryBars;

      // ラウンドナンバー設定 (JP225: 1000/500円)
      cfg.UseRoundNumberLines = InpUseRoundNumberLines;
      cfg.RN_Use_00_Line = InpRN_Use_00_Line;
      cfg.RN_Use_50_Line = InpRN_Use_50_Line;
      cfg.RN_TouchBufferPoints = InpRN_TouchBufferYen;  // JP225は1point=1円
      cfg.RN_LookbackBars = InpRN_LookbackBars;
      cfg.RN_CounterTrend = InpRN_CounterTrend;
      cfg.RN_DigitLevel = InpRN_DigitLevel;
      cfg.RN_AvoidEntryNear = InpRN_AvoidEntryNear;
      cfg.RN_AvoidBufferPoints = InpRN_AvoidBufferYen;  // JP225は1point=1円

      cfg.MaxSpreadPoints = g_MaxSpreadPoints;
      cfg.UseADXFilter = InpUseADXFilter;
      cfg.ADXPeriod = InpADXPeriod;
      cfg.ADXMinLevel = InpADXMinLevel;
      cfg.ATRPeriod = InpATRPeriod;
      cfg.ATRThresholdPoints = g_ATRMinPoints;
      cfg.SLTPMode = InpSLTPMode;
      cfg.StopLossFixedPoints = g_SLFixedPoints;
      cfg.TakeProfitFixedPoints = g_TPFixedPoints;
      cfg.StopLossAtrMulti = InpSLAtrMulti;
      cfg.TakeProfitAtrMulti = InpTPAtrMulti;
   }
   
   // Create Strategy
   g_strategy = new CPullbackStrategy(_Symbol, PERIOD_CURRENT, cfg);
   
   // Create Filter Manager
   SFilterConfig filterCfg;
   filterCfg.Symbol = _Symbol;
   filterCfg.EnableTimeFilter = InpEnableTimeFilter;
   filterCfg.GMTOffset = InpGMTOffset;
   filterCfg.UseDST = InpUseDST;
   filterCfg.StartMinute = InpStartMinute;
   filterCfg.EndMinute = InpEndMinute;
   filterCfg.StartHour = InpStartHour;
   filterCfg.EndHour = InpEndHour;
   filterCfg.TradeOnFriday = InpTradeOnFriday;
   filterCfg.EnableSpreadFilter = true;
   filterCfg.MaxSpreadPoints = g_MaxSpreadPoints;
   filterCfg.EnableADXFilter = InpUseADXFilter;
   filterCfg.ADXPeriod = InpADXPeriod;
   filterCfg.ADXMinLevel = InpADXMinLevel;
   filterCfg.EnableATRFilter = true;
   filterCfg.ATRPeriod = InpATRPeriod;
   filterCfg.ATRMinPoints = g_ATRMinPoints;
   // MTF Config
   filterCfg.EnableMTFFilter = InpEnableMTFFilter;
   filterCfg.MTFTimeframe = InpMTFTimeframe;
   filterCfg.MTFEmaShort = InpMTFEmaShort;
   filterCfg.MTFEmaMid = InpMTFEmaMid;
   filterCfg.MTFEmaLong = InpMTFEmaLong;
   filterCfg.UseMTFEmaShort = InpUseMTFEmaShort;
   filterCfg.UseMTFEmaMid = InpUseMTFEmaMid;
   filterCfg.UseMTFEmaLong = InpUseMTFEmaLong;
   
   g_filterManager = new CFilterManager();
   g_filterManager.Init(filterCfg, PERIOD_CURRENT);
   
   // Create Position Manager
   SPositionConfig posCfg;
   posCfg.MagicNumber = activeMagic;
   posCfg.Symbol = _Symbol;
   posCfg.EnablePersistentTpState = InpEnablePersistentTpState;
   posCfg.LogPersistentTpStateEvents = InpLogPersistentTpStateEvents;
   posCfg.EnablePartialClose = InpEnablePartialClose;
   posCfg.PartialCloseStages = InpPartialStages;
   posCfg.PartialClose1Points = g_Partial1Points;
   posCfg.PartialClose1Percent = InpPartial1Percent;
   posCfg.PartialClose2Points = g_Partial2Points;
   posCfg.PartialClose2Percent = InpPartial2Percent;
   posCfg.PartialClose3Points = g_Partial3Points;
   posCfg.PartialClose3Percent = InpPartial3Percent;
   posCfg.MoveToBreakEvenAfterLevel1 = InpMoveToBreakEven;
   posCfg.MoveSLAfterLevel2 = InpMoveSLAfterLevel2;
   posCfg.EnableFridayCloseJST = InpEnableFridayCloseJST;
   posCfg.FridayCloseStartHour = InpFridayCloseStartHour;
   posCfg.FridayCloseStartMinute = InpFridayCloseStartMinute;
   posCfg.FridayCloseEndHour = InpFridayCloseEndHour;
   posCfg.FridayCloseEndMinute = InpFridayCloseEndMinute;
   posCfg.TrailingMode = InpTrailingMode;
   posCfg.TrailingStartPoints = g_TrailStartPoints;
   posCfg.TrailingStepPoints = g_TrailStepPoints;
   posCfg.TrailingATRMulti = 1.0;
   posCfg.ATRPeriod = InpATRPeriod;
   posCfg.MaxSlippagePoints = (int)(InpDeviationYen * g_yenMultiplier);

   DumpEffectiveConfig(InpPreset, cfg);
   
   g_posManager = new CPositionManager();
   g_posManager.Init(posCfg);
   
   CLogger::Log(LOG_INFO, "Initialization complete");
   ExportAccountStatusWithTerminalId(InpTerminalId);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_strategy != NULL)    { delete g_strategy;     g_strategy = NULL; }
   if(g_posManager != NULL)  { delete g_posManager;   g_posManager = NULL; }
   if(g_filterManager != NULL) { delete g_filterManager; g_filterManager = NULL; }

   CLogger::Log(LOG_INFO, "EA_PullbackEntry deinitialized - reason: " + IntegerToString(reason));
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
      ExportAccountStatusWithTerminalId(InpTerminalId);
      last_export = now_export;
   }

   // 1. ポジション監視（利確・SL移動）は常に実行
   if(g_posManager != NULL)
      g_posManager.OnTick();

   // 2. メインロジック（分析・エントリー）はタイザー制御
   static datetime last_logic_exec = 0;
   datetime now = TimeCurrent();
   
   if(now - last_logic_exec < InpMainLogicIntervalSec)
      return;
      
   last_logic_exec = now;
   
   // Skip if filters fail
   if(g_filterManager != NULL && !g_filterManager.CheckAll())
   {
      LogSkipReason("Filter rejected: " + g_filterManager.GetLastRejectReason());
      return;
   }
   
   // Strategy entry logic
   if(g_strategy != NULL)
   {
      // Check MTF Trend Bias
      bool allowBuy = true;
      bool allowSell = true;
      if(g_filterManager != NULL)
      {
         allowBuy = g_filterManager.CheckMTF(ORDER_TYPE_BUY);
         allowSell = g_filterManager.CheckMTF(ORDER_TYPE_SELL);
      }
      
      // Update strategy permissions
      g_strategy.SetAllowedDirections(allowBuy, allowSell);
      g_strategy.OnTick();
   }
}
//+------------------------------------------------------------------+
