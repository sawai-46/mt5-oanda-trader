//+------------------------------------------------------------------+
//|                                           PullbackPresets.mqh    |
//|                        Strategy Presets for Pullback Entry       |
//|              MT4互換・TrendLine/Channel/AIノイズ対策対応          |
//+------------------------------------------------------------------+
#ifndef __PULLBACK_PRESETS_MQH__
#define __PULLBACK_PRESETS_MQH__

#include <Strategies/Pullback/PullbackConfig.mqh>

//+------------------------------------------------------------------+
//| 共通デフォルト設定を適用                                          |
//+------------------------------------------------------------------+
void ApplyCommonDefaults(CPullbackConfig &cfg)
{
   // TrendLine/Channelモード: デフォルトはEMAのみ
   cfg.TLChannelMode = MODE_EMA_ONLY;
   
   // TrendLine設定
   cfg.TrendLineLookbackBars = 100;
   cfg.TrendLineMinTouches = 2;
   cfg.TrendLineTolerancePoints = 20;
   cfg.TrendLineAutoUpdate = true;
   
   // Channel設定
   cfg.ChannelReversalOnly = true;
   cfg.ChannelMinWidthPoints = 50;
   cfg.ChannelMaxWidthPoints = 500;
   cfg.ChannelRequireParallel = true;
   cfg.ChannelParallelTolerance = 0.0005;
   
   // AIノイズ対策: デフォルトOFF
   cfg.UseATRSpikeFilter = false;
   cfg.ATRSpikeMultiplier = 2.0;
   cfg.ATRSpikeAvgBars = 20;
   cfg.ATRSpikeWaitBars = 3;
   
   cfg.UseSecondWaveEntry = false;
   cfg.SecondWaveMinBars = 5;
   cfg.SecondWaveMaxBars = 20;
   
   cfg.UsePostStopHuntEntry = false;
   cfg.StopHuntSpikePoints = 30;
   cfg.StopHuntRecoveryBars = 5;
}

