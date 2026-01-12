# MT5 段階利確（部分決済）再起動耐性：検証手順（チェックリスト）

作成日: 2026-01-11

## 関連ドキュメント
- 実装計画（チェックリスト / 別リポジトリ）: https://github.com/sawai-46/mt4-pullback-trader/blob/main/docs/EA_%E6%AE%B5%E9%9A%8E%E5%88%A9%E7%A2%BA_%E5%86%8D%E8%B5%B7%E5%8B%95%E8%80%90%E6%80%A7_%E5%AE%9F%E8%A3%85%E8%A8%88%E7%94%BB_CHECKLIST_2026-01-09.md
- 検証手順（MT4 / 別リポジトリ）:
  - GitHub: https://github.com/sawai-46/mt4-pullback-trader/blob/main/docs/EA_%E6%AE%B5%E9%9A%8E%E5%88%A9%E7%A2%BA_%E5%86%8D%E8%B5%B7%E5%8B%95%E8%80%90%E6%80%A7_%E6%A4%9C%E8%A8%BC%E6%89%8B%E9%A0%86_CHECKLIST_2026-01-11.md
  - ローカル（VS Code / multi-root）: [../../mt4-pullback-trader/docs/EA_段階利確_再起動耐性_検証手順_CHECKLIST_2026-01-11.md](../../mt4-pullback-trader/docs/EA_%E6%AE%B5%E9%9A%8E%E5%88%A9%E7%A2%BA_%E5%86%8D%E8%B5%B7%E5%8B%95%E8%80%90%E6%80%A7_%E6%A4%9C%E8%A8%BC%E6%89%8B%E9%A0%86_CHECKLIST_2026-01-11.md)

## 0. 目的
- 段階利確（部分決済）ステージが、EAの再初期化（再アタッチ/再コンパイル/端末再起動）後も復元されることを確認する。
  - `Include/Position/PositionManager.mqh`（PositionManager採用EA）
  - `Experts/MT5_AI_Trader_{FX,JP225,USIndex}.mq5`
- 永続化は「ターミナル Global Variables（GV）」を使用し、キーは `POSITION_IDENTIFIER` を採用（部分決済後にticketが変わっても追従しやすい）。

---

## 1. 事前準備

### 1.1 EA入力（推奨）
- [ ] 対象EAの以下をON
  - [ ] `InpEnablePersistentTpState = true`
  - [ ] `InpLogPersistentTpStateEvents = true`（最初だけON推奨）
- [ ] `InpEnablePartialClose = true`

### 1.2 検証前の掃除（GV）
- [ ] 検証シンボルが**完全にフラット**であることを確認
- [ ] MT5のメニュー: `ツール > グローバル変数` で、該当prefixが残っていれば削除
  - PositionManager系: `PERSIST|MT5_PM|<Symbol>|<Magic>|...`
  - AI Trader系: `PERSIST|MT5_AIT_XX|<Symbol>|<Magic>|...`（XX = FX / JP / US）

---

## 2. 共通の合否判定

### 2.1 期待する挙動
- [ ] stage=1後に再初期化しても、Level1が二重実行されない
- [ ] stage=1後に再初期化しても、次の到達でLevel2/3が継続して実行される
- [ ] フラット時のみGVが掃除される

### 2.2 期待するログ（Log ON時）
- [ ] save: `[PERSIST][MT5_PM] saved ...` または `[PERSIST][MT5_AIT_XX] saved ...`
- [ ] restore: `[PERSIST][MT5_PM] restored ...` または `[PERSIST][MT5_AIT_XX] restored ...`
- [ ] cleared: `[PERSIST][MT5_PM] cleared GV ...` または `[PERSIST][MT5_AIT_XX] cleared GV ...`（フラット時のみ）

---

## 3. テストシナリオ（MT5）

### シナリオA: 再アタッチ耐性（最短）
- [ ] 1ポジションを建てる
- [ ] Level1に到達して部分決済が1回走る（stage=1）
- [ ] EAをチャートから削除 → 再アタッチ
- [ ] その後、Level2（or Level3）到達で次の段階だけが実行される

### シナリオB: 再コンパイル耐性
- [ ] stage=1 の状態でコンパイルし直す
- [ ] 再初期化後もstage=1が復元され、次の段階だけ進む

### シナリオC: 端末再起動耐性
- [ ] stage=1 の状態でMT5端末を終了 → 再起動
- [ ] 稼働再開後に restoreログが出て、次の段階だけ進む

### シナリオD: ticket変化耐性（重要）
- [ ] 部分決済後に ticket が変わる（または変わらない）環境で、stageが追従する
- [ ] restore/save は `POSITION_IDENTIFIER` ベースで行われる

### シナリオE: フラット時の掃除
- [ ] 最終段階で全決済（or 手動で全決済）
- [ ] 数分以内に `cleared GV` が出る（クールダウンあり / 300秒）
- [ ] `ツール > グローバル変数` にprefixが残らない

---

## 4. トラブルシュート

### 4.1 復元されない
- [ ] `InpEnablePersistentTpState=true` か
- [ ] マジック/シンボルが一致しているか
- [ ] openPriceガード（Point*2）で弾かれていないか

### 4.2 GVが消えない
- [ ] 同じマジック/シンボルのポジションが残っていないか
- [ ] clearedはフラット時のみ（仕様）
