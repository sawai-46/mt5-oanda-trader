//+------------------------------------------------------------------+
//|                                EA_PullbackEntry_v5_USIndex.mq5   |
//|                    MQL5 OOP Version - Pullback Entry Strategy    |
//|                    US Index専用 単位: ドル (US30/SPX500/NAS100)     |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "5.00"
#property strict

#include <Trade\Trade.mqh>
#include <Strategies/Pullback/PullbackConfig.mqh>
#include <Strategies/Pullback/PullbackPresets.mqh>
#include <Strategies/Pullback/PullbackStrategy.mqh>
#include <Position/PositionManager.mqh>
#include <Filters/FilterManager.mqh>
#include <Integration/Logger.mqh>

//=== INPUT PARAMETERS ===

//--- Preset Selection
input ENUM_PULLBACK_PRESET InpPreset = PRESET_STANDARD;  // 戦略プリセット
input int InpPresetApplyMode = 1;  // Preset適用モード: 0=使わない(Input優先), 1=未設定のみ補完★推奨, 2=全上書き

//--- Basic Settings
input double InpLotSize = 0.10;              // ロットサイズ
input long   InpMagicNumber = 55000001;      // マジックナンバー
input int    InpDeviationPoints = 50;        // 最大スリッページ(points)

//--- EMA Settings
input int    InpEmaShort = 12;               // 短期EMA
input int    InpEmaMid = 25;                 // 中期EMA
input int    InpEmaLong = 100;               // 長期EMA
input bool   InpRequirePerfectOrder = true;  // パーフェクトオーダー必須

//--- Pullback Settings
input bool   InpUseTouchPullback = true;     // タッチプルバック
input bool   InpUseCrossPullback = true;     // クロスプルバック
input bool   InpUseBreakPullback = false;    // ブレイクプルバック
input ENUM_PULLBACK_EMA_REF InpPullbackEmaRef = PULLBACK_EMA_25;  // プルバック基準EMA

//--- Time Filter (JST)
input bool   InpEnableTimeFilter = true;     // 時間フィルター有効
input int    InpGMTOffset = 3;               // GMTオフセット
input int    InpStartHour = 8;               // 開始時刻(JST)
input int    InpEndHour = 21;                // 終了時刻(JST)
input bool   InpTradeOnFriday = true;        // 金曜取引

//--- Spread/ADX/ATR Filter
input double InpMaxSpreadDollars = 5.0;      // 最大スプレッド(ドル)
input bool   InpUseADXFilter = true;         // ADXフィルター
input int    InpADXPeriod = 14;              // ADX期間
input double InpADXMinLevel = 20.0;          // ADX最小値
input int    InpATRPeriod = 14;              // ATR期間
input double InpATRMinDollars = 5.0;         // ATR最小値(ドル)

//--- SL/TP Settings
input ENUM_SLTP_MODE InpSLTPMode = SLTP_FIXED;  // SL/TPモード
input double InpSLFixedDollars = 50.0;       // SL(ドル) - Fixed
input double InpTPFixedDollars = 100.0;      // TP(ドル) - Fixed
input double InpSLAtrMulti = 1.5;            // SL ATR倍率
input double InpTPAtrMulti = 2.0;            // TP ATR倍率

//--- Partial Close
input bool   InpEnablePartialClose = true;    // 部分決済有効
input int    InpPartialStages = 2;            // 段階数(2/3)
input double InpPartial1Dollars = 15.0;       // 1段階目(ドル)
input double InpPartial1Percent = 50.0;       // 1段階目決済率(%)
input double InpPartial2Dollars = 30.0;       // 2段階目(ドル)
input double InpPartial2Percent = 50.0;       // 2段階目決済率(%)
input double InpPartial3Dollars = 45.0;       // 3段階目(ドル)
input double InpPartial3Percent = 100.0;      // 3段階目決済率(%)
input bool   InpMoveToBreakEven = true;       // Level1後に建値移動
input bool   InpMoveSLAfterLevel2 = true;     // Level2後にSL移動(Level1利益位置へ)

//--- Trailing Stop
input ENUM_TRAILING_MODE InpTrailingMode = TRAILING_DISABLED;  // トレーリングモード
input double InpTrailStartDollars = 20.0;     // トレーリング開始(ドル)
input double InpTrailStepDollars = 5.0;       // トレーリングステップ(ドル)

//--- Logging
input bool   InpEnableLogging = true;                 // ログ出力有効
input ENUM_LOG_LEVEL InpLogMinLevel = LOG_INFO;       // 最小ログレベル
input bool   InpLogToFile = true;                     // ファイル出力
input bool   InpLogUseCommonFolder = true;            // Commonフォルダ使用
input string InpLogFileName = "EA_PullbackEntry_v5.log"; // ログファイル名

//--- Data collection (MT4 log sync compatible)
input bool   InpEnableAiLearningCsv = true;                    // AI学習CSV出力（DB同期用）
input string InpTerminalId = "10900k-mt5-live";               // 端末固定ID（10900k-mt5-live, 10900k-mt5-demo, matsu-mt5-live, matsu-mt5-demo）
input string InpAiLearningFolder = "OneDriveLogs\\data\\AI_Learning"; // MQL5/Files配下

