# MT5 AI Trader - 引継ぎガイド

## 概要
OANDA MT5への移行プロジェクト。MQL4からMQL5へのOOP化リファクタリング。

---

## OANDA MT5 仕様（重要）

| 項目 | FX (USDJPY等) | CFD (JP225等) |
|------|---------------|---------------|
| **1 Pip** | 0.01円 | 1.0円 |
| **1 Point** | 0.001円 | 0.1円 |
| **Point/Pip比** | **10倍** | **10倍** |
| **1 Lot** | 100,000通貨 | 1 Unit (指数価格×1) |
| **スプレッド許容** | 15 Points | 200 Points |
| **スリッページ許容** | 30-50 Points | 50-100 Points |

> ⚠️ MT5のSL/TP入力は**Points単位**。15 pipsなら「150」と入力。

---

## ディレクトリ構造

```
MT5_AI_Trader/
├── mql5/
│   ├── Experts/
│   │   └── MT5_AI_Trader.mq5       # メインEA
│   ├── Include/
│   │   ├── Core/
│   │   │   ├── StrategyBase.mqh    # 抽象基底クラス
│   │   │   ├── TradeManager.mqh    # 注文管理
│   │   │   └── IndicatorManager.mqh
│   │   ├── Strategies/
│   │   │   └── Pullback/
│   │   │       ├── PullbackStrategy.mqh
│   │   │       └── PullbackConfig.mqh
│   │   ├── Integration/
│   │   │   ├── HttpClient.mqh      # 推論サーバー通信
│   │   │   └── Logger.mqh
│   │   └── Utils/
│   │       └── Common.mqh          # 共通Enum定義
│   └── Scripts/
│       └── CheckParams.mq5         # ブローカー仕様確認用
├── python/                         # 推論サーバー（mt4-pullback-traderからコピー済み）
└── docs/
    └── OANDA MT5 取引条件調査.md   # 詳細仕様書
```

---

## 実装済みコード

### 1. Common.mqh
```cpp
#ifndef __COMMON_MQH__
#define __COMMON_MQH__

enum ENUM_SIGNAL_TYPE {
   SIGNAL_NONE = 0, SIGNAL_ENTRY_BUY = 1, SIGNAL_ENTRY_SELL = 2,
   SIGNAL_EXIT_BUY = 3, SIGNAL_EXIT_SELL = 4, SIGNAL_EXIT_ALL = 5
};

enum ENUM_LOG_LEVEL { LOG_INFO = 0, LOG_WARN = 1, LOG_ERROR = 2, LOG_DEBUG = 3 };

#endif
```

### 2. TradeManager.mqh
```cpp
#include <Trade/Trade.mqh>

class CTradeManager : public CTrade {
public:
   CTradeManager() {
      SetDeviationInPoints(10);
      SetTypeFilling(ORDER_FILLING_IOC); // OANDA向け
      SetAsyncMode(false);
   }
};
```

### 3. IndicatorManager.mqh
```cpp
#include <Object.mqh>

class CIndicatorManager : public CObject {
public:
   CIndicatorManager() {}
   virtual ~CIndicatorManager() {}
};
```

### 4. StrategyBase.mqh
```cpp
#include <Object.mqh>
#include "../Utils/Common.mqh"
#include "TradeManager.mqh"
#include "IndicatorManager.mqh"

class CStrategyBase : public CObject {
protected:
   string m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   CTradeManager *m_trade;
   CIndicatorManager *m_indicators;

public:
   CStrategyBase(string symbol, ENUM_TIMEFRAMES timeframe)
      : m_symbol(symbol), m_timeframe(timeframe) {
      m_trade = new CTradeManager();
      m_indicators = new CIndicatorManager();
   }

   virtual ~CStrategyBase() {
      if(CheckPointer(m_trade)==POINTER_DYNAMIC) delete m_trade;
      if(CheckPointer(m_indicators)==POINTER_DYNAMIC) delete m_indicators;
   }

   virtual void OnTick() = 0;
   virtual bool CheckEntry() { return false; }
   virtual bool CheckExit() { return false; }
};
```

### 5. HttpClient.mqh
```cpp
#include <Object.mqh>

class CHttpClient : public CObject {
private:
   string m_serverUrl;
   int m_timeout;

public:
   CHttpClient(string url, int timeout=2000) : m_serverUrl(url), m_timeout(timeout) {}

   bool PostJson(string endpoint, string jsonBody, string &responseResult) {
      char data[], result[];
      StringToCharArray(jsonBody, data, 0, StringLen(jsonBody), CP_UTF8);
      string headers = "Content-Type: application/json\r\n";
      string resultHeaders;
      
      int res = WebRequest("POST", m_serverUrl + endpoint, headers, m_timeout, data, result, resultHeaders);
      if(res == 200) {
         responseResult = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
         return true;
      }
      return false;
   }
};
```

### 6. Logger.mqh
```cpp
#include "../Utils/Common.mqh"

class CLogger {
public:
   static void Log(ENUM_LOG_LEVEL level, string message) {
      string prefix = "";
      switch(level) {
         case LOG_INFO: prefix = "[INFO] "; break;
         case LOG_WARN: prefix = "[WARN] "; break;
         case LOG_ERROR: prefix = "[ERROR] "; break;
         case LOG_DEBUG: prefix = "[DEBUG] "; break;
      }
      Print(prefix + message);
   }
};
```

---

## 次のタスク（未実装）

1. **PullbackStrategy.mqh** - `mt4-pullback-trader/mql4/Include/Lib_PullbackEngine.mqh` を参考にMQL5へ移植
2. **PullbackConfig.mqh** - パラメータ設定クラス
3. **MT5_AI_Trader.mq5** - メインEAエントリポイント
4. **推論サーバー接続テスト**

---

## 参考ファイル（mt4-pullback-trader内）

- `mql4/Include/Lib_PullbackEngine.mqh` - Pullback戦略のコアロジック
- `mql4/EA_PullbackEntry.mq4` - パラメータ定義
- `python/inference_server_hybrid.py` - 推論サーバー
- `docs/OANDA MT5 取引条件調査.md` - OANDA仕様詳細
