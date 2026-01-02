# CONTEXT LOCK（前提条件の固定）

このファイルは「前提条件を忘れない」ための **絶対ルール** です。
作業を始める前に必ずここを参照し、ここに反する変更はしません。

---

## 役割分担（最終確定）

- 楽天MT4: PullbackEntry がメイン
- OANDA MT5: **HTTP推論サーバー** がメイン（:5001）
- MT4_AI_Trader: **ファイルサーバー運用**（代替執行＋ログ収集）

---

## 絶対ルール

### 1) 推論サーバーの正本

このリポジトリの運用正本はこれだけ:

- `python/inference_server_http_7module.py`
- API: `GET /health`, `POST /analyze`, `POST /predict`
- ポート: **5001**（固定）

### 2) GPU専用運用

- GPU運用が前提。CPU導線を増やしたり、CPU向けの別運用を提案しない。

### 3) 「推論サーバーを壊す変更」はしない

- サーバー本体、Docker、依存関係、API、ポート等に触る変更は **事前合意なしに絶対に入れない**。
- 迷いが出る変更（正本の分岐・増殖）も入れない。

### 4) MT5 PullbackEntry は撤退済み

- PullbackEntry（MT5側）の完成は目標にしない。復活させない。

---

## 混線しないための固定

- MT5は **HTTP(:5001)**
- MT4_AI_Trader は **ファイルI/F**（共有フォルダ固定）

MT4側のファイルI/F正本は mt4-pullback-trader 側の [python/CANONICAL_FILE_SERVER.md](../python/CANONICAL_FILE_SERVER.md) を参照（本リポジトリからは変更しない）。
