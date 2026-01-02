# 楽天MT4 vs OANDA MT5: 最小ロット/刻みで迷わないための手順

結論: ブローカー/銘柄ごとに「最小ロット」「ロット刻み」「1ポイント価値」が違うのは普通です。数値を暗記せず、**端末に問い合わせてログに出す**のが一番確実です。

## 何が違うのか（混乱ポイント）

- **最小ロット**（`min volume`）: そもそも発注できる最小サイズ
- **ロット刻み**（`step`）: 0.01刻みなのか 1.0刻みなのか等
- **コントラクトサイズ**（`contract size`）: 1ロットが何単位か
- **1ポイント（または1ティック）価値**: 同じSL幅でも損益が全く変わる

これらが揃って初めて「同じリスク」を作れます。

## まずやること（ログで確認）

### MT5（OANDA）

1. MT5のMetaEditorでスクリプトをコンパイル
   - `mql5/Scripts/DumpSymbolSpecs.mq5`
2. MT5で対象銘柄のチャートを開き、スクリプトを実行
3. Expertsログに以下が出ます
   - `SYMBOL_VOLUME_MIN` / `SYMBOL_VOLUME_STEP`
   - `SYMBOL_TRADE_TICK_VALUE` / `SYMBOL_TRADE_TICK_SIZE`
   - `SYMBOL_TRADE_CONTRACT_SIZE`

### MT4（楽天）

1. MetaEditorでスクリプトをコンパイル
   - `mql4/Scripts/DumpSymbolSpecs.mq4`
2. MT4で対象銘柄のチャートに適用
3. Expertsログに以下が出ます
   - `MODE_MINLOT` / `MODE_LOTSTEP`
   - `MODE_TICKVALUE` / `MODE_TICKSIZE`
   - `MODE_LOTSIZE`

## “同じリスク”の作り方（考え方だけ統一）

リスク金額を $R$、ストップ幅を $S$（ポイント/ティック換算）とすると、

$$\text{損失} \approx \text{ロット} \times (\text{1ポイント価値}) \times S$$

なので、

$$\text{ロット} \approx \frac{R}{(\text{1ポイント価値})\times S}$$

ここでの「1ポイント価値」は、上記ログの `tickValue` と `tickSize` と `point` から近似できます。

## ありがちな落とし穴

- CFDは **0.1 lotが最小**だったり、逆に **1.0 unitが最小**だったりします
- 同じ「US500」でも、口座/ブローカー設定で **最小ロットが1.0** のことがあります（小さく張れない）
   - この場合は、MT5の気配値にある別シンボル（例: `US500m` / `US500mini` 等）が無いか探して、同じスクリプトで `SYMBOL_VOLUME_MIN` を確認するのが早いです
- JP225 も、環境によっては **`SYMBOL_VOLUME_MIN=1.0` / `SYMBOL_VOLUME_STEP=0.01`** などになり得ます（小さく張れない）
- 指数は銘柄により `SYMBOL_POINT` が 0.1 / 0.01 / 1.0 などバラバラです
- `SYMBOL_POINT` が 0.1 の銘柄は、**1.0 価格 = 10 points** になります（EAの「円/ドル入力」を points に変換する際の落とし穴）
- 金曜/指標前後はスプレッドが跳ねるので、最初はスプレッド閾値を狭めに

