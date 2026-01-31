#ifndef __PULLBACK_CONFIG_MQH__
#define __PULLBACK_CONFIG_MQH__

// Pullback設定（MT4 CommonEA互換・フル機能版）

enum ENUM_PULLBACK_EMA_REF
{
   PULLBACK_EMA_12  = 0,
   PULLBACK_EMA_25  = 1,
   PULLBACK_EMA_100 = 2
};

enum ENUM_SLTP_MODE
{
   SLTP_FIXED = 0,
   SLTP_ATR   = 1
};

//--- Strategy Preset Types (MT4互換)
enum ENUM_STRATEGY_PRESET
{
   PRESET_STANDARD = 0,        // 標準型 (M15推奨) ★推奨
   PRESET_CONSERVATIVE,        // 保守型 (質重視, M30推奨)
   PRESET_AGGRESSIVE,          // 積極型 (短期・回数重視)
   PRESET_AI_SCOUT,            // AIスカウト (最大緩和)
   PRESET_AI_ADAPTIVE,         // AI適応型 (DI差+パターン)
   PRESET_MULTI_LAYER,         // マルチレイヤー (全EMA使用)
   PRESET_SESSION,             // セッション重視 (時間帯依存)
   PRESET_FULL_EDGE,           // フルエッジ (全フィルタON)
   PRESET_CUSTOM               // カスタム
};

class CPullbackConfig
{
public:
   // 基本
   long            MagicNumber;
   double          LotSize;
   int             DeviationPoints;

   // Logging / Data collection (MT4 log sync compatible)
   bool            EnableAiLearningLog;
   string          TerminalId;
   string          AiLearningFolder;

   // EMA
   int             EmaShortPeriod;
   int             EmaMidPeriod;
   int             EmaLongPeriod;
   bool            UseEmaShort;
   bool            UseEmaMid;
   bool            UseEmaLong;
   bool            RequirePerfectOrder;  // MT4互換: falseならパーフェクトオーダー不要

   // Pullback
   bool            UseTouchPullback;
   bool            UseCrossPullback;
   bool            UseBreakPullback;
   ENUM_PULLBACK_EMA_REF PullbackEmaRef;
   bool            RequirePriceBreak;
   double          EntryBreakBufferPips;
   int             PullbackLookback;           // MT4非OOP互換: 過去N本を遡ってプルバック検出

   // 確認足モード (MT4非OOP互換: Use_Confirmation_Bar)
   bool            UseConfirmationBar;          // 確認足検証を有効化
   double          ConfirmationBarMinPips;      // 確認足最小サイズ(pips)
   double          ConfirmationBarMaxPips;      // 確認足最大サイズ(pips) 0=無制限

   // EMA傾きチェック (MT4非OOP互換: CheckEMASlope)
   bool            UseEmaSlopeFilter;           // EMA傾きフィルター有効
   double          EmaMinSlopeFast;             // 短期EMA最小傾き
   double          EmaMinSlopeSlow;             // 長期EMA最小傾き
   int             EmaSlopeBars;                // 傾き計算バー数

   // ローソク足条件 (MT4非OOP互換: CheckCandleCondition)
   bool            UseCandleCondition;          // ローソク足条件チェック有効
   double          MinCandleBodyPercent;        // 最小実体比率(%)

   // 強トレンドモード (MT4非OOP互換: Strong_Trend_Mode)
   bool            UseStrongTrendMode;          // 強トレンドモード有効
   double          StrongTrendADXLevel;         // 強トレンドADX閾値
   bool            StrongTrendAutoActivate;     // 自動判定モード

   // Filters
   int             MaxSpreadPoints;
   int             ATRPeriod;
   double          ATRThresholdPoints;
   bool            UseADXFilter;
   int             ADXPeriod;
   double          ADXMinLevel;

   // Edge Enhancement Filters (MT4互換)
   bool            ADXRequireRising;
   double          DISpreadMin;
   bool            UseATRSlopeFilter;
   bool            ATRSlopeRequireRising;
   bool            UseFibFilter;
   int             FibSwingPeriod;
   double          FibMinRatio;
   double          FibMaxRatio;
   bool            UseCandlePattern;
   bool            PatternPinBar;
   bool            PatternEngulfing;
   bool            UseDivergenceFilter;

   // SL/TP
   bool            UseStopLoss;
   bool            UseTakeProfit;
   ENUM_SLTP_MODE  SLTPMode;
   double          StopLossFixedPoints;
   double          TakeProfitFixedPoints;
   double          StopLossAtrMulti;
   double          TakeProfitAtrMulti;

   // 実運用の初期値（OANDA MT5: Points単位）
   CPullbackConfig()
   : MagicNumber(0),
     LotSize(0.10),
     DeviationPoints(10),
     EnableAiLearningLog(false),
     TerminalId(""),
     AiLearningFolder("OneDriveLogs\\data\\AI_Learning"),
     EmaShortPeriod(12),
     EmaMidPeriod(25),
     EmaLongPeriod(100),
     UseEmaShort(true),
     UseEmaMid(true),
     UseEmaLong(true),
     RequirePerfectOrder(true),   // MT4非OOP版準拠: パーフェクトオーダー必須
     UseTouchPullback(true),
     UseCrossPullback(true),
     UseBreakPullback(false),
     PullbackEmaRef(PULLBACK_EMA_25),
     RequirePriceBreak(false),
     EntryBreakBufferPips(0.0),
     PullbackLookback(5),                  // MT4非OOP互換: 過去5本をデフォルト
     UseConfirmationBar(false),            // MT4非OOP互換: デフォルトfalse
     ConfirmationBarMinPips(2.0),
     ConfirmationBarMaxPips(0.0),          // 0=無制限
     UseEmaSlopeFilter(true),              // MT4非OOP互換: 傾きチェック有効
     EmaMinSlopeFast(0.0),                 // MT4非OOP互換: デフォルト0.0
     EmaMinSlopeSlow(0.0),                 // MT4非OOP互換: デフォルト0.0
     EmaSlopeBars(3),                      // MT4非OOP互換: 3本で傾き計算
     UseCandleCondition(true),             // MT4非OOP互換: デフォルトtrue
     MinCandleBodyPercent(20.0),           // MT4非OOP互換: 最小20%
     UseStrongTrendMode(false),            // MT4非OOP互換: デフォルトfalse
     StrongTrendADXLevel(30.0),            // MT4非OOP互換: ADX 30以上
     StrongTrendAutoActivate(false),       // MT4非OOP互換: 自動判定オフ
     MaxSpreadPoints(200),
     ATRPeriod(14),
     ATRThresholdPoints(30.0),
     UseADXFilter(true),
     ADXPeriod(14),
     ADXMinLevel(20.0),        // MT4非OOP版準拠
     ADXRequireRising(false),
     DISpreadMin(0),
     UseATRSlopeFilter(false),
     ATRSlopeRequireRising(false),
     UseFibFilter(false),
     FibSwingPeriod(20),
     FibMinRatio(38.2),
     FibMaxRatio(61.8),
     UseCandlePattern(true),    // デフォルトON (MT4互換)
     PatternPinBar(true),
     PatternEngulfing(true),
     UseDivergenceFilter(false),
     UseStopLoss(true),
     UseTakeProfit(true),
     SLTPMode(SLTP_FIXED),
     StopLossFixedPoints(150.0),
     TakeProfitFixedPoints(400.0), // MT4互換: RR 1:2.67
     StopLossAtrMulti(1.5),
     TakeProfitAtrMulti(2.0)
   {
   }
};

#endif
