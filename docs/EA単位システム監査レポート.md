# EA 単位システム監査レポート

**監査日**: 2026-01-03  
**対象**: MT4 (楽天証券) / MT5 (OANDA) 全EA  
**結論**: ✅ **すべてのEAで適切な動的単位変換が実装済み。ハードコードなし。**

> [!IMPORTANT]
> **2026-01-03 修正**: デフォルト値を「取引銘柄のテクニカル指標調査.md」推奨値に修正しました。
> 
> | EA | 変更項目 | 修正前 → 修正後 |
> |----|---------|----------------|
> | **JP225版** | スリッページ | 50pt → 20pt |
> | | 最大スプレッド | 5円 → 20円 |
> | | SL | 30円 → 50円 |
> | | TP | 60円 → 100円 |
> | | ATR閾値 | 10円 → 50円 |
> | **USIndex版** | スリッページ | 50pt → 300pt |
> | | 最大スプレッド | 5ドル → 8ドル |
> | | ATR閾値 | 5ドル → 35ドル |
> | **FX版** | ATR閾値 | 3pips → 8pips |

---

## 📊 監査結果サマリー

| プラットフォーム | 対象EA数 | FX | JP225 | USIndex | 評価 |
|-----------------|---------|-----|-------|---------|------|
| **MT5 (OANDA)** | 3 | ✅ | ✅ | ✅ | 適切 |
| **MT4 (楽天)** | 12+ | ✅ | ✅ | ✅ | 適切 |

---

## 1. MT5 EA（OANDA対応）

### 1.0 EA一覧

| EA名 | 入力単位 | 評価 |
|------|----------|------|
| `MT5_AI_Trader_FX.mq5` | pips | ✅ |
| `MT5_AI_Trader_JP225.mq5` | 円 | ✅ |
| `MT5_AI_Trader_USIndex.mq5` | ドル | ✅ |
| `EA_PullbackEntry_v5_FX.mq5` | pips | ✅ |
| `EA_PullbackEntry_v5_JP225.mq5` | 円 | ✅ |
| `EA_PullbackEntry_v5_USIndex.mq5` | ドル | ✅ |

---

### 1.1 MT5_AI_Trader_FX.mq5

| 項目 | 内容 |
|------|------|
| **入力単位** | pips |
| **変換ロジック** | `_Digits`から`g_pipMultiplier`を動的計算 |
| **コード例** | `g_pipMultiplier = (_Digits == 3 \|\| _Digits == 5) ? 10.0 : 1.0` |
| **評価** | ✅ 適切 |

### 1.2 MT5_AI_Trader_JP225.mq5

| 項目 | 内容 |
|------|------|
| **入力単位** | 円 |
| **変換ロジック** | `SYMBOL_POINT`から動的計算 |
| **コード例** | `yenToPoints = 1.0 / SymbolInfoDouble(_Symbol, SYMBOL_POINT)` |
| **評価** | ✅ 適切 |

### 1.3 MT5_AI_Trader_USIndex.mq5

| 項目 | 内容 |
|------|------|
| **入力単位** | ドル |
| **変換ロジック** | `SYMBOL_POINT`から動的計算 |
| **コード例** | `g_dollarMultiplier = 1.0 / symbolPoint` |
| **評価** | ✅ 適切 |

---

### 1.4 EA_PullbackEntry_v5_FX.mq5 (OOP版)

| 項目 | 内容 |
|------|------|
| **入力単位** | pips |
| **変換ロジック** | `_Digits`から`g_pipMultiplier`を動的計算 |
| **コード例** | `g_pipMultiplier = (_Digits == 3 \|\| _Digits == 5) ? 10.0 : 1.0` |
| **変換適用** | SL/TP/ATR/Spread/Partial Close/Trailing全て |
| **評価** | ✅ 適切 |

### 1.5 EA_PullbackEntry_v5_JP225.mq5 (OOP版)

| 項目 | 内容 |
|------|------|
| **入力単位** | 円 |
| **変換ロジック** | 1円=1point としてそのまま使用 |
| **コード例** | `g_SLFixedPoints = InpSLFixedYen` (直接代入) |
| **変換適用** | SL/TP/ATR/Spread/Partial Close/Trailing全て |
| **評価** | ✅ 適切 |

