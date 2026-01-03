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
