//+------------------------------------------------------------------+
//|                                                   MT5_AI_Trader  |
//|                               MT5 Pullback Entry (minimal OOP)   |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1"

#include <Strategies/Pullback/PullbackStrategy.mqh>

//--- Inputs (Points単位: OANDA MT5)
input long   InpMagicNumber           = 22501;
input double InpLotSize               = 0.10;
input int    InpDeviationPoints       = 10;

input int    InpEmaShortPeriod        = 12;
input int    InpEmaMidPeriod          = 25;
input int    InpEmaLongPeriod         = 100;
input bool   InpRequirePerfectOrder   = true;

input bool   InpUseTouchPullback      = true;
input bool   InpUseCrossPullback      = true;
input bool   InpUseBreakPullback      = false;
input ENUM_PULLBACK_EMA_REF InpPullbackEmaRef = PULLBACK_EMA_25;

input int    InpMaxSpreadPoints       = 200;
input int    InpATRPeriod             = 14;
input double InpATRThresholdPoints    = 30.0;
input bool   InpUseADXFilter          = true;
input int    InpADXPeriod             = 14;
input double InpADXMinLevel           = 20.0;

input bool   InpUseStopLoss           = true;
input bool   InpUseTakeProfit         = true;
input ENUM_SLTP_MODE InpSLTPMode      = SLTP_FIXED;
input double InpStopLossFixedPoints   = 150.0;
input double InpTakeProfitFixedPoints = 300.0;
input double InpStopLossAtrMulti      = 1.5;
input double InpTakeProfitAtrMulti    = 2.0;

CPullbackStrategy *g_strategy = NULL;

int OnInit()
{
   CPullbackConfig cfg;
   cfg.MagicNumber = InpMagicNumber;
   cfg.LotSize = InpLotSize;
   cfg.DeviationPoints = InpDeviationPoints;

   cfg.EmaShortPeriod = InpEmaShortPeriod;
   cfg.EmaMidPeriod   = InpEmaMidPeriod;
   cfg.EmaLongPeriod  = InpEmaLongPeriod;
   cfg.RequirePerfectOrder = InpRequirePerfectOrder;

   cfg.UseTouchPullback = InpUseTouchPullback;
   cfg.UseCrossPullback = InpUseCrossPullback;
   cfg.UseBreakPullback = InpUseBreakPullback;
   cfg.PullbackEmaRef   = InpPullbackEmaRef;

   cfg.MaxSpreadPoints = InpMaxSpreadPoints;
   cfg.ATRPeriod = InpATRPeriod;
   cfg.ATRThresholdPoints = InpATRThresholdPoints;
   cfg.UseADXFilter = InpUseADXFilter;
   cfg.ADXPeriod = InpADXPeriod;
   cfg.ADXMinLevel = InpADXMinLevel;

   cfg.UseStopLoss = InpUseStopLoss;
   cfg.UseTakeProfit = InpUseTakeProfit;
   cfg.SLTPMode = InpSLTPMode;
   cfg.StopLossFixedPoints = InpStopLossFixedPoints;
   cfg.TakeProfitFixedPoints = InpTakeProfitFixedPoints;
   cfg.StopLossAtrMulti = InpStopLossAtrMulti;
   cfg.TakeProfitAtrMulti = InpTakeProfitAtrMulti;

   g_strategy = new CPullbackStrategy(_Symbol, (ENUM_TIMEFRAMES)_Period, cfg);
   if(CheckPointer(g_strategy) != POINTER_DYNAMIC)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(CheckPointer(g_strategy) == POINTER_DYNAMIC)
   {
      delete g_strategy;
      g_strategy = NULL;
   }
}

void OnTick()
{
   if(CheckPointer(g_strategy) == POINTER_DYNAMIC)
      g_strategy.OnTick();
}