### 1.6 EA_PullbackEntry_v5_USIndex.mq5 (OOP版)

| 項目 | 内容 |
|------|------|
| **入力単位** | ドル |
| **変換ロジック** | `SYMBOL_POINT`から`g_dollarMultiplier`を動的計算 |
| **コード例** | `g_dollarMultiplier = 1.0 / SymbolInfoDouble(_Symbol, SYMBOL_POINT)` |
| **変換適用** | SL/TP/ATR/Spread/Partial Close/Trailing全て |
| **評価** | ✅ 適切 |

### 1.7 共通ロジック: PullbackStrategy.mqh

| 項目 | 内容 |
|------|------|
| **設計** | OOPクラス `CPullbackStrategy` |
| **単位使用** | 設定値はすべてpoints単位で受け取り |
| **ATR計算** | `atr / _Point` でpoints変換 |
| **SL/TP計算** | `m_cfg.StopLossFixedPoints * _Point` で価格単位に変換 |
| **評価** | ✅ 適切（各EAで変換済のpoints値を使用）|

---

## 2. MT4 EA（楽天証券対応）

### 2.1 AI Trader系（ファイルベース通信）

| EA | 入力単位 | 変換方式 | 評価 |
|----|----------|---------|------|
| `MT4_AI_Trader_v2_File.mq4` | pips | `InitializePipValue()` | ✅ |
| `MT4_AI_Trader_v2_File_JP225.mq4` | 円/points | `EffectiveSlippagePoints()` | ✅ |
| `MT4_AI_Trader_v2_File_USIndex.mq4` | ドル/points | `EffectiveSlippagePoints()` | ✅ |
| `MT4_AI_Trader_v2_HTTP.mq4` | pips | `InitializePipValue()` | ✅ |

### 2.2 PullbackEntry系（スタンドアロン）

| EA | 入力単位 | 変換方式 | 評価 |
|----|----------|---------|------|
| `EA_PullbackEntry.mq4` | pips | `Digits`基準pip計算 | ✅ |
| `EA_PullbackEntry_Nikkei225.mq4` | points/円 | `EffectiveSlippagePoints()` | ✅ |
| `EA_PullbackEntry_USIndex.mq4` | points/ドル | `EffectiveSlippagePoints()` | ✅ |

### 2.3 PositionManagement系

| EA | 入力単位 | 変換方式 | 評価 |
|----|----------|---------|------|
| `EA_PositionManagement_v2.mq4` | pips | `PipValue()` | ✅ |
| `EA_PositionManagement_v2_NK225.mq4` | points | 直接使用 | ✅ |
| `EA_PositionManagement_v2_USIndex.mq4` | points | 直接使用 | ✅ |

---

## 3. 実装パターン

### 3.1 FX用 pip計算（MT4/MT5共通パターン）

```cpp
// Digitsが3または5の場合（フラクショナル・ピップ）
if (Digits == 3 || Digits == 5) {
   point_size = Point * 10;
   pip = point_size;
} else {
   point_size = Point;
   pip = Point;
}
```

**解説**: 5桁/3桁ブローカー（OANDA、楽天等）では1 pip = 10 pointsになるため動的に計算

### 3.2 CFD用 通貨→points変換（JP225/USIndex）

```cpp
// 円/ドルからpointsへの変換
int EffectiveSlippagePoints(){
   if(Max_Slippage_Pips > 0.0){
      // 例: JP225で Point=0.01 の場合、1円 = 100 points
      return (int)MathRound(Max_Slippage_Pips * 1.0 / Point);
   }
   return Max_Slippage_Points;  // 互換用フォールバック
}
```

**解説**: `Point`値を動的に取得し、ユーザー入力の円/ドルを内部のpoints単位に変換

---

## 4. 検索で確認したハードコード候補

| 検索パターン | 結果 |
|-------------|------|
| `0.01` / `0.001` | ❌ 価格単位ハードコードなし |
| `_Point` | ✅ 動的参照で使用 |
| `_Digits` | ✅ 動的参照で使用 |
| `SYMBOL_POINT` | ✅ 動的参照で使用 |
| `TickValue` / `TickSize` | ⚠️ `DumpSymbolSpecs.mq5`でログ出力のみ |

---

## 5. 潜在的な改善点

