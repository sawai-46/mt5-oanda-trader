//+------------------------------------------------------------------+
//|                                           PullbackPresets.mqh    |
//|                        Strategy Presets for Pullback Entry       |
//|              MT4 CommonEA互換・8プリセット完全版                 |
//+------------------------------------------------------------------+
#ifndef __PULLBACK_PRESETS_MQH__
#define __PULLBACK_PRESETS_MQH__

#include <Strategies/Pullback/PullbackConfig.mqh>

//+------------------------------------------------------------------+
//| Apply preset to config                                           |
//+------------------------------------------------------------------+
void ApplyPreset(CPullbackConfig &cfg, ENUM_STRATEGY_PRESET preset)
{
   switch(preset)
   {
      case PRESET_STANDARD:
         // 標準: ローソク足パターンをトリガーとして使用、ADX緩和
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 15.0;  // 緩和: 20→15
         // ATRThresholdPointsは銘柄別で設定されるため変更しない
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters: パターンON
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;   // パターントリガーON
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         break;
         
      case PRESET_CONSERVATIVE:
         // 慎重派: ADX上昇 + Fib + パターン
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 20.0;
         cfg.StopLossFixedPoints = 200.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters
         cfg.ADXRequireRising = true;
         cfg.DISpreadMin = 5.0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = true;
         cfg.FibSwingPeriod = 20;
         cfg.FibMinRatio = 38.2;
         cfg.FibMaxRatio = 61.8;
         cfg.UseCandlePattern = true;   // パターントリガーON
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         break;
         
      case PRESET_AGGRESSIVE:
         // 積極派: ADXなし、パターン重視、ブレイクも許可
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = false;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = true;
         cfg.UseADXFilter = false;  // ADXフィルタOFF
         cfg.ADXMinLevel = 0.0;
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters: パターンとATR傾きON
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = true;
         cfg.ATRSlopeRequireRising = true;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         break;

      case PRESET_AI_SCOUT:
         // スカウト: 最大限緩和、エントリー頻度重視
         cfg.EmaShortPeriod = 8;
         cfg.EmaMidPeriod = 20;
         cfg.EmaLongPeriod = 50;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = false;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = true;
         cfg.UseADXFilter = false;
         cfg.ADXMinLevel = 0.0;
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters: all OFF（最大緩和）
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = false;
         cfg.UseDivergenceFilter = false;
         break;

      case PRESET_AI_ADAPTIVE:
         // AI適応型: パターン + DI差確認
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 18.0;  // やや緩和
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters: DI差 + パターン
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 3.0;  // DI差確認
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         break;

      case PRESET_MULTI_LAYER:
         // マルチレイヤー: 全EMA使用、パターン重視
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = true;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 15.0;
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters: パターンON
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         break;

      case PRESET_SESSION:
         // セッション重視: 時間帯依存（フィルタ軽め）
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 15.0;
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters: パターンのみ
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         break;
         
      case PRESET_FULL_EDGE:
         // フルエッジ: 全フィルタ有効（高精度・低頻度）
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 20.0;
         cfg.StopLossFixedPoints = 200.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters: all ON
         cfg.ADXRequireRising = true;
         cfg.DISpreadMin = 5.0;
         cfg.UseATRSlopeFilter = true;
         cfg.ATRSlopeRequireRising = true;
         cfg.UseFibFilter = true;
         cfg.FibSwingPeriod = 20;
         cfg.FibMinRatio = 38.2;
         cfg.FibMaxRatio = 61.8;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = true;
         break;
         
      case PRESET_CUSTOM:
      default:
         // カスタム: 変更なし
         break;
   }
}

//+------------------------------------------------------------------+
//| Get preset name string                                           |
//+------------------------------------------------------------------+
string GetPresetName(ENUM_STRATEGY_PRESET preset)
{
   switch(preset)
   {
      case PRESET_STANDARD:     return "Standard";
      case PRESET_CONSERVATIVE: return "Conservative";
      case PRESET_AGGRESSIVE:   return "Aggressive";
      case PRESET_AI_SCOUT:     return "AI Scout";
      case PRESET_AI_ADAPTIVE:  return "AI Adaptive";
      case PRESET_MULTI_LAYER:  return "Multi Layer";
      case PRESET_SESSION:      return "Session";
      case PRESET_FULL_EDGE:    return "Full Edge";
      case PRESET_CUSTOM:       return "Custom";
      default:                  return "Unknown";
   }
}

#endif
