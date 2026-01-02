//+------------------------------------------------------------------+
//|                                           PullbackPresets.mqh    |
//|                        Strategy Presets for Pullback Entry       |
//|              STANDARD, CONSERVATIVE, AGGRESSIVE, SCALPING        |
//+------------------------------------------------------------------+
#ifndef __PULLBACK_PRESETS_MQH__
#define __PULLBACK_PRESETS_MQH__

#include <Strategies/Pullback/PullbackConfig.mqh>
#include <Filters/FilterManager.mqh>
#include <Position/PositionManager.mqh>

//--- Strategy Preset Types
enum ENUM_PULLBACK_PRESET
{
   PRESET_STANDARD = 0,        // 標準型 (M15推奨) ★推奨
   PRESET_CONSERVATIVE,        // 保守型 (質重視, M30推奨)
   PRESET_AGGRESSIVE,          // 積極型 (短期・回数重視)
   PRESET_SCALPING,            // スキャルピング (M5/M1, 高頻度)
   PRESET_CUSTOM = 4,          // カスタム（旧互換: 値を固定）

   // 追加プリセット（旧互換を壊さないため、5以降に追加）
   PRESET_TREND_PULLBACK = 5,  // トレンド継続・押し目限定
   PRESET_BREAKOUT_PULLBACK,   // ブレイク後の押し目（再加速狙い）
   PRESET_DEFENSIVE            // 防御特化（回数減らす）
};

//+------------------------------------------------------------------+
//| Apply preset to config                                           |
//+------------------------------------------------------------------+
// unitToPoints:
//  - FX: 1 unit = 1 pip（5桁なら unitToPoints=10）
//  - Indices: 1 unit = 1.0 価格（指数の値幅） → unitToPoints = 1 / SYMBOL_POINT
//    - 例: SYMBOL_POINT=0.01 → unitToPoints=100
//    - 例: SYMBOL_POINT=0.1  → unitToPoints=10
void ApplyPreset(CPullbackConfig &cfg, ENUM_PULLBACK_PRESET preset, const double unitToPoints)
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
         cfg.PullbackEmaRef = PULLBACK_EMA_25;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 20.0;
         cfg.ATRThresholdPoints = 3.0 * unitToPoints;
         cfg.StopLossFixedPoints = 15.0 * unitToPoints;
         cfg.TakeProfitFixedPoints = 30.0 * unitToPoints;
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
         cfg.PullbackEmaRef = PULLBACK_EMA_25;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 25.0;        // 高め
         cfg.ATRThresholdPoints = 4.0 * unitToPoints; // 高め
         cfg.StopLossFixedPoints = 20.0 * unitToPoints;
         cfg.TakeProfitFixedPoints = 40.0 * unitToPoints;
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
         cfg.PullbackEmaRef = PULLBACK_EMA_25;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 15.0;           // 低め
         cfg.ATRThresholdPoints = 2.0 * unitToPoints; // 低め
         cfg.StopLossFixedPoints = 12.0 * unitToPoints;
         cfg.TakeProfitFixedPoints = 24.0 * unitToPoints;
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
         cfg.PullbackEmaRef = PULLBACK_EMA_12;
         cfg.UseADXFilter = false;         // ADX無効
         cfg.ATRThresholdPoints = 1.0 * unitToPoints;
         cfg.StopLossFixedPoints = 6.0 * unitToPoints;
         cfg.TakeProfitFixedPoints = 12.0 * unitToPoints;
         break;

      case PRESET_TREND_PULLBACK:
         // トレンド継続: 伸びる局面だけ狙う（回数は減る）
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.RequirePerfectOrder = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = false;     // ノイズ減
         cfg.UseBreakPullback = false;
         cfg.PullbackEmaRef = PULLBACK_EMA_25;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 22.0;
         cfg.ATRThresholdPoints = 3.5 * unitToPoints;
         cfg.StopLossFixedPoints = 18.0 * unitToPoints;
         cfg.TakeProfitFixedPoints = 45.0 * unitToPoints;
         break;

      case PRESET_BREAKOUT_PULLBACK:
         // ブレイク後の押し: 再加速狙い（トレンド初動飛び乗りを避ける）
         cfg.EmaShortPeriod = 8;
         cfg.EmaMidPeriod = 20;
         cfg.EmaLongPeriod = 100;
         cfg.RequirePerfectOrder = false;
         cfg.UseTouchPullback = false;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = true;
         cfg.PullbackEmaRef = PULLBACK_EMA_12;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 18.0;
         cfg.ATRThresholdPoints = 3.0 * unitToPoints;
         cfg.StopLossFixedPoints = 15.0 * unitToPoints;
         cfg.TakeProfitFixedPoints = 35.0 * unitToPoints;
         break;

      case PRESET_DEFENSIVE:
         // 防御特化: 条件を絞って事故を減らす
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.RequirePerfectOrder = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.PullbackEmaRef = PULLBACK_EMA_25;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 28.0;
         cfg.ATRThresholdPoints = 4.0 * unitToPoints;
         cfg.StopLossFixedPoints = 20.0 * unitToPoints;
         cfg.TakeProfitFixedPoints = 30.0 * unitToPoints;
         break;
         
      case PRESET_CUSTOM:
      default:
         // カスタム: デフォルト値のまま
         break;
   }
}