//=== GLOBAL OBJECTS ===
CPullbackStrategy *g_strategy = NULL;
CPositionManager  *g_posManager = NULL;
CFilterManager    *g_filterManager = NULL;

// ドル→Points変換値（US30: 1ドル≈100points）
double g_dollarMultiplier = 100.0;
int    g_MaxSpreadPoints = 0;
double g_ATRMinPoints = 0;
double g_SLFixedPoints = 0;
double g_TPFixedPoints = 0;
double g_Partial1Points = 0;
double g_Partial2Points = 0;
double g_Partial3Points = 0;
double g_TrailStartPoints = 0;
double g_TrailStepPoints = 0;

string BoolStr(const bool v){ return v ? "true" : "false"; }

void DumpEffectiveConfig(const ENUM_PULLBACK_PRESET preset,
                         const CPullbackConfig &cfg,
                         const SFilterConfig &filterCfg,
                         const SPositionConfig &posCfg)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double spreadPrice = spreadPts * point;

   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5] Preset=%s Symbol=%s TF=%s Digits=%d Point=%g Spread=%lld pts (%.5f)",
                                       GetPresetName(preset), _Symbol, EnumToString(PERIOD_CURRENT), digits, point, spreadPts, spreadPrice));

   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][cfg] Magic=%lld Lot=%.2f DeviationPoints=%d",
                                       cfg.MagicNumber, cfg.LotSize, cfg.DeviationPoints));
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][cfg] EMA: short=%d mid=%d long=%d PerfectOrder=%s Pullback(ref=%d touch=%s cross=%s break=%s)",
                                       cfg.EmaShortPeriod, cfg.EmaMidPeriod, cfg.EmaLongPeriod,
                                       BoolStr(cfg.RequirePerfectOrder),
                                       (int)cfg.PullbackEmaRef,
                                       BoolStr(cfg.UseTouchPullback), BoolStr(cfg.UseCrossPullback), BoolStr(cfg.UseBreakPullback)));
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][cfg] Filters: MaxSpreadPoints=%d ATR(period=%d min=%.1f) ADX(en=%s period=%d min=%.1f)",
                                       cfg.MaxSpreadPoints,
                                       cfg.ATRPeriod, cfg.ATRThresholdPoints,
                                       BoolStr(cfg.UseADXFilter), cfg.ADXPeriod, cfg.ADXMinLevel));
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][cfg] SLTP: useSL=%s useTP=%s mode=%d SL_fixed=%.1f TP_fixed=%.1f SL_ATR=%.2f TP_ATR=%.2f",
                                       BoolStr(cfg.UseStopLoss), BoolStr(cfg.UseTakeProfit), (int)cfg.SLTPMode,
                                       cfg.StopLossFixedPoints, cfg.TakeProfitFixedPoints,
                                       cfg.StopLossAtrMulti, cfg.TakeProfitAtrMulti));
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][cfg] AiLearning: enabled=%s terminalId=%s folder=%s",
                                       BoolStr(cfg.EnableAiLearningLog), cfg.TerminalId, cfg.AiLearningFolder));

   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][filter] Time(en=%s GMTOffset=%d Start=%02d:%02d End=%02d:%02d Fri=%s DST=%s)",
                                       BoolStr(filterCfg.EnableTimeFilter),
                                       filterCfg.GMTOffset,
                                       filterCfg.StartHour, filterCfg.StartMinute,
                                       filterCfg.EndHour, filterCfg.EndMinute,
                                       BoolStr(filterCfg.TradeOnFriday), BoolStr(filterCfg.UseDST)));
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][filter] Spread(en=%s max=%d) ADX(en=%s period=%d min=%.1f) ATR(en=%s period=%d min=%.1f)",
                                       BoolStr(filterCfg.EnableSpreadFilter), filterCfg.MaxSpreadPoints,
                                       BoolStr(filterCfg.EnableADXFilter), filterCfg.ADXPeriod, filterCfg.ADXMinLevel,
                                       BoolStr(filterCfg.EnableATRFilter), filterCfg.ATRPeriod, filterCfg.ATRMinPoints));

   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][pos] Partial(en=%s stages=%d L1=%.1f(%.1f%%) L2=%.1f(%.1f%%) L3=%.1f(%.1f%%) BE_after_L1=%s SL_after_L2=%s)",
                                       BoolStr(posCfg.EnablePartialClose), posCfg.PartialCloseStages,
                                       posCfg.PartialClose1Points, posCfg.PartialClose1Percent,
                                       posCfg.PartialClose2Points, posCfg.PartialClose2Percent,
                                       posCfg.PartialClose3Points, posCfg.PartialClose3Percent,
                                       BoolStr(posCfg.MoveToBreakEvenAfterLevel1), BoolStr(posCfg.MoveSLAfterLevel2)));
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][pos] Trailing(mode=%d start=%.1f step=%.1f atrMulti=%.2f atrPeriod=%d) SlippagePoints=%d",
                                       (int)posCfg.TrailingMode,
                                       posCfg.TrailingStartPoints, posCfg.TrailingStepPoints,
                                       posCfg.TrailingATRMulti, posCfg.ATRPeriod,
                                       posCfg.MaxSlippagePoints));
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   string instanceId = "EA_PullbackEntry_v5_USIndex|" + _Symbol + "|Magic:" + (string)InpMagicNumber + "|CID:" + (string)ChartID();
   CLogger::Configure(instanceId, InpEnableLogging, InpLogMinLevel, InpLogToFile, InpLogFileName, InpLogUseCommonFolder);

   // ドル→Points変換（US30: 1ドル ≈ 100points）
   double symbolPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(symbolPoint > 0)
      g_dollarMultiplier = 1.0 / symbolPoint;  // 例: point=0.01 → multiplier=100
   else
      g_dollarMultiplier = 100.0;  // デフォルト
   
   g_MaxSpreadPoints = (int)(InpMaxSpreadDollars * g_dollarMultiplier);
   g_ATRMinPoints = InpATRMinDollars * g_dollarMultiplier;
   g_SLFixedPoints = InpSLFixedDollars * g_dollarMultiplier;
   g_TPFixedPoints = InpTPFixedDollars * g_dollarMultiplier;
   g_Partial1Points = InpPartial1Dollars * g_dollarMultiplier;
   g_Partial2Points = InpPartial2Dollars * g_dollarMultiplier;
   g_Partial3Points = InpPartial3Dollars * g_dollarMultiplier;
   g_TrailStartPoints = InpTrailStartDollars * g_dollarMultiplier;
   g_TrailStepPoints = InpTrailStepDollars * g_dollarMultiplier;
   
   CLogger::Log(LOG_INFO, StringFormat("★ ドル→Points変換: multiplier=%.0f SL=%.1f$→%.0fpts TP=%.1f$→%.0fpts",
                g_dollarMultiplier, InpSLFixedDollars, g_SLFixedPoints, InpTPFixedDollars, g_TPFixedPoints));

   CLogger::Log(LOG_INFO, "=== EA_PullbackEntry v5.0 USIndex (MQL5 OOP) ===");
   CLogger::Log(LOG_INFO, "Preset: " + GetPresetName(InpPreset));
   CLogger::Log(LOG_INFO, "Symbol: " + _Symbol);
   CLogger::Log(LOG_INFO, "Magic: " + (string)InpMagicNumber);
   
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
   cfg.MagicNumber = InpMagicNumber;
   cfg.LotSize = InpLotSize;
   cfg.DeviationPoints = InpDeviationPoints;

   // Data collection
   cfg.EnableAiLearningLog = InpEnableAiLearningCsv;
   cfg.TerminalId = InpTerminalId;
   cfg.AiLearningFolder = InpAiLearningFolder;
   
   // mode=0/1 または PRESET_CUSTOM: Inputから全パラメータを読み込み
   if(InpPresetApplyMode != 2 || InpPreset == PRESET_CUSTOM)
   {
      cfg.EmaShortPeriod = InpEmaShort;
      cfg.EmaMidPeriod = InpEmaMid;
      cfg.EmaLongPeriod = InpEmaLong;
      cfg.RequirePerfectOrder = InpRequirePerfectOrder;
      cfg.UseTouchPullback = InpUseTouchPullback;
      cfg.UseCrossPullback = InpUseCrossPullback;
      cfg.UseBreakPullback = InpUseBreakPullback;
      cfg.PullbackEmaRef = InpPullbackEmaRef;
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
   filterCfg.UseDST = false;
   filterCfg.StartMinute = 0;
   filterCfg.EndMinute = 0;
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
   
   g_filterManager = new CFilterManager();
   g_filterManager.Init(filterCfg, PERIOD_CURRENT);
   
   // Create Position Manager
   SPositionConfig posCfg;
   posCfg.MagicNumber = InpMagicNumber;
   posCfg.Symbol = _Symbol;
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
   posCfg.TrailingMode = InpTrailingMode;
   posCfg.TrailingStartPoints = g_TrailStartPoints;
   posCfg.TrailingStepPoints = g_TrailStepPoints;
   posCfg.TrailingATRMulti = 1.0;
   posCfg.ATRPeriod = InpATRPeriod;
   posCfg.MaxSlippagePoints = InpDeviationPoints;

   DumpEffectiveConfig(InpPreset, cfg, filterCfg, posCfg);
   
   g_posManager = new CPositionManager();
   g_posManager.Init(posCfg);
   
   CLogger::Log(LOG_INFO, "Initialization complete");
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
   // Position management (partial close, trailing)
   if(g_posManager != NULL)
      g_posManager.OnTick();
   
   // Skip if filters fail
   if(g_filterManager != NULL && !g_filterManager.CheckAll())
   {
      if(InpEnableLogging && InpLogMinLevel == LOG_DEBUG)
         CLogger::Log(LOG_DEBUG, "Filter rejected: " + g_filterManager.GetLastRejectReason());
      return;
   }
   
   // Strategy entry logic
   if(g_strategy != NULL)
      g_strategy.OnTick();
}
//+------------------------------------------------------------------+