//+------------------------------------------------------------------+
//| Apply preset to config                                           |
//+------------------------------------------------------------------+
void ApplyPreset(CPullbackConfig &cfg, ENUM_STRATEGY_PRESET preset)
{
   // 共通デフォルトを先に適用
   ApplyCommonDefaults(cfg);
   
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
         cfg.ADXMinLevel = 15.0;
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
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
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         // AIノイズ対策: ATRスパイク有効（慎重派向け）
         cfg.UseATRSpikeFilter = true;
         cfg.ATRSpikeMultiplier = 2.0;
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
         cfg.UseADXFilter = false;
         cfg.ADXMinLevel = 0.0;
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters
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
         // Edge filters: all OFF
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
         cfg.ADXMinLevel = 18.0;
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 3.0;
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
         // Edge filters
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
         // Edge filters
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
         // AIノイズ対策: 全有効
         cfg.UseATRSpikeFilter = true;
         cfg.UseSecondWaveEntry = true;
         cfg.UsePostStopHuntEntry = true;
         break;
         
      //=================================================================
      // 新プリセット: TrendLine/Channel/AIノイズ対策
      //=================================================================
      
      case PRESET_TRENDLINE:
         // トレンドライン追従型: 設計書Section12準拠
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
         // Edge filters
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         // === TrendLineモード有効 ===
         cfg.TLChannelMode = MODE_TRENDLINE_TREND;
         cfg.TrendLineLookbackBars = 100;
         cfg.TrendLineMinTouches = 2;
         cfg.TrendLineTolerancePoints = 20;
         cfg.TrendLineAutoUpdate = true;
         // AIノイズ対策: ATRスパイクのみ
         cfg.UseATRSpikeFilter = true;
         break;
         
      case PRESET_CHANNEL:
         // チャネル逆張り型: 設計書Section13準拠
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;  // チャネルではブレイクは危険
         cfg.UseADXFilter = false;  // レンジ相場なのでADX不要
         cfg.ADXMinLevel = 0.0;
         cfg.StopLossFixedPoints = 100.0;  // チャネル幅に応じて調整
         cfg.TakeProfitFixedPoints = 200.0;
         // Edge filters: パターン重視
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         // === Channelモード有効 ===
         cfg.TLChannelMode = MODE_CHANNEL_RANGE;
         cfg.TrendLineLookbackBars = 80;  // チャネルは短めのルックバック
         cfg.ChannelReversalOnly = true;
         cfg.ChannelMinWidthPoints = 50;
         cfg.ChannelMaxWidthPoints = 400;
         cfg.ChannelRequireParallel = true;
         cfg.ChannelParallelTolerance = 0.0005;
         // AIノイズ対策: ストップ狩り検出有効（逆張りに有効）
         cfg.UseATRSpikeFilter = true;
         cfg.UsePostStopHuntEntry = true;
         cfg.StopHuntSpikePoints = 30;
         cfg.StopHuntRecoveryBars = 5;
         break;
         
      case PRESET_AI_NOISE:
         // AIノイズ対策型: AI_MARKET_TRANSFORMATION.md準拠
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
         cfg.ADXMinLevel = 18.0;
         cfg.StopLossFixedPoints = 200.0;  // ノイズ対策で広めに
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters
         cfg.ADXRequireRising = true;
         cfg.DISpreadMin = 3.0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = true;
         cfg.FibSwingPeriod = 20;
         cfg.FibMinRatio = 38.2;
         cfg.FibMaxRatio = 61.8;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         // === AIノイズ対策: 全有効 ===
         cfg.UseATRSpikeFilter = true;
         cfg.ATRSpikeMultiplier = 2.0;
         cfg.ATRSpikeAvgBars = 20;
         cfg.ATRSpikeWaitBars = 3;
         cfg.UseSecondWaveEntry = true;
         cfg.SecondWaveMinBars = 5;
         cfg.SecondWaveMaxBars = 20;
         cfg.UsePostStopHuntEntry = true;
         cfg.StopHuntSpikePoints = 30;
         cfg.StopHuntRecoveryBars = 5;
         break;
         
      case PRESET_CUSTOM:
      default:
         // カスタム: 共通デフォルトのみ（個別設定はユーザー任せ）
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
      case PRESET_TRENDLINE:    return "TrendLine";
      case PRESET_CHANNEL:      return "Channel";
      case PRESET_AI_NOISE:     return "AI Noise";
      case PRESET_CUSTOM:       return "Custom";
      default:                  return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| プリセット説明を取得                                              |
//+------------------------------------------------------------------+
string GetPresetDescription(ENUM_STRATEGY_PRESET preset)
{
   switch(preset)
   {
      case PRESET_STANDARD:
         return "標準型: EMAプルバック + ローソク足パターン、ADX15以上";
      case PRESET_CONSERVATIVE:
         return "保守型: ADX上昇必須 + Fib38-61% + ATRスパイクフィルター";
      case PRESET_AGGRESSIVE:
         return "積極型: ADXなし、全プルバックタイプ許可、ATR傾き確認";
      case PRESET_AI_ADAPTIVE:
         return "AI適応型: DI差確認 + パターン検出";
      case PRESET_AI_SCOUT:
         return "AIスカウト型: 最大緩和、高頻度エントリー用";
      case PRESET_MULTI_LAYER:
         return "マルチレイヤー型: 全EMA使用、全プルバックタイプ";
      case PRESET_SESSION:
         return "セッション型: ロンドン/NY時間帯重視";
      case PRESET_FULL_EDGE:
         return "フルエッジ型: 全フィルタ有効、高精度・低頻度";
      case PRESET_TRENDLINE:
         return "トレンドライン型: 自動TL検出、トレンド追従";
      case PRESET_CHANNEL:
         return "チャネル型: 自動チャネル検出、境界逆張り";
      case PRESET_AI_NOISE:
         return "AIノイズ対策型: ATRスパイク/2度目狙い/ストップ狩り検出";
      case PRESET_CUSTOM:
         return "カスタム: 全パラメータ手動設定";
      default:
         return "不明なプリセット";
   }
}

#endif