// 旧互換（過去コード/インクルード向け）
void ApplyPreset(CPullbackConfig &cfg, ENUM_PULLBACK_PRESET preset)
{
   ApplyPreset(cfg, preset, 10.0);
}

// Filter/Position も含めてプリセット適用（EA側で unitToPoints を渡す）
void ApplyPresetAll(CPullbackConfig &cfg, SFilterConfig &filterCfg, SPositionConfig &posCfg,
                    ENUM_PULLBACK_PRESET preset, const double unitToPoints)
{
   ApplyPreset(cfg, preset, unitToPoints);

   // Filters（MTFが無い前提なので、時間/スプレッド/ATR/ADX/チャネル幅で再現）
   switch(preset)
   {
      case PRESET_STANDARD:
         filterCfg.EnableTimeFilter = true;
         filterCfg.StartHour = 8; filterCfg.StartMinute = 0;
         filterCfg.EndHour = 21;  filterCfg.EndMinute = 0;
         filterCfg.TradeOnFriday = true;
         filterCfg.EnableSpreadFilter = true;
         filterCfg.EnableATRFilter = true;
         filterCfg.EnableADXFilter = true;
         filterCfg.EnableChannelFilter = false;
         filterCfg.ADXMinLevel = 20.0;
         filterCfg.ATRMinPoints = 3.0 * unitToPoints;
         break;

      case PRESET_CONSERVATIVE:
         filterCfg.EnableTimeFilter = true;
         filterCfg.StartHour = 9; filterCfg.StartMinute = 0;
         filterCfg.EndHour = 20;  filterCfg.EndMinute = 0;
         filterCfg.TradeOnFriday = false;
         filterCfg.EnableSpreadFilter = true;
         filterCfg.EnableATRFilter = true;
         filterCfg.EnableADXFilter = true;
         filterCfg.EnableChannelFilter = true;
         filterCfg.ADXMinLevel = 25.0;
         filterCfg.ATRMinPoints = 4.0 * unitToPoints;
         filterCfg.MinChannelWidthPoints = 10.0 * unitToPoints;
         break;

      case PRESET_AGGRESSIVE:
         filterCfg.EnableTimeFilter = true;
         filterCfg.StartHour = 7; filterCfg.StartMinute = 0;
         filterCfg.EndHour = 22;  filterCfg.EndMinute = 0;
         filterCfg.TradeOnFriday = true;
         filterCfg.EnableSpreadFilter = true;
         filterCfg.EnableATRFilter = true;
         filterCfg.EnableADXFilter = true;
         filterCfg.EnableChannelFilter = false;
         filterCfg.ADXMinLevel = 15.0;
         filterCfg.ATRMinPoints = 2.0 * unitToPoints;
         break;

      case PRESET_SCALPING:
         filterCfg.EnableTimeFilter = true;
         filterCfg.StartHour = 9; filterCfg.StartMinute = 0;
         filterCfg.EndHour = 18;  filterCfg.EndMinute = 0;
         filterCfg.TradeOnFriday = true;
         filterCfg.EnableSpreadFilter = true;
         filterCfg.EnableATRFilter = true;
         filterCfg.EnableADXFilter = false;
         filterCfg.EnableChannelFilter = false;
         filterCfg.ATRMinPoints = 1.0 * unitToPoints;
         break;

      case PRESET_TREND_PULLBACK:
         filterCfg.EnableTimeFilter = true;
         filterCfg.StartHour = 9; filterCfg.StartMinute = 0;
         filterCfg.EndHour = 21;  filterCfg.EndMinute = 0;
         filterCfg.TradeOnFriday = true;
         filterCfg.EnableSpreadFilter = true;
         filterCfg.EnableATRFilter = true;
         filterCfg.EnableADXFilter = true;
         filterCfg.EnableChannelFilter = true;
         filterCfg.ADXMinLevel = 22.0;
         filterCfg.ATRMinPoints = 3.5 * unitToPoints;
         filterCfg.MinChannelWidthPoints = 12.0 * unitToPoints;
         break;

      case PRESET_BREAKOUT_PULLBACK:
         filterCfg.EnableTimeFilter = true;
         filterCfg.StartHour = 8; filterCfg.StartMinute = 0;
         filterCfg.EndHour = 22;  filterCfg.EndMinute = 0;
         filterCfg.TradeOnFriday = true;
         filterCfg.EnableSpreadFilter = true;
         filterCfg.EnableATRFilter = true;
         filterCfg.EnableADXFilter = true;
         filterCfg.EnableChannelFilter = true;
         filterCfg.ADXMinLevel = 18.0;
         filterCfg.ATRMinPoints = 3.0 * unitToPoints;
         filterCfg.MinChannelWidthPoints = 10.0 * unitToPoints;
         break;

      case PRESET_DEFENSIVE:
         filterCfg.EnableTimeFilter = true;
         filterCfg.StartHour = 9; filterCfg.StartMinute = 0;
         filterCfg.EndHour = 20;  filterCfg.EndMinute = 0;
         filterCfg.TradeOnFriday = false;
         filterCfg.EnableSpreadFilter = true;
         filterCfg.EnableATRFilter = true;
         filterCfg.EnableADXFilter = true;
         filterCfg.EnableChannelFilter = true;
         filterCfg.ADXMinLevel = 28.0;
         filterCfg.ATRMinPoints = 4.0 * unitToPoints;
         filterCfg.MinChannelWidthPoints = 12.0 * unitToPoints;
         break;

      case PRESET_CUSTOM:
      default:
         break;
   }

   // Position management（部分利確/BEをベースに、トレーリングは抑えめ）
   switch(preset)
   {
      case PRESET_STANDARD:
         posCfg.EnablePartialClose = true;
         posCfg.PartialCloseStages = 2;
         posCfg.PartialClose1Points = 15.0 * unitToPoints;
         posCfg.PartialClose1Percent = 50.0;
         posCfg.PartialClose2Points = 30.0 * unitToPoints;
         posCfg.PartialClose2Percent = 100.0;
         posCfg.MoveToBreakEvenAfterLevel1 = true;
         posCfg.MoveSLAfterLevel2 = true;
         posCfg.TrailingMode = TRAILING_DISABLED;
         break;

      case PRESET_CONSERVATIVE:
         posCfg.EnablePartialClose = true;
         posCfg.PartialCloseStages = 2;
         posCfg.PartialClose1Points = 20.0 * unitToPoints;
         posCfg.PartialClose1Percent = 50.0;
         posCfg.PartialClose2Points = 40.0 * unitToPoints;
         posCfg.PartialClose2Percent = 100.0;
         posCfg.MoveToBreakEvenAfterLevel1 = true;
         posCfg.MoveSLAfterLevel2 = true;
         posCfg.TrailingMode = TRAILING_DISABLED;
         break;

      case PRESET_AGGRESSIVE:
         posCfg.EnablePartialClose = true;
         posCfg.PartialCloseStages = 2;
         posCfg.PartialClose1Points = 12.0 * unitToPoints;
         posCfg.PartialClose1Percent = 50.0;
         posCfg.PartialClose2Points = 24.0 * unitToPoints;
         posCfg.PartialClose2Percent = 100.0;
         posCfg.MoveToBreakEvenAfterLevel1 = true;
         posCfg.MoveSLAfterLevel2 = true;
         posCfg.TrailingMode = TRAILING_DISABLED;
         break;

      case PRESET_SCALPING:
         posCfg.EnablePartialClose = true;
         posCfg.PartialCloseStages = 2;
         posCfg.PartialClose1Points = 6.0 * unitToPoints;
         posCfg.PartialClose1Percent = 60.0;
         posCfg.PartialClose2Points = 12.0 * unitToPoints;
         posCfg.PartialClose2Percent = 100.0;
         posCfg.MoveToBreakEvenAfterLevel1 = true;
         posCfg.MoveSLAfterLevel2 = false;
         posCfg.TrailingMode = TRAILING_DISABLED;
         break;

      case PRESET_TREND_PULLBACK:
         posCfg.EnablePartialClose = true;
         posCfg.PartialCloseStages = 3;
         posCfg.PartialClose1Points = 18.0 * unitToPoints;
         posCfg.PartialClose1Percent = 40.0;
         posCfg.PartialClose2Points = 30.0 * unitToPoints;
         posCfg.PartialClose2Percent = 40.0;
         posCfg.PartialClose3Points = 45.0 * unitToPoints;
         posCfg.PartialClose3Percent = 100.0;
         posCfg.MoveToBreakEvenAfterLevel1 = true;
         posCfg.MoveSLAfterLevel2 = true;
         posCfg.TrailingMode = TRAILING_DISABLED;
         break;

      case PRESET_BREAKOUT_PULLBACK:
         posCfg.EnablePartialClose = true;
         posCfg.PartialCloseStages = 2;
         posCfg.PartialClose1Points = 15.0 * unitToPoints;
         posCfg.PartialClose1Percent = 50.0;
         posCfg.PartialClose2Points = 35.0 * unitToPoints;
         posCfg.PartialClose2Percent = 100.0;
         posCfg.MoveToBreakEvenAfterLevel1 = true;
         posCfg.MoveSLAfterLevel2 = true;
         posCfg.TrailingMode = TRAILING_DISABLED;
         break;

      case PRESET_DEFENSIVE:
         posCfg.EnablePartialClose = true;
         posCfg.PartialCloseStages = 2;
         posCfg.PartialClose1Points = 15.0 * unitToPoints;
         posCfg.PartialClose1Percent = 60.0;
         posCfg.PartialClose2Points = 30.0 * unitToPoints;
         posCfg.PartialClose2Percent = 100.0;
         posCfg.MoveToBreakEvenAfterLevel1 = true;
         posCfg.MoveSLAfterLevel2 = false;
         posCfg.TrailingMode = TRAILING_DISABLED;
         break;

      case PRESET_CUSTOM:
      default:
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
      case PRESET_TREND_PULLBACK:    return "TrendPullback";
      case PRESET_BREAKOUT_PULLBACK: return "BreakoutPullback";
      case PRESET_DEFENSIVE:         return "Defensive";
      default:                  return "Unknown";
   }
}

#endif
