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
         
      //=================================================================
      // 新プリセット: 用途別・戦略別
      //=================================================================
      
      case PRESET_SCALPING:
         // スキャルピング型: M5/M15、狭いSL/TP、高頻度
         cfg.EmaShortPeriod = 8;
         cfg.EmaMidPeriod = 20;
         cfg.EmaLongPeriod = 50;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = false;  // 短期なのでEMA100不要
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = true;  // ブレイクも狙う
         cfg.UseADXFilter = false;  // フィルタ少なめで頻度重視
         cfg.ADXMinLevel = 0.0;
         cfg.StopLossFixedPoints = 80.0;   // 狭いSL
         cfg.TakeProfitFixedPoints = 120.0; // 狭いTP (RR 1:1.5)
         // Edge filters: 最小限
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;  // パターンのみ
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = false;
         cfg.UseDivergenceFilter = false;
         // 段階利確: 素早く利確
         cfg.EnablePartialClose = true;
         cfg.PartialCloseLevel1Pips = 6.0;
         cfg.PartialClosePercent1 = 50.0;
         cfg.PartialCloseLevel2Pips = 10.0;
         cfg.PartialClosePercent2 = 50.0;
         cfg.MoveToBreakEvenAfterStage1 = true;
         break;
         
      case PRESET_SWING:
         // スイング型: H1/H4、広いSL/TP、低頻度・高精度
         cfg.EmaShortPeriod = 20;
         cfg.EmaMidPeriod = 50;
         cfg.EmaLongPeriod = 200;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = true;
         cfg.UseBreakPullback = false;
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 20.0;
         cfg.StopLossFixedPoints = 300.0;   // 広いSL
         cfg.TakeProfitFixedPoints = 600.0; // 広いTP (RR 1:2)
         // Edge filters: 厳格
         cfg.ADXRequireRising = true;
         cfg.DISpreadMin = 5.0;
         cfg.UseATRSlopeFilter = true;
         cfg.ATRSlopeRequireRising = true;
         cfg.UseFibFilter = true;
         cfg.FibSwingPeriod = 30;
         cfg.FibMinRatio = 38.2;
         cfg.FibMaxRatio = 61.8;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = true;
         // 段階利確: ゆっくり利確
         cfg.EnablePartialClose = true;
         cfg.PartialCloseLevel1Pips = 30.0;
         cfg.PartialClosePercent1 = 30.0;
         cfg.PartialCloseLevel2Pips = 50.0;
         cfg.PartialClosePercent2 = 40.0;
         cfg.PartialCloseLevel3Pips = 70.0;
         cfg.PartialClosePercent3 = 30.0;
         cfg.MoveToBreakEvenAfterStage1 = true;
         // トレーリング有効
         cfg.TrailingMode = TRAILING_FIXED;
         cfg.TrailingStopPips = 25.0;
         cfg.TrailingActivationPips = 40.0;
         break;
         
      case PRESET_ROUND_NUMBER:
         // ラウンドナンバー重視型: .00/.50レベルを活用
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
         cfg.TakeProfitFixedPoints = 300.0;
         // Edge filters
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         // === ラウンドナンバー機能有効 ===
         cfg.UseRoundNumberLines = true;
         cfg.RN_Use_00_Line = true;
         cfg.RN_Use_50_Line = true;
         cfg.RN_TouchBufferPoints = 100;
         cfg.RN_LookbackBars = 5;
         cfg.RN_CounterTrend = false;
         cfg.RN_DigitLevel = 2;
         cfg.RN_AvoidEntryNear = true;
         cfg.RN_AvoidBufferPoints = 50;
         break;
         
      case PRESET_STRONG_TREND:
         // 強トレンド型: Al Brooks理論、連続バー・浅いプルバック
         cfg.EmaShortPeriod = 12;
         cfg.EmaMidPeriod = 25;
         cfg.EmaLongPeriod = 100;
         cfg.UseEmaShort = true;
         cfg.UseEmaMid = true;
         cfg.UseEmaLong = true;
         cfg.UseTouchPullback = true;
         cfg.UseCrossPullback = false;  // 強トレンドではタッチのみ
         cfg.UseBreakPullback = true;   // ブレイクアウトバー即エントリー
         cfg.UseADXFilter = true;
         cfg.ADXMinLevel = 25.0;  // 強トレンド要求
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 400.0;
         // Edge filters
         cfg.ADXRequireRising = true;
         cfg.DISpreadMin = 10.0;  // DI差が大きいことを要求
         cfg.UseATRSlopeFilter = true;
         cfg.ATRSlopeRequireRising = true;
         cfg.UseFibFilter = false;  // 強トレンドではFib不要
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         // === 強トレンドモード有効 ===
         cfg.UseStrongTrendMode = true;
         cfg.StrongTrendADXLevel = 30.0;
         cfg.StrongTrendAutoActivate = true;
         cfg.ConsecutiveBarsCount = 3;
         cfg.LargeCandleMultiplier = 1.5;
         cfg.ShallowPullbackPercent = 40.0;
         cfg.UseBreakoutBarEntry = true;
         cfg.MinBarBodyRatio = 60.0;
         break;
         
      case PRESET_PARTIAL_CLOSE:
         // 段階利確重視型: 3段階で細かく利確
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
         cfg.TakeProfitFixedPoints = 500.0;  // 広めのTP（段階利確で徐々に回収）
         // Edge filters
         cfg.ADXRequireRising = false;
         cfg.DISpreadMin = 0;
         cfg.UseATRSlopeFilter = false;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         // === 段階利確設定: 3段階フル活用 ===
         cfg.EnablePartialClose = true;
         cfg.PartialCloseLevel1Pips = 15.0;
         cfg.PartialClosePercent1 = 30.0;
         cfg.PartialCloseLevel2Pips = 30.0;
         cfg.PartialClosePercent2 = 30.0;
         cfg.PartialCloseLevel3Pips = 50.0;
         cfg.PartialClosePercent3 = 40.0;
         cfg.MoveToBreakEvenAfterStage1 = true;
         cfg.BreakEvenOffsetPips = 2.0;
         break;
         
      case PRESET_TRAIL_PROFIT:
         // トレーリング重視型: 利益を伸ばす戦略
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
         cfg.StopLossFixedPoints = 150.0;
         cfg.TakeProfitFixedPoints = 0.0;  // TPなし（トレーリングで決済）
         // Edge filters
         cfg.ADXRequireRising = true;  // トレンド継続を確認
         cfg.DISpreadMin = 5.0;
         cfg.UseATRSlopeFilter = true;
         cfg.ATRSlopeRequireRising = true;
         cfg.UseFibFilter = false;
         cfg.UseCandlePattern = true;
         cfg.PatternPinBar = true;
         cfg.PatternEngulfing = true;
         cfg.UseDivergenceFilter = false;
         // === トレーリング設定: ATRベース ===
         cfg.TrailingMode = TRAILING_ATR;
         cfg.TrailingStopATRMulti = 1.5;
         cfg.TrailingActivationPips = 20.0;
         // 段階利確: 最初だけ回収
         cfg.EnablePartialClose = true;
         cfg.PartialCloseLevel1Pips = 20.0;
         cfg.PartialClosePercent1 = 30.0;
         cfg.PartialCloseLevel2Pips = 0.0;
         cfg.PartialClosePercent2 = 0.0;
         cfg.MoveToBreakEvenAfterStage1 = true;
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
      case PRESET_SCALPING:     return "Scalping";
      case PRESET_SWING:        return "Swing";
      case PRESET_ROUND_NUMBER: return "Round Number";
      case PRESET_STRONG_TREND: return "Strong Trend";
      case PRESET_PARTIAL_CLOSE:return "Partial Close";
      case PRESET_TRAIL_PROFIT: return "Trail Profit";
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
      case PRESET_SCALPING:
         return "スキャルピング型: M5/M15短期、狭いSL/TP、高頻度";
      case PRESET_SWING:
         return "スイング型: H1/H4中長期、広いSL/TP、トレーリング有効";
      case PRESET_ROUND_NUMBER:
         return "ラウンドナンバー型: .00/.50レベルを活用";
      case PRESET_STRONG_TREND:
         return "強トレンド型: Al Brooks理論、連続バー・浅いプルバック";
      case PRESET_PARTIAL_CLOSE:
         return "段階利確型: 3段階で細かく利確、リスク管理重視";
      case PRESET_TRAIL_PROFIT:
         return "トレーリング型: ATRトレール、利益を伸ばす戦略";
      case PRESET_CUSTOM:
         return "カスタム: 全パラメータ手動設定";
      default:
         return "不明なプリセット";
   }
}

#endif
