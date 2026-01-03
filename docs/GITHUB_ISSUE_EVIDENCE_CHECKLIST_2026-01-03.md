# GitHub提出用 証拠チェックリスト（2026-01-03）

このファイルは「意図の証明」ではなく、第三者が追跡できる**事実の証拠**を揃えるためのチェックリストです。

## 1) リポジトリ情報（こちらで用意済み）
- 対象: `sawai-46/mt5-oanda-trader`
- ブランチ: `main`
- 観測時のHEAD: `e5ed28b263e4942357641f30f82bc0342f48e012`

## 2) 影響ファイル（Pullback）
- `mql5/Experts/EA_PullbackEntry_v5_FX.mq5`
- `mql5/Experts/EA_PullbackEntry_v5_JP225.mq5`
- `mql5/Experts/EA_PullbackEntry_v5_USIndex.mq5`

## 3) 差分証拠（こちらで用意可能）
以下コマンド出力をIssueに貼る（または要点を引用）:
- `git rev-parse HEAD`
- `git diff --stat`
- `git diff`（該当箇所だけ）

## 4) 検索証拠（こちらで用意可能）
「問題の識別子がどこで使われているか」を示す:
- Windows PowerShell例:
  - `Select-String -Path .\\mql5\\Experts\\EA_PullbackEntry_v5_*.mq5 -Pattern "PeriodToString\\("`

## 5) 必須の一次証拠（ユーザー提供が必要）
以下はMetaEditor上の出力のため、こちら側で生成できません。

### 5.1 コンパイルログ（最重要）
- MetaEditorの「Errors」タブの先頭（最初のエラーから）を**20〜40行**コピー
- 可能なら、どのEAをコンパイルしたか（FX/JP225/USIndex）も併記

例:
- `EA_PullbackEntry_v5_USIndex.mq5(123,45): error ...`

### 5.2 利用している `.set`（任意だが強い）
- もし `.set` を読み込んでいるなら、そのファイル名

## 6) 既に用意したIssueドラフト
- `docs/GITHUB_ISSUE_REPORT_PULLBACKENTRY_BROKEN_2026-01-03.md`