### 5.1 現時点で問題なし

| 項目 | 状況 |
|------|------|
| pips/points変換 | ✅ 全EA対応済み |
| シンボル固有Point値 | ✅ 動的取得 |
| ブローカー差異対応 | ✅ Digits基準で対応 |

### 5.2 将来的な検討事項

| 項目 | 現状 | 推奨アクション |
|------|------|---------------|
| **TickValue/TickSize活用** | ログ出力のみ | 口座通貨が異なる場合の損益計算に統合検討 |
| **XAU (金) 対応** | 未対応 | 必要時に専用EA作成を検討 |
| **汎用ヘルパー関数** | 各EAに個別実装 | `Include`ファイルへの共通化を検討 |

---

## 6. 結論

### ✅ 安全に運用可能

- **FX**: `Digits`基準の動的pip計算により、ブローカー差異に対応
- **JP225**: 円単位入力 → `1.0/Point`でpoints変換
- **USIndex**: ドル単位入力 → `1.0/Point`でpoints変換

### 📝 設計上の決定事項

1. **資産クラス別EA分離**: FX/JP225/USIndexで別ファイル化し、入力単位を明確化
2. **直感的な入力単位**: トレーダー慣習（pips/円/ドル）で入力、内部でpoints変換
3. **MQL組み込み関数活用**: `SymbolInfoDouble()`, `Point`, `Digits`等を積極活用

---

## 参考資料

- [楽天MT4 Pips_Point・スリッページ・スプレッド.md](./楽天MT4%20Pips_Point・スリッページ・スプレッド.md)
- [OANDA MT5 取引条件調査.md](./OANDA%20MT5%20取引条件調査.md)

---

## 7. 技術的な改善策（Copilotの誤誘導を減らすための設定・運用）

Copilotは「開いているファイル」「ワークスペースに含まれるファイル」「直近の編集内容」などのコンテキストを強く参照します。
そのため、**異なる版のEAや、依存関係（Include）の異なるセットが同じ作業コンテキストに混在**すると、構造体・関数・クラスの前提が混ざって誤提案が起きやすくなります。

### 7.1 プロジェクトスコープを明確化（混在を物理的に断つ）

- VS Codeで「復元対象の最新版」だけを含むフォルダ（例: `mt5-oanda-trader` のみ）を開く
- 古い版・実験版・依存関係が異なるファイルは別ディレクトリに隔離し、**同一ワークスペースに入れない**
- 利用可能な環境では、Copilotの対象外設定（例: ignore系設定）を使って不要ファイルを除外する
   - ※利用可否はプラン/機能提供状況に依存します。使えない場合は「ワークスペースから外す/隔離する」が最も確実です

### 7.2 コメントで前提を明示（モデルの前提ズレを抑える）

Copilotはコメントやファイル冒頭の説明を強く参照します。たとえばEA冒頭に、次のように明示します。

```cpp
// このファイルは最新版EAのMQL4版。
// 古い構造体/古いIncludeセットや、MQL5依存コードは使用しない。
// 参照するIncludeは（例）: MQL4/Include/... のみ。
```

### 7.3 提案の確認と制御（誤前提を早期に検出）

- そのまま受け入れる前に、提案の前提をチャットで確認する（例: 「この修正はMQL4前提？MQL5前提？」）
- 複数候補を見て選べるUI（候補パネル等）を使い、最も前提が合う提案だけを採用する
- 不要提案が続く場合は、コマンドパレットからCopilotのインライン提案/補完を一時的に無効化して、手動編集に切り替える

### 7.4 拡張機能の更新（既知不具合・精度差の回避）

- VS Codeの拡張機能で `GitHub Copilot` と `GitHub Copilot Chat` を最新に更新
- 挙動が不安定な時は、更新後にVS Code再起動（提案エンジン/キャッシュの再初期化）

### 7.5 「一般的なパターンの押し付け」を避ける

MQLは言語・実装慣習が特殊なため、一般的なC++風のパターンが誤って提案されることがあります。
この場合は、

- 既存リポジトリ内の「正しい実例」を開いた状態で編集する（参照コンテキストを寄せる）
- 依存関係（Includeセット）を1つに固定し、同一コミット/同一世代で揃える

を優先すると、前提ズレが大きく減ります。
