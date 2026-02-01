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
   PRESET_TRENDLINE,           // トレンドライン追従型
   PRESET_CHANNEL,             // チャネル逆張り型
   PRESET_AI_NOISE,            // AIノイズ対策型
   PRESET_CUSTOM = 99          // カスタム
};

//--- トレンドライン/チャネルモード (設計書セクション12-13)
enum ENUM_TL_CHANNEL_MODE
{
   MODE_EMA_ONLY = 0,          // EMAモードのみ（デフォルト）
   MODE_TRENDLINE_TREND,       // トレンドライン順張り
   MODE_CHANNEL_RANGE          // チャネル逆張り
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

   // 強トレンドモード (MT4非OOP互換: Strong_Trend_Mode + Al Brooks理論拡張)
   bool            UseStrongTrendMode;          // 強トレンドモード有効
   double          StrongTrendADXLevel;         // 強トレンドADX閾値
   bool            StrongTrendAutoActivate;     // 自動判定モード
   
   // === Al Brooks強トレンド理論拡張 ===
   int             ConsecutiveBarsCount;        // 連続陽線/陰線の最小本数
   double          LargeCandleMultiplier;       // 大陽線/大陰線判定 (ATR倍率)
   double          ShallowPullbackPercent;      // 浅いプルバック許容率 (30-50%)
   bool            UseBreakoutBarEntry;         // ブレイクアウトバー即エントリー
   double          MinBarBodyRatio;             // 最小ボディ比率 (ヒゲ少ない足)

   // === トレンドライン/チャネル設定 (設計書セクション12-13) ===
   ENUM_TL_CHANNEL_MODE TLChannelMode;          // モード選択

   // トレンドライン設定
   int             TrendLineLookbackBars;       // トレンドライン検出範囲
   int             TrendLineMinTouches;         // 最小タッチ回数
   double          TrendLineToleranceATR;       // タッチ許容幅(ATR倍率)
   bool            TrendLineAutoUpdate;         // 自動更新

   // チャネル設定
   bool            ChannelReversalOnly;         // 逆張り専用
   double          ChannelMinWidthATR;          // 最小チャネル幅(ATR倍率)
   double          ChannelMaxWidthATR;          // 最大チャネル幅(ATR倍率)
   bool            ChannelRequireParallel;      // 平行チャネル必須
   double          ChannelParallelTolerance;    // 平行許容度（傾き差の割合）

   // === AIノイズ対策 (AI_MARKET_TRANSFORMATION.md準拠) ===
   // モメンタム・イグニッション回避 (セクション5.3, 7.2B)
   bool            UseATRSpikeFilter;           // ATRスパイク検出有効
   double          ATRSpikeMultiplier;          // ATRスパイク判定倍率（平均比）
   int             ATRSpikeAvgBars;             // ATR平均計算期間
   int             ATRSpikeWaitBars;            // スパイク後の待機本数

   // 2度目の動きを狙う (セクション9.2-5)
   bool            UseSecondWaveEntry;          // 2度目のタッチでエントリー
   int             SecondWaveMinBars;           // 最初のタッチからの最小間隔
   int             SecondWaveMaxBars;           // 最初のタッチからの最大間隔

   // ストップ狩り確認後エントリー (セクション9.2-3)
   bool            UsePostStopHuntEntry;        // ストップ狩り後エントリー
   double          StopHuntSpikePoints;         // ストップ狩りスパイク幅(Points)
   int             StopHuntRecoveryBars;        // 回復確認バー数

   // === ラウンドナンバー (.00/.50) 設定 ===
   bool            UseRoundNumberLines;         // ラウンドナンバーライン使用
   bool            RN_Use_00_Line;              // .00ライン使用
   bool            RN_Use_50_Line;              // .50ライン使用
   double          RN_TouchBufferPoints;        // タッチ判定バッファ(Points)
   int             RN_LookbackBars;             // 検出期間(バー数)
   bool            RN_CounterTrend;             // 逆張りモード（反転狙い）
   int             RN_DigitLevel;               // 桁数レベル（0=整数, 2=2桁, 3=3桁）

   // ラウンドナンバー付近エントリー回避
   bool            RN_AvoidEntryNear;           // .00/.50付近でのエントリー回避
   double          RN_AvoidBufferPoints;        // 回避範囲(Points)

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
     ConsecutiveBarsCount(3),              // Al Brooks: 3本連続でトレンド確認
     LargeCandleMultiplier(1.5),           // Al Brooks: ATR1.5倍で大足判定
     ShallowPullbackPercent(40.0),         // Al Brooks: 40%戻しでエントリー
     UseBreakoutBarEntry(false),           // Al Brooks: ブレイクアウトバー即エントリー
     MinBarBodyRatio(60.0),                // Al Brooks: ボディ60%以上（ヒゲ少）
     TLChannelMode(MODE_EMA_ONLY),         // デフォルト: EMAモードのみ
     TrendLineLookbackBars(50),            // 設計書準拠: 50本
     TrendLineMinTouches(2),               // 設計書準拠: 最小2回
     TrendLineToleranceATR(0.1),           // ATR*0.1
     TrendLineAutoUpdate(true),            // 自動更新有効
     ChannelReversalOnly(true),            // 設計書準拠: 逆張り専用
     ChannelMinWidthATR(0.5),              // ATR*0.5
     ChannelMaxWidthATR(3.0),              // ATR*3.0
     ChannelRequireParallel(true),         // 設計書準拠: 平行必須
     ChannelParallelTolerance(0.3),        // 設計書準拠: 傾き差30%
     UseATRSpikeFilter(true),              // AIノイズ対策: スパイク検出有効
     ATRSpikeMultiplier(2.0),              // AIノイズ対策: ATR平均の2倍以上でスパイク
     ATRSpikeAvgBars(10),                  // AIノイズ対策: 過去10本でATR平均
     ATRSpikeWaitBars(3),                  // AIノイズ対策: スパイク後3本待機
     UseSecondWaveEntry(false),            // AIノイズ対策: 2度目エントリー（デフォルトOFF）
     SecondWaveMinBars(3),                 // AIノイズ対策: 最初のタッチから3本以上
     SecondWaveMaxBars(10),                // AIノイズ対策: 最初のタッチから10本以内
     UsePostStopHuntEntry(false),          // AIノイズ対策: ストップ狩り後（デフォルトOFF）
     StopHuntSpikePoints(100.0),           // AIノイズ対策: 10pipsスパイク
     StopHuntRecoveryBars(2),              // AIノイズ対策: 2本で回復確認
     UseRoundNumberLines(false),           // ラウンドナンバーライン（デフォルトOFF）
     RN_Use_00_Line(true),                 // .00ライン使用
     RN_Use_50_Line(true),                 // .50ライン使用
     RN_TouchBufferPoints(20.0),           // タッチバッファ2pips相当
     RN_LookbackBars(3),                   // 検出期間3本
     RN_CounterTrend(false),               // 順張りモード
     RN_DigitLevel(2),                     // FX: 2桁（100.00）
     RN_AvoidEntryNear(false),             // 付近回避（デフォルトOFF）
     RN_AvoidBufferPoints(50.0),           // 回避範囲5pips相当
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
