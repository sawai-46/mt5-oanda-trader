# PullbackEntry v5 プリセット運用ガイド（MTF無し）

このドキュメントは、`EA_PullbackEntry_v5_*`（FX/USIndex/JP225）で使うプリセットの意味と、運用で迷わないためのルールをまとめたものです。

## 重要ルール（先にこれだけ）

- **`InpPresetApplyMode=2`（デフォルト）**: Preset優先。プリセットが **Strategy/Filter/Position** まで一括で効きます。
- **`InpPresetApplyMode=0`**: Input優先（`.set` 尊重）。プリセットは適用しません。
- **`InpPreset=PRESET_CUSTOM`**: 常に Input 優先（`.set` をそのまま使う）。
- **`InpTerminalId` は端末固定ID**
  - 例: `10900k-mt5-fx` / `10900k-mt5-index`
  - **live/demo は含めない**（口座切替の概念として扱う）

### Preset優先でも Input が使われる項目

Preset優先（`InpPresetApplyMode!=0` かつ `InpPreset!=PRESET_CUSTOM`）でも、以下は **環境依存**として Input 値を使います。

- `InpMaxSpread*`（FX: pips / USIndex: dollars / JP225: yen） → `MaxSpreadPoints`
- `InpADXPeriod` / `InpATRPeriod`
- `InpGMTOffset`（JST変換の基準）
- `InpStartHour` / `InpEndHour` / `InpTradeOnFriday`（取引時間帯）
- `InpMagicNumber` / `InpLotSize` / `InpDeviationPoints`
- `InpTerminalId` / `InpAiLearningFolder` / `InpEnableAiLearningCsv`

理由: ブローカー/銘柄/環境で変わる値をプリセットに固定しないため。

## 推奨スプレッド（初期値の目安）

市場状況で最適値は変わるので、まずは **「狭めに始める」**のが安全です（広げるのは後からでも可能）。

### FX（`InpMaxSpreadPips`）

- EURUSD: 2.0
- USDJPY: 2.0
- AUDUSD: 2.5
- EURJPY: 3.5
- AUDJPY: 3.5

### 指数（`InpMaxSpreadDollars` / `InpMaxSpreadYen`）

- US500: 1.5（ドル）
- US30: 3.0（ドル）
- US100（NQ100）: 3.0（ドル）※宝くじ枠は時間帯も絞る（取引時間外はスプレッド拡大しがち）
- JP225: 20（円）※時間帯によって 15 円前後まで広がることがある（実測）

※ ここはブローカー表示/時間帯で大きく変わるので、実測ログで微調整がベスト。

## 最小ロット/刻みが違って混乱したら

- 楽天MT4とOANDA MT5で、CFD/Fxの最小ロットや刻みが違うのは正常です。
- 暗記しないで、端末から仕様をダンプして確認してください:
  - [docs/SYMBOL_SPECS_AND_LOT_MINIMUMS.md](SYMBOL_SPECS_AND_LOT_MINIMUMS.md)

## unit → points 換算（プリセットのスケーリング）

プリセット内部のSL/TP/ATR/部分利確幅などは「unit」を介して points に変換されます。

- **FX**: `1 unit = 1 pip`
  - 5桁/3桁: `unitToPoints=10`
  - 4桁/2桁: `unitToPoints=1`
- **USIndex**: `1 unit = 1.0 価格（指数の値幅）`（`unitToPoints = 1 / SYMBOL_POINT`）
  - 例: `SYMBOL_POINT=0.01` → `unitToPoints=100`
- **JP225**: `1 unit = 1.0 価格（円/指数の値幅）`（`unitToPoints = 1 / SYMBOL_POINT`）
  - 例: `SYMBOL_POINT=0.1` → `unitToPoints=10`（1円=10 points）

この換算値はEA側で自動計算して `ApplyPresetAll(..., unitToPoints)` に渡しています。

## プリセット一覧（Strategy + Filters + Position）

凡例:
- **ATRMin**: `ATRMinPoints` / `ATRThresholdPoints`
- **SL/TP**: fixed points（`SLTPMode` が fixed の場合）
- **Time**: 取引時間フィルタ（ローカル時間ではなく EA 設定の扱いに従う）
- **Channel**: `EnableChannelFilter` と `MinChannelWidthPoints`

### Standard（標準）
- Strategy
  - EMA: 12/25/100、PerfectOrder=true
  - Pullback: Touch=true, Cross=true, Break=false（Ref=EMA25）
  - ADX>=20、ATRMin=3.0 unit
  - SL=15 unit / TP=30 unit
- Filters
  - Time: 08:00-21:00, Friday=true
  - Spread/ATR/ADX: on、Channel: off
- Position
  - Partial: 2段（15 unitで50% → 30 unitで100%）
  - BE: after L1=true、after L2=true、Trailing=off

### Conservative（保守）
- Strategy
  - EMA: 12/25/100、PerfectOrder=true
  - ADX>=25、ATRMin=4.0 unit
  - SL=20 unit / TP=40 unit
