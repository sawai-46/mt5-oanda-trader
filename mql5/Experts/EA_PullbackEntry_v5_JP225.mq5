//+------------------------------------------------------------------+
//|                                  EA_PullbackEntry_v5_JP225.mq5   |
//|                    MQL5 OOP Version - Pullback Entry Strategy    |
//|                    日経225専用 単位: 円 (1point=1円)               |
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
input int InpPresetApplyMode = 2;  // Preset適用モード: 0=使わない(Input優先), 1=旧互換(=Preset優先), 2=Preset優先

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
input int    InpMaxSpreadYen = 5;            // 最大スプレッド(円)
input bool   InpUseADXFilter = true;         // ADXフィルター
input int    InpADXPeriod = 14;              // ADX期間
input double InpADXMinLevel = 20.0;          // ADX最小値
input int    InpATRPeriod = 14;              // ATR期間
input double InpATRMinYen = 10.0;            // ATR最小値(円)

//--- SL/TP Settings
input ENUM_SLTP_MODE InpSLTPMode = SLTP_FIXED;  // SL/TPモード
input double InpSLFixedYen = 30.0;           // SL(円) - Fixed
input double InpTPFixedYen = 60.0;           // TP(円) - Fixed
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

//--- Trailing Stop
input ENUM_TRAILING_MODE InpTrailingMode = TRAILING_DISABLED;  // トレーリングモード
input double InpTrailStartYen = 20.0;        // トレーリング開始(円)
input double InpTrailStepYen = 5.0;          // トレーリングステップ(円)

//--- Logging
input bool   InpEnableLogging = true;                 // ログ出力有効
input ENUM_LOG_LEVEL InpLogMinLevel = LOG_INFO;       // 最小ログレベル
input bool   InpLogToFile = true;                     // ファイル出力
input bool   InpLogUseCommonFolder = true;            // Commonフォルダ使用
input string InpLogFileName = "EA_PullbackEntry_v5.log"; // ログファイル名

//--- Data collection (MT4 log sync compatible)
input bool   InpEnableAiLearningCsv = true;                    // AI学習CSV出力（DB同期用）
input string InpTerminalId = "10900k-mt5-index";              // 端末固定ID（例: 10900k-mt5-fx / 10900k-mt5-index）。live/demoは含めない
input string InpAiLearningFolder = "OneDriveLogs\\data\\AI_Learning"; // MQL5/Files配下

//=== GLOBAL OBJECTS ===
CPullbackStrategy *g_strategy = NULL;
CPositionManager  *g_posManager = NULL;
CFilterManager    *g_filterManager = NULL;

