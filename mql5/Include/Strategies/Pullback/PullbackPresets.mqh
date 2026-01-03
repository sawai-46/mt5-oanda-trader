//+------------------------------------------------------------------+
//|                                           PullbackPresets.mqh    |
//|                        Strategy Presets for Pullback Entry       |
//|              STANDARD, CONSERVATIVE, AGGRESSIVE, SCALPING        |
//+------------------------------------------------------------------+
#ifndef __PULLBACK_PRESETS_MQH__
#define __PULLBACK_PRESETS_MQH__

#include <Strategies/Pullback/PullbackConfig.mqh>

//--- Strategy Preset Types
enum ENUM_PULLBACK_PRESET
{
   PRESET_STANDARD = 0,        // 標準型 (M15推奨) ★推奨
   PRESET_CONSERVATIVE,        // 保守型 (質重視, M30推奨)
   PRESET_AGGRESSIVE,          // 積極型 (短期・回数重視)
   PRESET_SCALPING,            // スキャルピング (M5/M1, 高頻度)
   PRESET_CUSTOM               // カスタム
};

//+------------------------------------------------------------------+
//| Apply preset to config                                           |
//+------------------------------------------------------------------+
void ApplyPreset(CPullbackConfig &cfg, ENUM_PULLBACK_PRESET preset)
{
   switch(preset)
   {
      case PRESET_STANDARD:
         // 標準型: バランス重視、M15推奨
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.RequirePerfectOrder = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 20.0;
         cfg.ATRThresholdPoints = 30.0;
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 300.0;
         break;
         
      case PRESET_CONSERVATIVE:
         // 保守型: 厳しめフィルター、質重視
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.RequirePerfectOrder = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 25.0;        // 高め
         cfg.ATRThresholdPoints = 40.0; // 高め
         cfg.StopLossFixedPoints = 200.0;
         cfg.TakeProfitFixedPoints = 400.0;
         break;
         
      case PRESET_AGGRESSIVE:
         // 積極型: 緩めフィルター、回数重視
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.RequirePerfectOrder = false;  // パーフェクトオーダー不要
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = true;      // ブレイクも許可
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 15.0;           // 低め
         cfg.ATRThresholdPoints = 20.0;    // 低め
         cfg.StopLossFixedPoints = 100.0;
         cfg.TakeProfitFixedPoints = 200.0;
         break;
         
      case PRESET_SCALPING:
         // スキャルピング: M5/M1、高頻度、狭いSL/TP
         cfg.EmaShortPeriod = 8;
         cfg.EmaMidPeriod = 20;
         cfg.EmaLongPeriod = 50;
         cfg.RequirePerfectOrder = false;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = true;
         cfg.UseADXFilter = false;         // ADX無効
         cfg.ATRThresholdPoints = 10.0;
         cfg.StopLossFixedPoints = 50.0;
         cfg.TakeProfitFixedPoints = 100.0;
         break;
         
      case PRESET_CUSTOM:
      default:
         // カスタム: デフォルト値のまま
         break;
   }
}

//+------------------------------------------------------------------+
//| Get preset name string                                           |
//+------------------------------------------------------------------+
string GetPresetName(ENUM_PULLBACK_PRESET preset)
{
   switch(preset)
   {
      case PRESET_STANDARD:     return "Standard";
      case PRESET_CONSERVATIVE: return "Conservative";
      case PRESET_AGGRESSIVE:   return "Aggressive";
      case PRESET_SCALPING:     return "Scalping";
      case PRESET_CUSTOM:       return "Custom";
      default:                  return "Unknown";
   }
}

#endif