- Filters
  - Time: 09:00-20:00, Friday=false
  - Spread/ATR/ADX: on、Channel: on（MinChannelWidth=10 unit）
- Position
  - Partial: 2段（20 unitで50% → 40 unitで100%）
  - BE: after L1=true、after L2=true、Trailing=off

### Aggressive（積極）
- Strategy
  - EMA: 12/25/100、PerfectOrder=false
  - Pullback: Touch/Cross/Break=true（回数重視）
  - ADX>=15、ATRMin=2.0 unit
  - SL=12 unit / TP=24 unit
- Filters
  - Time: 07:00-22:00, Friday=true
  - Spread/ATR/ADX: on、Channel: off
- Position
  - Partial: 2段（12 unitで50% → 24 unitで100%）
  - BE: after L1=true、after L2=true、Trailing=off

### Scalping（スキャル）
- Strategy
  - EMA: 8/20/50、PerfectOrder=false
  - ADX filter: off、ATRMin=1.0 unit
  - SL=6 unit / TP=12 unit
- Filters
  - Time: 09:00-18:00, Friday=true
  - Spread/ATR: on、ADX: off、Channel: off
- Position
  - Partial: 2段（6 unitで60% → 12 unitで100%）
  - BE: after L1=true、after L2=false、Trailing=off

### TrendPullback（トレンド継続押し目）
- Strategy
  - EMA: 12/25/100、PerfectOrder=true
  - Pullback: Touch=true, Cross=false, Break=false（ノイズ減）
  - ADX>=22、ATRMin=3.5 unit
  - SL=18 unit / TP=45 unit
- Filters
  - Time: 09:00-21:00, Friday=true
  - Spread/ATR/ADX: on、Channel: on（MinChannelWidth=12 unit）
- Position
  - Partial: 3段（18 unitで40% → 30 unitで40% → 45 unitで100%）
  - BE: after L1=true、after L2=true、Trailing=off

### BreakoutPullback（ブレイク後押し）
- Strategy
  - EMA: 8/20/100、PerfectOrder=false
  - Pullback: Touch=false, Cross=true, Break=true（Ref=EMA12）
  - ADX>=18、ATRMin=3.0 unit
  - SL=15 unit / TP=35 unit
- Filters
  - Time: 08:00-22:00, Friday=true
  - Spread/ATR/ADX: on、Channel: on（MinChannelWidth=10 unit）
- Position
  - Partial: 2段（15 unitで50% → 35 unitで100%）
  - BE: after L1=true、after L2=true、Trailing=off

### Defensive（防御）
- Strategy
  - EMA: 12/25/100、PerfectOrder=true
  - ADX>=28、ATRMin=4.0 unit
  - SL=20 unit / TP=30 unit
- Filters
  - Time: 09:00-20:00, Friday=false
  - Spread/ATR/ADX: on、Channel: on（MinChannelWidth=12 unit）
- Position
  - Partial: 2段（15 unitで60% → 30 unitで100%）
  - BE: after L1=true、after L2=false、Trailing=off

## 実装参照

- プリセット定義: `mql5/Include/Strategies/Pullback/PullbackPresets.mqh`
- EA本体: `mql5/Experts/EA_PullbackEntry_v5_FX.mq5` / `..._USIndex.mq5` / `..._JP225.mq5`

## `.set` 雛形（matsuPC向け）

リポジトリ内に雛形を置いています（MT5端末の `MQL5\Presets\` にコピーして読み込んでください）。

- FX
  - `mql5/Presets/PBEv5_FX_matsu_MAJORS_STANDARD.set`（EURUSD/USDJPY想定）
  - `mql5/Presets/PBEv5_FX_matsu_JPYCROSSES_STANDARD.set`（EURJPY/AUDJPY想定）
  - `mql5/Presets/PBEv5_FX_matsu_AUDUSD_STANDARD.set`
  - `mql5/Presets/PBEv5_FX_matsu_STANDARD.set`（汎用）
- US Index
  - `mql5/Presets/PBEv5_USIndex_matsu_US500_DEFENSIVE.set`
  - `mql5/Presets/PBEv5_USIndex_matsu_US30_DEFENSIVE.set`
  - `mql5/Presets/PBEv5_USIndex_matsu_US100_LOTTERY_BREAKOUT.set`
  - `mql5/Presets/PBEv5_USIndex_matsu_DEFENSIVE.set`（汎用）

### 実測メモ（OANDA MT5の例）

- US30: `VOL_MIN=0.1 / STEP=0.1`（=0.1刻み）
- US100: `VOL_MIN=0.1 / STEP=0.1`（=0.1刻み、スプレッド広がりやすい）
- US500: **`VOL_MIN=1.0 / STEP=0.01`**（=最小ロットが大きいので要注意。別シンボルが無いか確認推奨）
- JP225
  - `mql5/Presets/PBEv5_JP225_matsu_DEFENSIVE.set`
  - 実測例: `Point=0.1`（=1円=10 points）, `VOL_MIN=1.0 / STEP=0.01`, `SpreadPrice=15.0`（時間帯で変動）