// 円→Points変換値（JP225: 1円 = 1point）
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
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][cfg] Filters: MaxSpreadPoints=%d ATR(period=%d min=%s (price units) / %s MT5pt) ADX(en=%s period=%d min=%.1f)",
                                       cfg.MaxSpreadPoints,
                                       cfg.ATRPeriod,
                                       DoubleToString(cfg.ATRThresholdPoints * point, digits),
                                       DoubleToString(cfg.ATRThresholdPoints, 1),
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
   CLogger::Log(LOG_INFO, StringFormat("[CONFIG][PBEv5][filter] Spread(en=%s max=%d) ADX(en=%s period=%d min=%.1f) ATR(en=%s period=%d min=%s (price units) / %s MT5pt)",
                                       BoolStr(filterCfg.EnableSpreadFilter), filterCfg.MaxSpreadPoints,
                                       BoolStr(filterCfg.EnableADXFilter), filterCfg.ADXPeriod, filterCfg.ADXMinLevel,
                                       BoolStr(filterCfg.EnableATRFilter), filterCfg.ATRPeriod,
                                       DoubleToString(filterCfg.ATRMinPoints * point, digits),
                                       DoubleToString(filterCfg.ATRMinPoints, 1)));

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
   string instanceId = "EA_PullbackEntry_v5_JP225|" + _Symbol + "|Magic:" + (string)InpMagicNumber + "|CID:" + (string)ChartID();
   CLogger::Configure(instanceId, InpEnableLogging, InpLogMinLevel, InpLogToFile, InpLogFileName, InpLogUseCommonFolder);

   // 円→Points変換（JP225: 1円 = 1point）
   g_MaxSpreadPoints = InpMaxSpreadYen;        // 円 = points
   g_ATRMinPoints = InpATRMinYen;
   g_SLFixedPoints = InpSLFixedYen;
   g_TPFixedPoints = InpTPFixedYen;
   g_Partial1Points = InpPartial1Yen;
   g_Partial2Points = InpPartial2Yen;
   g_Partial3Points = InpPartial3Yen;
   g_TrailStartPoints = InpTrailStartYen;
   g_TrailStepPoints = InpTrailStepYen;
   
   CLogger::Log(LOG_INFO, StringFormat("★ 円→Points変換: SL=%.1f円→%.0fpts TP=%.1f円→%.0fpts",
                InpSLFixedYen, g_SLFixedPoints, InpTPFixedYen, g_TPFixedPoints));

   CLogger::Log(LOG_INFO, "=== EA_PullbackEntry v5.0 JP225 (MQL5 OOP) ===");
   CLogger::Log(LOG_INFO, "Preset: " + GetPresetName(InpPreset));
   CLogger::Log(LOG_INFO, "Symbol: " + _Symbol);
   CLogger::Log(LOG_INFO, "Magic: " + (string)InpMagicNumber);
   
   // Build Config
   CPullbackConfig cfg;
   SFilterConfig filterCfg;
   SPositionConfig posCfg;

   filterCfg.Symbol = _Symbol;
   posCfg.Symbol = _Symbol;
   
   // Preset適用
   // mode=0: Input優先（.set尊重）
   // mode=1/2: Preset優先（MTF無し前提の推奨値を適用）
   if(InpPresetApplyMode != 0 && InpPreset != PRESET_CUSTOM)
   {
      ApplyPresetAll(cfg, filterCfg, posCfg, InpPreset, 1.0);
      CLogger::Log(LOG_INFO, StringFormat("PresetApplyMode=%d: Preset優先", InpPresetApplyMode));
   }
   else
   {
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
   
   // Input優先 または PRESET_CUSTOM: Inputから戦略パラメータを読み込み
   if(InpPresetApplyMode == 0 || InpPreset == PRESET_CUSTOM)
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
   filterCfg.GMTOffset = InpGMTOffset;
   filterCfg.UseDST = false;

   if(InpPresetApplyMode == 0 || InpPreset == PRESET_CUSTOM)
   {
      filterCfg.EnableTimeFilter = InpEnableTimeFilter;
      filterCfg.StartHour = InpStartHour;
      filterCfg.EndHour = InpEndHour;
      filterCfg.StartMinute = 0;
      filterCfg.EndMinute = 0;
      filterCfg.TradeOnFriday = InpTradeOnFriday;
      filterCfg.EnableSpreadFilter = true;
      filterCfg.MaxSpreadPoints = g_MaxSpreadPoints;
      filterCfg.EnableADXFilter = InpUseADXFilter;
      filterCfg.ADXPeriod = InpADXPeriod;
      filterCfg.ADXMinLevel = InpADXMinLevel;
      filterCfg.EnableATRFilter = true;
      filterCfg.ATRPeriod = InpATRPeriod;
      filterCfg.ATRMinPoints = g_ATRMinPoints;
   }
   
   g_filterManager = new CFilterManager();
   g_filterManager.Init(filterCfg, PERIOD_CURRENT);
   
   // Create Position Manager
   posCfg.MagicNumber = InpMagicNumber;
   posCfg.MaxSlippagePoints = InpDeviationPoints;

   if(InpPresetApplyMode == 0 || InpPreset == PRESET_CUSTOM)
   {
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
   }

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
