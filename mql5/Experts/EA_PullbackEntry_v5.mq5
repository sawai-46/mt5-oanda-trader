//+------------------------------------------------------------------+
//|                                      EA_PullbackEntry_v5.mq5     |
//|                    MQL5 OOP Version - Pullback Entry Strategy    |
//|                    Integrated with CPositionManager, CFilters    |
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

//=== INPUT PARAMETERS ===

//--- Preset Selection
input ENUM_PULLBACK_PRESET InpPreset = PRESET_STANDARD;  // 戦略プリセット

//--- Basic Settings
input double InpLotSize = 0.10;              // ロットサイズ
input ulong  InpMagicNumber = 55000001;      // マジックナンバー
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
input int    InpMaxSpreadPoints = 200;       // 最大スプレッド(points)
input bool   InpUseADXFilter = true;         // ADXフィルター
input int    InpADXPeriod = 14;              // ADX期間
input double InpADXMinLevel = 20.0;          // ADX最小値
input int    InpATRPeriod = 14;              // ATR期間
input double InpATRMinPoints = 30.0;         // ATR最小値(points)

//--- SL/TP Settings
input ENUM_SLTP_MODE InpSLTPMode = SLTP_FIXED;  // SL/TPモード
input double InpSLFixedPoints = 150.0;       // SL(points) - Fixed
input double InpTPFixedPoints = 300.0;       // TP(points) - Fixed
input double InpSLAtrMulti = 1.5;            // SL ATR倍率
input double InpTPAtrMulti = 2.0;            // TP ATR倍率

//--- Partial Close
input bool   InpEnablePartialClose = true;   // 部分決済有効
input int    InpPartialStages = 2;           // 段階数(2/3)
input double InpPartial1Points = 150.0;      // 1段階目(points)
input double InpPartial1Percent = 50.0;      // 1段階目決済率(%)
input double InpPartial2Points = 300.0;      // 2段階目(points)
input double InpPartial2Percent = 100.0;     // 2段階目決済率(%)
input bool   InpMoveToBreakEven = true;      // Level1後に建値移動

//--- Trailing Stop
input ENUM_TRAILING_MODE InpTrailingMode = TRAILING_DISABLED;  // トレーリングモード
input double InpTrailStartPoints = 200.0;    // トレーリング開始(points)
input double InpTrailStepPoints = 50.0;      // トレーリングステップ(points)

//=== GLOBAL OBJECTS ===
CPullbackStrategy *g_strategy = NULL;
CPositionManager  *g_posManager = NULL;
CFilterManager    *g_filterManager = NULL;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== EA_PullbackEntry v5.0 (MQL5 OOP) ===");
   Print("Preset: ", GetPresetName(InpPreset));
   Print("Symbol: ", _Symbol);
   Print("Magic: ", InpMagicNumber);
   
   // Build Config
   CPullbackConfig cfg;
   
   // Apply preset first
   ApplyPreset(cfg, InpPreset);
   
   // Override with input parameters if CUSTOM or user wants to fine-tune
   cfg.MagicNumber = InpMagicNumber;
   cfg.LotSize = InpLotSize;
   cfg.DeviationPoints = InpDeviationPoints;
   
   if(InpPreset == PRESET_CUSTOM)
   {
      cfg.EmaShortPeriod = InpEmaShort;
      cfg.EmaMidPeriod = InpEmaMid;
      cfg.EmaLongPeriod = InpEmaLong;
      cfg.RequirePerfectOrder = InpRequirePerfectOrder;
      cfg.UseTouchPullback = InpUseTouchPullback;
      cfg.UseCrossPullback = InpUseCrossPullback;
      cfg.UseBreakPullback = InpUseBreakPullback;
      cfg.PullbackEmaRef = InpPullbackEmaRef;
      cfg.MaxSpreadPoints = InpMaxSpreadPoints;
      cfg.UseADXFilter = InpUseADXFilter;
      cfg.ADXPeriod = InpADXPeriod;
      cfg.ADXMinLevel = InpADXMinLevel;
      cfg.ATRPeriod = InpATRPeriod;
      cfg.ATRThresholdPoints = InpATRMinPoints;
      cfg.SLTPMode = InpSLTPMode;
      cfg.StopLossFixedPoints = InpSLFixedPoints;
      cfg.TakeProfitFixedPoints = InpTPFixedPoints;
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
   filterCfg.StartHour = InpStartHour;
   filterCfg.EndHour = InpEndHour;
   filterCfg.TradeOnFriday = InpTradeOnFriday;
   filterCfg.EnableSpreadFilter = true;
   filterCfg.MaxSpreadPoints = InpMaxSpreadPoints;
   filterCfg.EnableADXFilter = InpUseADXFilter;
   filterCfg.ADXPeriod = InpADXPeriod;
   filterCfg.ADXMinLevel = InpADXMinLevel;
   filterCfg.EnableATRFilter = true;
   filterCfg.ATRPeriod = InpATRPeriod;
   filterCfg.ATRMinPoints = InpATRMinPoints;
   
   g_filterManager = new CFilterManager();
   g_filterManager.Init(filterCfg, PERIOD_CURRENT);
   
   // Create Position Manager
   SPositionConfig posCfg;
   posCfg.MagicNumber = InpMagicNumber;
   posCfg.Symbol = _Symbol;
   posCfg.EnablePartialClose = InpEnablePartialClose;
   posCfg.PartialCloseStages = InpPartialStages;
   posCfg.PartialClose1Points = InpPartial1Points;
   posCfg.PartialClose1Percent = InpPartial1Percent;
   posCfg.PartialClose2Points = InpPartial2Points;
   posCfg.PartialClose2Percent = InpPartial2Percent;
   posCfg.MoveToBreakEvenAfterLevel1 = InpMoveToBreakEven;
   posCfg.TrailingMode = InpTrailingMode;
   posCfg.TrailingStartPoints = InpTrailStartPoints;
   posCfg.TrailingStepPoints = InpTrailStepPoints;
   posCfg.MaxSlippagePoints = InpDeviationPoints;
   
   g_posManager = new CPositionManager();
   g_posManager.Init(posCfg);
   
   Print("Initialization complete");
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
   
   Print("EA_PullbackEntry deinitialized - reason: ", reason);
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
      // Optionally log rejection reason
      // Print("Filter rejected: ", g_filterManager.GetLastRejectReason());
      return;
   }
   
   // Strategy entry logic
   if(g_strategy != NULL)
      g_strategy.OnTick();
}
//+------------------------------------------------------------------+
