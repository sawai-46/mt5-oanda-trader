//+------------------------------------------------------------------+
//|                                              EA_PullbackEntry_USIndex.mq4 |
//|                                  Pullback Entry Specialist System (US Index) |
//|                          トレンド中のプルバックのみを狙う専用EA (US Index版)     |
//|                          対応銘柄: US30/US500/NQ100                           |
//+------------------------------------------------------------------+
#property copyright "Pullback Entry Specialist (US Index)"
#property link      ""
#property version   "1.00"
#property strict

// Market Sentinel連携（経済指標・要人発言による売買制御）※サービス削除済み - 無効
// #include <MarketSentinel.mqh>  // サービス削除済み - 不要

// マジックナンバー自動生成
#include <MagicNumberGenerator.mqh>

// TradeOptimizer連携（最適化パラメータ自動読み込み）※サービス削除済み - 無効
// #include <EAParamsLoader.mqh>  // サービス削除済み - 不要

//+------------------------------------------------------------------+
//| US Index Symbol Type                                              |
//+------------------------------------------------------------------+
enum US_INDEX_TYPE {
   INDEX_US30,    // US30 (Dow Jones)
   INDEX_US500,   // US500 (S&P 500)
   INDEX_NQ100,   // NQ100 (NASDAQ 100)
   INDEX_UNKNOWN  // Unknown
};

//--- シンボル選択モード
enum SYMBOL_SELECT_MODE {
   SYMBOL_AUTO,   // 自動検出（チャートのシンボルに従う）
   SYMBOL_US30,   // US30固定
   SYMBOL_US500,  // US500固定
   SYMBOL_NQ100   // NQ100固定
};

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
// Pullback EMA Reference
enum PullbackEMAReference {
   PULLBACK_EMA_12,   // EMA12を基準
   PULLBACK_EMA_25,   // EMA25を基準
   PULLBACK_EMA_100   // EMA100を基準
};

// SLTP Mode
enum SLTPMode {
   SLTP_FIXED,    // 固定ポイント
   SLTP_ATR       // ATR基準
};

// Trailing Mode
enum TrailingMode {
   TRAILING_FIXED_POINTS,   // 固定ポイント
   TRAILING_ATR           // ATR連動
};

// Trading Strategy Preset
enum TradingStrategy {
   STRATEGY_STANDARD,           // 標準型（RELAXEDベース、M15推奨）★推奨
   STRATEGY_CONSERVATIVE,       // 保守型（厳しめフィルター、質重視、M30推奨）
   STRATEGY_AGGRESSIVE,         // 積極型（フィルターなし、量重視、M5推奨）★推奨
   STRATEGY_AI_ADAPTIVE,        // AI適応型（HFTノイズ除外+アルゴレベル検出、M5推奨）★NEW
   STRATEGY_AI_SCOUT,           // AIスカウト型（データ収集+パターン学習、全時間足対応）★実験
   STRATEGY_MULTI_LAYER,        // マルチレイヤー（EMA+ラウンドナンバー+トレンドライン）
   STRATEGY_CUSTOM,             // カスタム（手動設定）
   // --- 以下は非推奨（バックテスト結果不良またはコンセプト重複、コメントアウト） ---
   // STRATEGY_BALANCED,        // バランス型（段階利確）→ STANDARDと重複
   // STRATEGY_HIGH_ACCURACY,   // 高精度型（厳格化）→ CONSERVATIVEと重複
   // STRATEGY_SCALPING,        // スキャルピング型 → 実用性低い
   // STRATEGY_TREND_RIDER,     // トレンド継続型（オリジナル）→ 古いバージョン
   // STRATEGY_TREND_RIDER_V2,  // トレンド継続型V2（改良版）→ 中間バージョン
   // STRATEGY_TREND_RIDER_V3,  // トレンド継続型V3（バランス型ベース）→ STANDARDに統合
   // STRATEGY_HYBRID,          // ハイブリッド型（レンジ対応）→ 結果不安定
   // STRATEGY_TRENDLINE,       // トレンドライン順張り → MULTI_LAYERで対応
   // STRATEGY_CHANNEL_RANGE,   // チャネルレンジ逆張り → MULTI_LAYERで対応
   // STRATEGY_ENV_FILTER_STRICT,   // 環境フィルター厳格型 → CONSERVATIVEに統合
   // STRATEGY_ENV_FILTER_MODERATE, // 環境フィルター標準型 → STANDARDに統合
   // STRATEGY_ENV_FILTER_RELAXED,  // 環境フィルター緩和型 → STANDARDに改名
   // STRATEGY_ENV_FILTER_OPTIMIZED,// 環境フィルター最適化型 → AGGRESSIVEに統合
   // STRATEGY_V3_FILTERED,     // V3+環境フィルター（最強版）→ STANDARDに統合
};

// Trendline/Channel Mode
enum TrendlineChannelMode {
   MODE_DISABLED,               // 無効
   MODE_TRENDLINE_TREND,        // トレンドライン（順張り）
   MODE_CHANNEL_RANGE,          // チャネル（逆張り）
   MODE_CHANNEL_BREAKOUT        // チャネルブレイクアウト（順張り）
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
//--- 戦略選択
input TradingStrategy Selected_Strategy = STRATEGY_STANDARD;  // 使用する戦略

//--- 複数MT4対応
input string MT4_ID = "10900k-A";                // MT4識別ID（10900k-A, 10900k-B, matsu-A, matsu-B）

//--- シンボル選択設定
input SYMBOL_SELECT_MODE SymbolMode = SYMBOL_AUTO; // シンボル選択モード

//--- 基本設定
input bool   AutoMagicNumber = true;            // マジックナンバー自動生成
input int    MagicNumber = 22501;                // マジックナンバー（自動生成時は無視）
input double BaseLotSize = 0.1;                  // 基準ロットサイズ（US30: 0.01, US500: 0.1）
input double MaxLotSize = 1.0;                   // 最大ロットサイズ（上限）
input bool   EnableLotAdjustment = true;         // ロット自動調整有効化
input bool   EnableDebugLog = true;              // デバッグログ有効化

//--- EMA設定
input int    EMA_Short_Period = 12;              // 短期EMA期間
input int    EMA_Mid_Period = 25;                // 中期EMA期間
input int    EMA_Long_Period = 100;              // 長期EMA期間

//--- トレンド判定設定【絶対条件】
input bool   Require_Perfect_Order = true;       // パーフェクトオーダー必須
input double EMA_Min_Slope_Fast = 0.0001;        // 短期EMA最小傾き(0=無効)
input double EMA_Min_Slope_Slow = 0.00005;       // 長期EMA最小傾き(0=無効)
input int    EMA_Slope_Bars = 3;                 // 傾き計算期間(バー数)

//--- MTFフィルター設定【絶対条件】
input bool             Use_MTF_Filter1 = false;              // MTFフィルター1使用
input ENUM_TIMEFRAMES  MTF_Timeframe1 = PERIOD_H1;           // MTF時間足1
input int              MTF_EMA_Period1 = 25;                 // MTF判定用EMA期間1
input bool             MTF_Require_Perfect_Order1 = true;    // MTF1でパーフェクトオーダー必須

input bool             Use_MTF_Filter2 = false;              // MTFフィルター2使用
input ENUM_TIMEFRAMES  MTF_Timeframe2 = PERIOD_H4;           // MTF時間足2
input int              MTF_EMA_Period2 = 25;                 // MTF判定用EMA期間2
input bool             MTF_Require_Perfect_Order2 = true;    // MTF2でパーフェクトオーダー必須

input bool             Use_MTF_Filter3 = false;              // MTFフィルター3使用
input ENUM_TIMEFRAMES  MTF_Timeframe3 = PERIOD_D1;           // MTF時間足3
input int              MTF_EMA_Period3 = 25;                 // MTF判定用EMA期間3
input bool             MTF_Require_Perfect_Order3 = true;    // MTF3でパーフェクトオーダー必須

//--- プルバック検出設定
input bool   Use_Touch_Pullback = true;          // EMAタッチプルバック
input bool   Use_Cross_Pullback = true;          // EMAクロスプルバック
input bool   Use_Break_Pullback = false;         // EMA完全ブレイクプルバック（終値基準）
input PullbackEMAReference Pullback_EMA = PULLBACK_EMA_25;  // プルバック基準EMA
input int    Pullback_Lookback = 5;              // プルバック探索範囲(1-10本)

//--- 強トレンドモード設定（押し目待ちに押し目なし対策）
input bool   Use_Strong_Trend_Mode = false;      // 強トレンドモード使用（ADX高値時にEMA12タッチで即エントリー）
input double Strong_Trend_ADX_Level = 30.0;      // 強トレンド判定ADX閾値（30以上推奨）
input bool   Auto_Strong_Trend_Mode = false;     // 強トレンドモード自動ON/OFF（★実験的機能）
input double Auto_ATR_Spike_Threshold = 1.5;     // ATRスパイク閾値（1.5倍以上で自動ON）
input double Auto_Volume_Surge_Threshold = 2.0;  // ボリューム急増閾値（2倍以上で自動ON）
input int    Auto_Detection_Period = 5;          // 異常検知期間（バー数）

//--- エントリートリガー設定
input bool   Use_Immediate_Entry = true;         // 即座エントリー（プルバック検出足の高値/安値ブレイク）
input bool   Use_Confirmation_Bar = false;       // 確認足使用（次の足を待つ）
input double Confirmation_Bar_Min_Size = 50.0;    // 確認足最小サイズ（指数ポイント/価格差）
input double Confirmation_Bar_Max_Size = 200.0;   // 確認足最大サイズ（指数ポイント/価格差、0=無制限）

//--- ローソク足条件
input bool   Require_Bullish_Candle_Long = true;    // ロング時に陽線必須
input bool   Require_Bearish_Candle_Short = true;   // ショート時に陰線必須
input double Min_Candle_Body_Percent = 50.0;        // 実体最小比率(%)

//--- Volman式プライスアクション設定【補助条件】
input bool   Use_Volman_Patterns = true;         // Volman式パターン使用
input bool   Use_Double_Bar_Breakout = true;     // ダブルバーブレイクアウト
input bool   Use_IRB = true;                     // IRB（インサイドバーリバーサル）
input bool   Use_Failed_Break_Reversal = true;   // フェイルドブレイクリバーサル
input int    Volman_Lookback = 5;                // パターン探索範囲(2-10本)

//--- MACD設定【補助条件】
input bool   Use_MACD = true;                    // MACD反転検出使用
input int    MACD_FastEMA = 12;                  // MACD Fast EMA
input int    MACD_SlowEMA = 26;                  // MACD Slow EMA
input int    MACD_Signal = 9;                    // MACD Signal

//--- 失敗ブレイク設定【補助条件】
input bool   Use_FailedBreak = true;             // 失敗ブレイク検出使用
input int    BB_Period = 20;                     // BB期間
input double BB_Deviation = 2.0;                 // BB偏差
input bool   BB_Use_EMA_Middle = true;           // BBミドルラインをEMAで計算

//--- 補助条件設定
input int    Entry_Confirmations = 2;            // 必要な補助条件数(0-6)

//--- エントリー基本設定
input double Entry_Buffer_Points = 20.0;            // ブレイクバッファ（指数ポイント/価格差）
input double Max_Slippage_Pips = 50.0;              // 最大スリッページ（指数ポイント/価格差） ※推奨
input int    Max_Slippage_Points = 0;               // 最大スリッページ（MT4 points） ※互換用、0=Max_Slippage_Pips使用
input double Max_Spread_Points = 20.0;             // 最大スプレッド（指数ポイント/価格差） ※通常5-10指数ポイント程度

//--- ATR設定
input int    ATR_Period = 14;                    // ATR期間
input double ATR_Threshold_Points = 30.0;        // ATR最低値（指数ポイント/価格差） ※US Index推奨値

//--- 相場環境フィルター（レンジ相場回避）
input bool   Use_ADX_Filter = true;              // ADXフィルター使用
input int    ADX_Period = 14;                    // ADX期間
input double ADX_Min_Level = 20.0;               // ADX最低値（20以下=レンジ）
input double Max_Spread_Multiplier = 3.0;        // 通常スプレッドの何倍まで許容
input bool   Use_Channel_Width_Filter = true;    // チャネル幅フィルター使用
input int    Channel_Width_Period = 20;          // チャネル幅計算期間
input double Min_Channel_Width_Points = 100.0;   // 最低チャネル幅（指数ポイント/価格差） ※US Index推奨値

//--- SL/TP設定
input bool   Use_StopLoss = true;                // SL使用
input bool   Use_TakeProfit = true;              // TP使用
input SLTPMode SLTP_Mode = SLTP_FIXED;           // SLTP モード
input double StopLoss_Fixed_Points = 100.0;         // 固定SL（指数ポイント） ※US Index推奨値
input double TakeProfit_Fixed_Points = 200.0;       // 固定TP（指数ポイント） ※US Index推奨値
input double StopLoss_ATR_Multi = 1.5;           // SL用ATR倍率
input double TakeProfit_ATR_Multi = 2.0;         // TP用ATR倍率

//--- 段階的利確設定
input bool   EnablePartialClose = false;         // 段階的利確有効化
input int    PartialCloseLevels = 2;             // 利確レベル数(1, 2, 3)
input bool   UseTPForFinalLevel = true;          // 最終レベルをMT4のTPとして設定
input double PartialClosePercent1 = 50.0;        // 第1利確割合(%)
input double PartialCloseLevel1_Points = 50.0;      // 第1利確レベル（指数ポイント） ※US Index推奨値
input double PartialClosePercent2 = 50.0;        // 第2利確割合(%)
input double PartialCloseLevel2_Points = 100.0;     // 第2利確レベル（指数ポイント） ※US Index推奨値
input double PartialClosePercent3 = 0.0;         // 第3利確割合(%)
input double PartialCloseLevel3_Points = 150.0;     // 第3利確レベル（指数ポイント） ※US Index推奨値

//--- 建値移動設定
input bool   MoveToBreakevenOnPartial1 = true;   // 第1利確でSLを建値へ
input bool   MoveToTP1OnPartial2 = false;        // 第2利確でSLを第1利確価格へ
input double BreakevenOffset_Points = 20.0;         // 建値オフセット（指数ポイント） ※US Index推奨値

//--- トレーリングストップ設定
input bool   EnableTrailingAfterTP2 = false;     // 第2利確後トレーリング
input TrailingMode Trailing_Mode = TRAILING_ATR; // トレーリングモード
input double TrailingStop_Fixed_Points = 50.0;      // 固定ポイント幅 ※US Index推奨値
input double TrailingStop_ATR_Multi = 1.0;       // ATR倍率
input int    Trailing_ATR_Period = 14;           // トレーリング用ATR期間
input double TrailingUpdate_Step_Points = 20.0;     // 更新ステップ（指数ポイント） ※US Index推奨値

//--- トレンドライン/チャネル設定
input TrendlineChannelMode TL_Channel_Mode = MODE_DISABLED;  // モード選択
input string TL_Upper_Name = "TL_Upper";         // 上限ライン名（チャネル上限/下降トレンドライン）
input string TL_Lower_Name = "TL_Lower";         // 下限ライン名（チャネル下限/上昇トレンドライン）
input double TL_Touch_Buffer_Points = 20.0;      // タッチ判定バッファ（指数ポイント/価格差）
input bool   TL_Use_Touch = true;                // タッチパターン
input bool   TL_Use_Cross = true;                // クロスパターン
input bool   TL_Use_Break = false;               // ブレイクパターン
input int    TL_Lookback_Bars = 3;               // 検出期間(バー数)

//--- プライスアクション反転パターン設定（チャネル逆張り用）
input bool   PA_Require_Reversal = true;         // 反転パターン必須
input bool   PA_Use_Pinbar = true;               // ピンバー検出
input bool   PA_Use_Engulfing = true;            // エンゴルフィング検出
input double PA_Pinbar_Shadow_Ratio = 2.0;       // ピンバー影/実体比率
input double PA_Pinbar_Opposite_Shadow_Ratio = 0.5; // 反対側影/実体比率

//--- ラウンドナンバー設定
input bool   Use_RoundNumber_Lines = false;      // ラウンドナンバーライン使用
input bool   RN_Use_00_Line = true;              // 000/500ライン使用
input bool   RN_Use_50_Line = true;              // 250/750ライン使用（オプション）
input double RN_Touch_Buffer_Points = 30.0;      // タッチ判定バッファ（指数ポイント/価格差）
input bool   RN_Use_Touch = true;                // タッチパターン
input bool   RN_Use_Cross = true;                // クロスパターン
input bool   RN_Use_Break = false;               // ブレイクパターン
input int    RN_Lookback_Bars = 3;               // 検出期間(バー数)
input bool   RN_Counter_Trend = false;           // 逆張りモード（反転狙い）
input int    RN_Digit_Level = 0;                 // 桁数レベル（0=39000, 1=39100）

//--- ラウンドナンバー付近エントリー回避設定
input bool   RN_Avoid_Entry_Near = false;        // 1000/500付近でのエントリー回避
input double RN_Avoid_Buffer_Points = 50.0;      // 回避範囲（指数ポイント/価格差） ※プルバックタッチ時は除外

//--- マルチレイヤー設定
input bool   ML_Require_EMA = true;              // EMAレイヤー必須
input bool   ML_Require_Trendline = false;       // トレンドライン/チャネルレイヤー必須
input bool   ML_Require_RoundNumber = false;     // ラウンドナンバーレイヤー必須
input int    ML_Min_Layers = 1;                  // 最小一致レイヤー数（1-3）
input bool   ML_Bonus_Multi_Layer = true;        // 複数レイヤー一致時ボーナス

//--- AI対応設定（GPU不要、軽量アルゴリズム）
input bool   Use_Micro_Volatility_Filter = false; // マイクロボラティリティフィルター（HFTノイズ除外）
input double Min_Bar_Range_Pips = 30.0;          // 最小バーサイズ（指数ポイント/価格差） - これ未満はノイズ
input int    Noise_Detection_Period = 10;       // ノイズ検出期間(バー数)
input double Noise_Ratio_Threshold = 0.6;       // ノイズ比率閾値(0.0-1.0)

input bool   Use_Algo_Price_Levels = false;     // アルゴ価格レベル検出
input double Algo_Price_Clustering = 50.0;      // 価格集中度（指数ポイント/価格差） - アルゴ反応範囲
input bool   Use_Quarter_Levels = true;         // 0.25刻みレベル使用（AIの好む価格帯）

input bool   Use_OrderFlow_Detection = false;   // オーダーフロー検出（ティックボリューム分析）
input double OrderFlow_Volume_Multi = 2.0;      // ボリューム倍率（この倍以上で大量注文）
input int    OrderFlow_Avg_Period = 9;          // 平均ボリューム計算期間

input bool   Use_Algo_TimeFilter = false;       // アルゴ活発時間帯フィルター
input int    Algo_Active_Start_Hour = 21;       // アルゴ活発開始時刻(JST)
input int    Algo_Active_End_Hour = 24;         // アルゴ活発終了時刻(JST)

input bool   Enable_AI_Learning_Log = true;     // AI学習用ログ出力（DLL推論EA用データ収集）

//--- 時間フィルター設定
input bool   Enable_Time_Filter = false;         // 時間フィルター有効化
input int    GMT_Offset = 3;                     // GMTオフセット
input bool   Use_DST = false;                    // 夏時間適用
input int    Custom_Start_Hour = 8;              // 稼働開始時(日本時間)
input int    Custom_Start_Minute = 0;            // 稼働開始分
input int    Custom_End_Hour = 21;               // 稼働終了時(日本時間)
input int    Custom_End_Minute = 0;              // 稼働終了分

//--- ログ出力設定
input bool   EnableCsvLogging = true;            // CSVログ出力を有効化
input bool   LogSkipEvents = true;               // スキップ理由も記録
input string CsvLogFolder = "OneDriveLogs";      // ログ保存ルートフォルダ（自動でサブフォルダ作成）
input int    SkipLogCooldownSeconds = 60;        // 同一スキップログの抑制秒数

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
// 戦略設定用変数（プリセットで上書き可能）
double g_StopLoss_Points;
double g_TakeProfit_Points;
bool g_EnablePartialClose;
int g_PartialCloseLevels;
double g_PartialClosePercent1;
double g_PartialCloseLevel1_Points;
double g_PartialClosePercent2;
double g_PartialCloseLevel2_Points;
double g_PartialClosePercent3;
double g_PartialCloseLevel3_Points;
bool g_MoveToBreakevenOnPartial1;
double g_BreakevenOffset_Points;
bool g_EnableTrailingAfterTP2;
TrailingMode g_Trailing_Mode;
double g_TrailingStop_Fixed_Points;
double g_TrailingStop_ATR_Multi;
double g_TrailingUpdate_Step_Points;
int g_Entry_Confirmations;
double g_Min_Candle_Body_Percent;
bool g_Use_MTF_Filter1;
ENUM_TIMEFRAMES g_MTF_Timeframe1;
bool g_MTF_Require_Perfect_Order1;
bool g_Use_MTF_Filter2;
ENUM_TIMEFRAMES g_MTF_Timeframe2;
bool g_MTF_Require_Perfect_Order2;
bool g_Require_Perfect_Order;
double g_EMA_Min_Slope_Fast;
double g_EMA_Min_Slope_Slow;
bool g_Use_FailedBreak;
bool g_Use_Failed_Break_Reversal;
bool g_Use_Immediate_Entry;
bool g_Use_Confirmation_Bar;
double g_Confirmation_Bar_Min_Size;
double g_Confirmation_Bar_Max_Size;
bool g_Use_Touch_Pullback;
bool g_Use_Cross_Pullback;
bool g_Use_Break_Pullback;

// 強トレンドモード
bool g_Use_Strong_Trend_Mode;
double g_Strong_Trend_ADX_Level;
bool g_Auto_Strong_Trend_Mode;
double g_Auto_ATR_Spike_Threshold;
double g_Auto_Volume_Surge_Threshold;
int g_Auto_Detection_Period;

// トレンドライン/チャネル設定用変数
TrendlineChannelMode g_TL_Channel_Mode;
string g_TL_Upper_Name;
string g_TL_Lower_Name;
double g_TL_Touch_Buffer_Points;
bool g_TL_Use_Touch;
bool g_TL_Use_Cross;
bool g_TL_Use_Break;
int g_TL_Lookback_Bars;
bool g_PA_Require_Reversal;
bool g_PA_Use_Pinbar;
bool g_PA_Use_Engulfing;
double g_PA_Pinbar_Shadow_Ratio;
double g_PA_Pinbar_Opposite_Shadow_Ratio;

// ラウンドナンバー設定用変数
bool g_Use_RoundNumber_Lines;
bool g_RN_Use_00_Line;
bool g_RN_Use_50_Line;
double g_RN_Touch_Buffer_Points;
bool g_RN_Use_Touch;
bool g_RN_Use_Cross;
bool g_RN_Use_Break;
int g_RN_Lookback_Bars;
bool g_RN_Counter_Trend;
int g_RN_Digit_Level;

// マルチレイヤー設定用変数
bool g_ML_Require_EMA;
bool g_ML_Require_Trendline;
bool g_ML_Require_RoundNumber;
int g_ML_Min_Layers;
bool g_ML_Bonus_Multi_Layer;

// 環境フィルター設定用変数
bool g_Use_ADX_Filter;
double g_ADX_Min_Level;
bool g_Use_Channel_Width_Filter;
double g_Min_Channel_Width_Points;
double g_ATR_Threshold_Points;

// EMA値
double ema12_current, ema12_previous;
double ema25_current, ema25_previous;
double ema100_current, ema100_previous;

// ATR値
double current_atr;

// 価格情報
double prev_high = 0;
double prev_low = 0;
double pip = 1.0;        // US Index/日経225では常に1.0
double point_size;       // Point値

// US Indexタイプ判定
US_INDEX_TYPE g_indexType = INDEX_UNKNOWN;
double g_symbolMinLot = 0.1;

// ポジション管理
int current_ticket = -1;
bool partial1_executed = false;
bool partial2_executed = false;
bool partial3_executed = false;
bool trailing_active = false;
double highest_price_trailing = 0;
double lowest_price_trailing = 0;

// ラウンドナンバー検出フラグ
bool roundnumber_entry_detected = false;  // ラウンドナンバー(1000/500)でエントリー予定

// ラウンドナンバー回避設定用変数
bool g_RN_Avoid_Entry_Near;
double g_RN_Avoid_Buffer_Points;

// AI対応用グローバル変数
bool g_Use_Micro_Volatility_Filter;
double g_Min_Bar_Range_Pips;
double g_Min_Bar_Range_Points;  // 指数ポイント/価格単位
int g_Noise_Detection_Period;

// スリッページ変換関数（指数ポイント/価格差 → MT4 points）
int EffectiveSlippagePoints(){
   // Max_Slippage_Pips（指数ポイント/価格差）が0より大きければ優先使用
   if(Max_Slippage_Pips > 0.0){
      // US Index例: 1.00（指数ポイント）= 100 MT4 points（Point=0.01 の場合）
      return (int)MathRound(Max_Slippage_Pips * 1.0 / Point);
   }
   // 互換用: Max_Slippage_Pointsをそのまま使用
   return Max_Slippage_Points;
}
double g_Noise_Ratio_Threshold;
bool g_Use_Algo_Price_Levels;
double g_Algo_Price_Clustering;
bool g_Use_Quarter_Levels;
bool g_Use_OrderFlow_Detection;
double g_OrderFlow_Volume_Multi;
int g_OrderFlow_Avg_Period;
bool g_Use_Algo_TimeFilter;
int g_Algo_Active_Start_Hour;
int g_Algo_Active_End_Hour;
bool g_Enable_AI_Learning_Log;
string g_AI_Learning_LogFile;
string g_AI_Learning_Folder;
string g_Trade_History_Folder;
string g_Trade_LogFile;

// AI学習データ統計
int ai_pattern_count = 0;
double ai_total_profit = 0.0;
double ai_total_loss = 0.0;

// ログ管理
string csv_file_path = "";
datetime last_skip_log_time = 0;
string last_skip_reason = "";

// 実際に使用するマジックナンバー（自動生成または手動設定）
int g_ActiveMagicNumber = 0;

// プルバック検出状態
bool pullback_detected = false;
string pullback_type = "";
datetime pullback_bar_time = 0;
double pullback_entry_level = 0;
bool is_pullback_long = false;
bool confirmation_bar_validated = false;  // 確認足が条件を満たしたか

// AI対応関数群をインクルード（グローバル変数宣言後）
// ※Nikkei版を流用（指数ポイント/価格単位のためUS Indexでも動作）
#include "EA_AI_Functions_Nikkei.mqh"

//+------------------------------------------------------------------+
//| シンボルタイプ判定                                                |
//+------------------------------------------------------------------+
US_INDEX_TYPE DetectIndexType()
{
   // 手動選択モードの場合
   if(SymbolMode == SYMBOL_US30)
      return INDEX_US30;
   if(SymbolMode == SYMBOL_US500)
      return INDEX_US500;
   if(SymbolMode == SYMBOL_NQ100)
      return INDEX_NQ100;
   
   // 自動検出モード
   string sym = Symbol();
   StringToUpper(sym);
   
   if(StringFind(sym, "US30") >= 0 || StringFind(sym, "DOW") >= 0 || StringFind(sym, "DJI") >= 0)
      return INDEX_US30;
   
   if(StringFind(sym, "US500") >= 0 || StringFind(sym, "SPX") >= 0 || StringFind(sym, "SP500") >= 0)
      return INDEX_US500;
   
   // NQ100: NQ100, NAS100, NASDAQ, USTEC, NDX などに対応
   if(StringFind(sym, "NQ100") >= 0 || StringFind(sym, "NAS100") >= 0 || StringFind(sym, "NASDAQ") >= 0 ||
      StringFind(sym, "USTEC") >= 0 || StringFind(sym, "NDX") >= 0 || StringFind(sym, "NAS") >= 0)
      return INDEX_NQ100;
   
   return INDEX_UNKNOWN;
}

//+------------------------------------------------------------------+
//| シンボル別最小ロット取得                                          |
double GetSymbolMinLot()
{
   switch(g_indexType)
   {
      case INDEX_US30:  return 0.01;   // US30は0.01lot
      case INDEX_US500: return 0.1;    // US500は0.1lot
      case INDEX_NQ100: return 0.1;    // NQ100は0.1lot
      default:          return MarketInfo(Symbol(), MODE_MINLOT);
   }
}

//+------------------------------------------------------------------+
//| シンボル名取得（ログ用）                                          |
//+------------------------------------------------------------------+
string GetIndexName()
{
   switch(g_indexType)
   {
      case INDEX_US30:  return "US30 (Dow Jones)";
      case INDEX_US500: return "US500 (S&P 500)";
      case INDEX_NQ100: return "NQ100 (NASDAQ 100)";
      default:          return "Unknown US Index";
   }
}

//+------------------------------------------------------------------+
//| 銘柄別デフォルトパラメータ情報表示                                  |
//+------------------------------------------------------------------+
void ApplySymbolDefaults()
{
   if(g_indexType == INDEX_US30)
   {
      Print("=== US30推奨設定 ===");
      Print("  SL: 100-150 指数ポイント, TP: 200-300 指数ポイント");
      Print("  ATR閾値: 30-50 指数ポイント");
      Print("  最小ロット: 0.01");
   }
   else if(g_indexType == INDEX_US500)
   {
      Print("=== US500推奨設定 ===");
      Print("  SL: 30-50 指数ポイント, TP: 60-100 指数ポイント");
      Print("  ATR閾値: 15-30 指数ポイント");
      Print("  最小ロット: 0.1");
      Print("  ※現在の設定はUS30向けです。US500ではパラメータ調整を推奨します。");
   }
   else if(g_indexType == INDEX_NQ100)
   {
      Print("=== NQ100推奨設定 ===");
      Print("  SL: 50-100 指数ポイント, TP: 100-200 指数ポイント");
      Print("  ATR閾値: 20-40 指数ポイント");
      Print("  最小ロット: 0.01");
      Print("  ※現在の設定はUS30向けです。NQ100ではパラメータ調整を推奨します。");
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Market Sentinel初期化
   // MS_Init();  // サービス削除済み - 不要
   
   // US Indexタイプ判定
   g_indexType = DetectIndexType();
   g_symbolMinLot = GetSymbolMinLot();
   
   if(g_indexType == INDEX_UNKNOWN)
   {
      Print("[WARNING] サポートされていないシンボルです: ", Symbol());
      Print("  対応銘柄: US30, US500");
      Print("  続行しますが、ロットサイズに注意してください");
   }
   
   // 銘柄別デフォルト情報表示
   ApplySymbolDefaults();
   
   // EA パラメータローダー初期化（TradeOptimizer連携）
   // EAP_Init();  // サービス削除済み - 不要
   
   // マジックナンバー初期化（US Index: PullbackEntry系のEAタイプを使用）
   if (AutoMagicNumber) {
      int preset_code = PRESET_STANDARD;
      switch(Selected_Strategy) {
         case STRATEGY_STANDARD:      preset_code = PRESET_STANDARD; break;
         case STRATEGY_CONSERVATIVE:  preset_code = PRESET_CONSERVATIVE; break;
         case STRATEGY_AGGRESSIVE:    preset_code = PRESET_AGGRESSIVE; break;
         case STRATEGY_AI_ADAPTIVE:   preset_code = PRESET_AI_ADAPTIVE; break;
         case STRATEGY_AI_SCOUT:      preset_code = PRESET_AI_SCOUT; break;
         case STRATEGY_MULTI_LAYER:   preset_code = PRESET_MULTI_LAYER; break;
         case STRATEGY_CUSTOM:        preset_code = PRESET_CUSTOM; break;
      }
      // US Index: PullbackEntryのEAタイプを使用（ペアコードは自動判定）
      g_ActiveMagicNumber = GenerateMagicNumber(EA_TYPE_PULLBACK_ENTRY, Symbol(), preset_code);
      Print("マジックナンバー自動生成: ", g_ActiveMagicNumber);
      PrintMagicNumberInfo(g_ActiveMagicNumber);
   } else {
      g_ActiveMagicNumber = MagicNumber;
      Print("マジックナンバー手動設定: ", g_ActiveMagicNumber);
   }
   
   // 戦略プリセット適用
   ApplyStrategyPreset();
   
   // US Indexでは1ポイント=1なので計算不要
   point_size = Point;
   
   // トレンドライン/チャネル設定
   g_TL_Channel_Mode = TL_Channel_Mode;
   g_TL_Upper_Name = TL_Upper_Name;
   g_TL_Lower_Name = TL_Lower_Name;
   g_TL_Touch_Buffer_Points = TL_Touch_Buffer_Points;
   g_TL_Use_Touch = TL_Use_Touch;
   g_TL_Use_Cross = TL_Use_Cross;
   g_TL_Use_Break = TL_Use_Break;
   g_TL_Lookback_Bars = TL_Lookback_Bars;
   g_PA_Require_Reversal = PA_Require_Reversal;
   g_PA_Use_Pinbar = PA_Use_Pinbar;
   g_PA_Use_Engulfing = PA_Use_Engulfing;
   g_PA_Pinbar_Shadow_Ratio = PA_Pinbar_Shadow_Ratio;
   g_PA_Pinbar_Opposite_Shadow_Ratio = PA_Pinbar_Opposite_Shadow_Ratio;
   
   // ラウンドナンバー設定
   g_Use_RoundNumber_Lines = Use_RoundNumber_Lines;
   g_RN_Use_00_Line = RN_Use_00_Line;
   g_RN_Use_50_Line = RN_Use_50_Line;
   g_RN_Touch_Buffer_Points = RN_Touch_Buffer_Points;
   g_RN_Use_Touch = RN_Use_Touch;
   g_RN_Use_Cross = RN_Use_Cross;
   g_RN_Use_Break = RN_Use_Break;
   g_RN_Lookback_Bars = RN_Lookback_Bars;
   g_RN_Counter_Trend = RN_Counter_Trend;
   g_RN_Digit_Level = RN_Digit_Level;
   
   // ラウンドナンバー付近回避設定
   g_RN_Avoid_Entry_Near = RN_Avoid_Entry_Near;
   g_RN_Avoid_Buffer_Points = RN_Avoid_Buffer_Points;
   
   // マルチレイヤー設定
   g_ML_Require_EMA = ML_Require_EMA;
   g_ML_Require_Trendline = ML_Require_Trendline;
   g_ML_Require_RoundNumber = ML_Require_RoundNumber;
   g_ML_Min_Layers = ML_Min_Layers;
   g_ML_Bonus_Multi_Layer = ML_Bonus_Multi_Layer;
   
   // CSVログ初期化
   if (EnableCsvLogging) {
      InitializeCsvLog();
   }
   
   // 初期ATR確認
   double init_atr = iATR(Symbol(), 0, ATR_Period, 1);
   double init_atr_price = init_atr;
   double init_atr_mt4pt = (Point > 0.0) ? (init_atr_price / Point) : 0.0;
   
   Print("===== EA_PullbackEntry (US Index) 初期化完了 =====");
   Print("対応銘柄: ", GetIndexName());
   Print("シンボル: ", Symbol());
   Print("時間足: ", Period());
   Print("Digits: ", Digits);
   Print("最小ロット: ", DoubleToString(g_symbolMinLot, 2));
   Print("プルバック基準EMA: ", GetEMAName(Pullback_EMA));
   Print("EMAタッチ: ", Use_Touch_Pullback);
   Print("EMAクロス: ", Use_Cross_Pullback);
   Print("EMA完全ブレイク: ", g_Use_Break_Pullback);
   Print("ATR期間: ", ATR_Period);
   // g_ATR_Threshold_Points は「価格差（指数ポイント/price units）」として扱う（従来挙動を維持）
   if (Point > 0.0) {
      Print("ATR閾値設定: ", DoubleToString(g_ATR_Threshold_Points, 2), " (price units) / ", DoubleToString(g_ATR_Threshold_Points / Point, 0), " (MT4 points)");
      Print("現在のATR: ", DoubleToString(init_atr_price, Digits), " (price units) / ", DoubleToString(init_atr_mt4pt, 0), " (MT4 points)");
   } else {
      Print("ATR閾値設定: ", DoubleToString(g_ATR_Threshold_Points, 2), " (price units)");
      Print("現在のATR: ", DoubleToString(init_atr_price, Digits), " (price units)");
   }
   
   // 補助条件情報
   Print("===== 補助条件設定 =====");
   Print("必要補助条件数: ", Entry_Confirmations);
   Print("Volmanパターン: ", Use_Volman_Patterns);
   Print("  - ダブルバー: ", Use_Double_Bar_Breakout);
   Print("  - IRB: ", Use_IRB);
   Print("  - フェイルドブレイクリバーサル: ", Use_Failed_Break_Reversal);
   Print("MACD反転: ", Use_MACD);
   Print("失敗ブレイク: ", Use_FailedBreak);
   
   // MTFフィルター情報
   if (Use_MTF_Filter1) {
      Print("MTFフィルター1: ", EnumToString(MTF_Timeframe1), " EMA", MTF_EMA_Period1, 
            " PO=", MTF_Require_Perfect_Order1);
   }
   if (Use_MTF_Filter2) {
      Print("MTFフィルター2: ", EnumToString(MTF_Timeframe2), " EMA", MTF_EMA_Period2,
            " PO=", MTF_Require_Perfect_Order2);
   }
   if (Use_MTF_Filter3) {
      Print("MTFフィルター3: ", EnumToString(MTF_Timeframe3), " EMA", MTF_EMA_Period3,
            " PO=", MTF_Require_Perfect_Order3);
   }
   
   // TradeOptimizer連携情報
   Print("===== TradeOptimizer連携 =====");
   Print("サービス削除済み - 無効");
   Print("=====================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA_PullbackEntry 終了: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // ===== 起動直後のエントリー防止 =====
   // EA起動後、最低1本のバーが完成するまでエントリーをスキップ
   static int warmup_bars = 0;
   static bool warmup_complete = false;
   
   // Market Sentinelによる売買許可チェック（毎分更新）
   // サービス削除済み - 不要
   
   // EA パラメータ更新チェック（TradeOptimizer連携）
   // EAP_CheckUpdate();  // サービス削除済み - 不要
   
   // 新しいバーのチェック
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(Symbol(), 0, 0);
   bool new_bar = (current_bar_time != last_bar_time);
   
   if (new_bar) {
      last_bar_time = current_bar_time;
      
      // ウォームアップ期間のカウント
      if (!warmup_complete) {
         warmup_bars++;
         if (warmup_bars >= 1) {  // 1本のバーを待つ（即時動作に近い）
            warmup_complete = true;
            Print("EA ウォームアップ完了: エントリー有効化");
         } else {
            if (EnableDebugLog) {
               Print("EA ウォームアップ中: ", warmup_bars, "/1 バー");
            }
         }
      }
      
      // インジケーター更新
      UpdateIndicators();
      
      // 既存ポジションがない場合、エントリーチェック
      // ウォームアップ完了前はエントリーしない
      if (!HasOpenPosition() && warmup_complete) {
         // Market Sentinelで取引停止中ならエントリーしない
         // サービス削除済み - 常にエントリー許可
         // 確認足モードでプルバック待機中の場合
         if (g_Use_Confirmation_Bar && pullback_detected) {
            CheckConfirmationBarEntry();
         } else {
            CheckForPullbackEntry();
         }
      }
   }
   
   // 既存ポジション管理（毎Tick）
   if (HasOpenPosition()) {
      ManagePosition();
   }
   
   // 即座エントリーモード: プルバック検出後、毎Tickでブレイクチェック
   // ウォームアップ完了前はエントリーしない
   if (!HasOpenPosition() && warmup_complete && g_Use_Immediate_Entry && pullback_detected) {
      CheckPriceBreakEntry();
   }
   
   // 確認足モード: 確認足条件を満たした後、毎Tickでブレイクチェック
   // ウォームアップ完了前はエントリーしない
   if (!HasOpenPosition() && warmup_complete && g_Use_Confirmation_Bar && pullback_detected && confirmation_bar_validated) {
      CheckPriceBreakEntry();
   }
}

//+------------------------------------------------------------------+
//| インジケーター更新                                                |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
   // EMA値取得
   ema12_current = iMA(Symbol(), 0, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   ema12_previous = iMA(Symbol(), 0, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
   
   ema25_current = iMA(Symbol(), 0, EMA_Mid_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   ema25_previous = iMA(Symbol(), 0, EMA_Mid_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
   
   ema100_current = iMA(Symbol(), 0, EMA_Long_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   ema100_previous = iMA(Symbol(), 0, EMA_Long_Period, 0, MODE_EMA, PRICE_CLOSE, 2);
   
   // ATR値取得
   current_atr = iATR(Symbol(), 0, ATR_Period, 1);
   
   // 前バーの高値・安値
   prev_high = iHigh(Symbol(), 0, 1);
   prev_low = iLow(Symbol(), 0, 1);
}

//+------------------------------------------------------------------+
//| プルバックエントリーチェック                                      |
//+------------------------------------------------------------------+
void CheckForPullbackEntry()
{
   // ラウンドナンバーフラグリセット
   roundnumber_entry_detected = false;
   
   // 1. 時間フィルターチェック
   if (Enable_Time_Filter && !IsWithinTradingHours()) {
      LogSkipReason("時間フィルター: 取引時間外");
      return;
   }
   
   // 1.5 TradeOptimizer推奨時間帯チェック（オプトイン時のみ）
   // サービス削除済み - スキップ
   
   // 2. スプレッドチェック（価格差=指数ポイント/価格単位）
   double current_spread = Ask - Bid;  // 価格差（指数ポイント/価格単位）
   double normal_spread = MarketInfo(Symbol(), MODE_SPREAD) * Point;  // MODE_SPREADはポイント数を返す
   if (normal_spread <= 0) normal_spread = 20.0; // ブローカー情報が無い場合のフォールバック
   
   if (current_spread > Max_Spread_Points) {
      LogSkipReason("スプレッド過大: " + DoubleToString(current_spread, 1) + " 指数ポイント");
      return;
   }
   
   // 3. スプレッド異常検出
   if (current_spread > normal_spread * Max_Spread_Multiplier) {
      LogSkipReason("スプレッド異常: " + DoubleToString(current_spread, 1) + " 指数ポイント > " + DoubleToString(normal_spread * Max_Spread_Multiplier, 1) + " 指数ポイント");
      return;
   }
   
   // 4. ATRチェック（比較は price units で行う）
   double atr_price = current_atr;
   double atr_mt4pt = (Point > 0.0) ? (atr_price / Point) : 0.0;
   if (EnableDebugLog) {
      if (Point > 0.0)
         Print("ATRチェック: 現在=", DoubleToString(atr_price, Digits), " (price units) / ", DoubleToString(atr_mt4pt, 0), " MT4pt, 閾値=", DoubleToString(g_ATR_Threshold_Points, 2), " (price units) / ", DoubleToString(g_ATR_Threshold_Points / Point, 0), " MT4pt");
      else
         Print("ATRチェック: 現在=", DoubleToString(atr_price, Digits), " (price units), 閾値=", DoubleToString(g_ATR_Threshold_Points, 2), " (price units)");
   }
   if (atr_price < g_ATR_Threshold_Points) {
      if (Point > 0.0)
         LogSkipReason("ATR不足: " + DoubleToString(atr_price, Digits) + " (price) / " + DoubleToString(atr_mt4pt, 0) + " MT4pt < " + DoubleToString(g_ATR_Threshold_Points, 2) + " (price) / " + DoubleToString(g_ATR_Threshold_Points / Point, 0) + " MT4pt");
      else
         LogSkipReason("ATR不足: " + DoubleToString(atr_price, Digits) + " < " + DoubleToString(g_ATR_Threshold_Points, 2));
      return;
   }
   
   // 5. ADXフィルター（レンジ相場回避）
   if (g_Use_ADX_Filter) {
      double adx_threshold = g_ADX_Min_Level;
      // TradeOptimizerでの動的調整はサービス削除済み - デフォルト値使用
      double adx = iADX(Symbol(), 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
      if (EnableDebugLog) {
         Print("ADXチェック: 現在=", DoubleToString(adx, 2), ", 最低値=", adx_threshold);
      }
      if (adx < adx_threshold) {
         LogSkipReason("ADX不足（レンジ相場）: " + DoubleToString(adx, 2) + " < " + DoubleToString(adx_threshold, 1));
         return;
      }
      if (EnableDebugLog) {
         Print("ADX合格: ", DoubleToString(adx, 2), " >= ", adx_threshold, " → トレンド相場");
      }
   }
   
   // 6. チャネル幅フィルター（狭いチャネル回避）
   if (g_Use_Channel_Width_Filter) {
      double highest = iHigh(Symbol(), 0, iHighest(Symbol(), 0, MODE_HIGH, Channel_Width_Period, 1));
      double lowest = iLow(Symbol(), 0, iLowest(Symbol(), 0, MODE_LOW, Channel_Width_Period, 1));
      double channel_width = (highest - lowest) / 1.0; // 指数ポイント/価格単位
      
      if (EnableDebugLog) {
         Print("チャネル幅チェック: 現在=", DoubleToString(channel_width, 2), " 指数ポイント, 最低値=", g_Min_Channel_Width_Points, " 指数ポイント (過去", Channel_Width_Period, "本)");
      }
      
      if (channel_width < g_Min_Channel_Width_Points) {
         LogSkipReason("チャネル幅不足（狭いチャネル）: " + DoubleToString(channel_width, 1) + " 指数ポイント < " + DoubleToString(g_Min_Channel_Width_Points, 1) + " 指数ポイント");
         return;
      }
      
      if (EnableDebugLog) {
         Print("チャネル幅合格: ", DoubleToString(channel_width, 2), " 指数ポイント >= ", g_Min_Channel_Width_Points, " 指数ポイント → 十分な値幅");
      }
   }
   
   // 7. トレンド判定
   int trend = CheckTrend();
   if (trend == 0) {
      LogSkipReason("トレンドなし: レンジ相場");
      return;
   }
   
   bool is_long = (trend == 1);
   
   // 5. マルチレイヤープルバック検出
   bool pullback_found = false;
   int layer_count = 0;
   string detected_layers = "";
   
   // レイヤー1: EMAプルバック
   bool ema_layer_detected = DetectPullback(is_long);
   if (ema_layer_detected) {
      layer_count++;
      detected_layers += "[EMA]";
      if (EnableDebugLog) Print("  レイヤー1: EMAプルバック検出");
   }
   
   // レイヤー2: トレンドライン/チャネル
   bool tl_layer_detected = false;
   int tl_signal = 0;
   if (g_TL_Channel_Mode == MODE_TRENDLINE_TREND) {
      tl_layer_detected = DetectTrendlinePullback(is_long, tl_signal);
      if (tl_layer_detected) {
         layer_count++;
         detected_layers += "[Trendline]";
         if (EnableDebugLog) Print("  レイヤー2: トレンドラインプルバック検出");
      }
   } else if (g_TL_Channel_Mode == MODE_CHANNEL_RANGE) {
      tl_layer_detected = DetectChannelRangePullback(tl_signal);
      if (tl_layer_detected) {
         layer_count++;
         detected_layers += "[Channel]";
         is_long = (tl_signal == 1);  // 逆張りなのでシグナルから方向決定
         if (EnableDebugLog) Print("  レイヤー2: チャネルプルバック検出（逆張り）");
      }
   }
   
   // レイヤー3: ラウンドナンバー
   bool rn_layer_detected = false;
   int rn_signal = 0;
   if (g_Use_RoundNumber_Lines) {
      rn_layer_detected = DetectRoundNumberPullback(is_long, rn_signal);
      if (rn_layer_detected) {
         layer_count++;
         detected_layers += "[RoundNumber]";
         if (g_RN_Counter_Trend && rn_signal != 0) {
            is_long = (rn_signal == 1);  // 逆張りの場合、方向更新
         }
         if (EnableDebugLog) Print("  レイヤー3: ラウンドナンバープルバック検出");
      }
   }
   
   // マルチレイヤー判定
   if (EnableDebugLog) {
      Print("マルチレイヤー検出: ", layer_count, "/", g_ML_Min_Layers, " 必須レイヤー ", detected_layers);
   }
   
   // 必須レイヤーチェック
   if (g_ML_Require_EMA && !ema_layer_detected) {
      LogSkipReason("EMAレイヤー必須だが未検出");
      return;
   }
   if (g_ML_Require_Trendline && !tl_layer_detected) {
      LogSkipReason("トレンドライン/チャネルレイヤー必須だが未検出");
      return;
   }
   if (g_ML_Require_RoundNumber && !rn_layer_detected) {
      LogSkipReason("ラウンドナンバーレイヤー必須だが未検出");
      return;
   }
   
   // 最小レイヤー数チェック
   if (layer_count < g_ML_Min_Layers) {
      LogSkipReason("レイヤー不足: " + IntegerToString(layer_count) + " < " + IntegerToString(g_ML_Min_Layers));
      return;
   }
   
   pullback_found = (layer_count >= g_ML_Min_Layers);
   
   // 複数レイヤー一致ボーナス（ログ出力）
   if (g_ML_Bonus_Multi_Layer && layer_count >= 2) {
      if (EnableDebugLog) Print("★★★ マルチレイヤー一致! ", layer_count, "レイヤー ", detected_layers, " → 強いシグナル");
   }
   
   if (!pullback_found) {
      // プルバック未検出（ログ不要）
      return;
   }
   
   // 6. ローソク足条件チェック
   if (!CheckCandleCondition(is_long)) {
      LogSkipReason("ローソク足条件不適合");
      return;
   }
   
   // 7. エントリートリガー判定
   if (g_Use_Immediate_Entry) {
      // 即座エントリー: プルバック検出、フラグを立てる
      pullback_detected = true;
      confirmation_bar_validated = false;
      pullback_bar_time = iTime(Symbol(), 0, 1);
      is_pullback_long = is_long;
      pullback_entry_level = is_long ? prev_high : prev_low;
      
      if (EnableDebugLog) {
         Print(">>> 即座モード: プルバック検出、ブレイク待機（エントリーレベル=", DoubleToString(pullback_entry_level, Digits), "）");
      }
   } else if (g_Use_Confirmation_Bar) {
      // 確認足モード: 次の足を待つ
      pullback_detected = true;
      confirmation_bar_validated = false;
      pullback_bar_time = iTime(Symbol(), 0, 1);
      is_pullback_long = is_long;
      pullback_entry_level = is_long ? prev_high : prev_low;
      
      if (EnableDebugLog) {
         Print(">>> 確認足モード: プルバック検出、次の足を待機");
      }
   }
}

//+------------------------------------------------------------------+
//| 確認足チェック後のエントリー                                      |
//+------------------------------------------------------------------+
void CheckConfirmationBarEntry()
{
   if (!pullback_detected) return;
   
   // 確認足のサイズチェック
   double bar_high = iHigh(Symbol(), 0, 1);
   double bar_low = iLow(Symbol(), 0, 1);
   double bar_size_Points = (bar_high - bar_low) / 1.0;
   
   if (EnableDebugLog) {
      Print("確認足チェック: サイズ=", DoubleToString(bar_size_Points, 1), " 指数ポイント, 最小=", g_Confirmation_Bar_Min_Size, " 指数ポイント, 最大=", g_Confirmation_Bar_Max_Size, " 指数ポイント");
   }
   
   if (bar_size_Points < g_Confirmation_Bar_Min_Size) {
      if (EnableDebugLog) {
         Print("確認足サイズ不足: ", DoubleToString(bar_size_Points, 1), " 指数ポイント < ", g_Confirmation_Bar_Min_Size, " 指数ポイント");
      }
      pullback_detected = false;
      confirmation_bar_validated = false;
      return;
   }
   
   if (g_Confirmation_Bar_Max_Size > 0 && bar_size_Points > g_Confirmation_Bar_Max_Size) {
      if (EnableDebugLog) {
         Print("確認足サイズ過大: ", DoubleToString(bar_size_Points, 1), " 指数ポイント > ", g_Confirmation_Bar_Max_Size, " 指数ポイント");
      }
      pullback_detected = false;
      confirmation_bar_validated = false;
      return;
   }
   
   // 確認足のローソク足条件チェック
   if (!CheckCandleCondition(is_pullback_long)) {
      if (EnableDebugLog) Print("確認足: ローソク足条件不適合");
      pullback_detected = false;
      confirmation_bar_validated = false;
      return;
   }
   
   // エントリーレベルを確認足の高値/安値に更新
   pullback_entry_level = is_pullback_long ? bar_high : bar_low;
   confirmation_bar_validated = true;
   
   if (EnableDebugLog) {
      Print(">>> 確認足OK: サイズ=", DoubleToString(bar_size_Points, 1), " 指数ポイント, エントリーレベル=", DoubleToString(pullback_entry_level, Digits));
   }
}

//+------------------------------------------------------------------+
//| 価格ブレイクエントリーチェック（毎Tick）                          |
//+------------------------------------------------------------------+
void CheckPriceBreakEntry()
{
   if (!pullback_detected) return;
   
   double buffer = Entry_Buffer_Points * 1.0;
   
   if (is_pullback_long) {
      if (Ask >= pullback_entry_level + buffer) {
         // 補助条件チェック
         if (!CheckAuxiliaryConditions(true)) {
            if (EnableDebugLog) Print("補助条件不足でエントリースキップ[ロング]");
            return;
         }
         ExecuteEntry(true);
         pullback_detected = false;
         confirmation_bar_validated = false;
         roundnumber_entry_detected = false;  // フラグリセット
      }
   } else {
      if (Bid <= pullback_entry_level - buffer) {
         // 補助条件チェック
         if (!CheckAuxiliaryConditions(false)) {
            if (EnableDebugLog) Print("補助条件不足でエントリースキップ[ショート]");
            return;
         }
         ExecuteEntry(false);
         pullback_detected = false;
         confirmation_bar_validated = false;
         roundnumber_entry_detected = false;  // フラグリセット
      }
   }
}

//+------------------------------------------------------------------+
//| トレンド判定                                                      |
//| 戻り値: 1=上昇, -1=下降, 0=レンジ                                |
//+------------------------------------------------------------------+
int CheckTrend()
{
   // パーフェクトオーダーチェック
   if (g_Require_Perfect_Order) {
      bool is_uptrend = (ema12_current > ema25_current) && (ema25_current > ema100_current);
      bool is_downtrend = (ema12_current < ema25_current) && (ema25_current < ema100_current);
      
      if (!is_uptrend && !is_downtrend) {
         return 0; // レンジ
      }
      
      // EMA傾きチェック
      if (is_uptrend && !CheckEMASlope(true)) {
         return 0;
      }
      if (is_downtrend && !CheckEMASlope(false)) {
         return 0;
      }
      
      int trend_direction = is_uptrend ? 1 : -1;
      
      // MTFフィルターチェック
      if (g_Use_MTF_Filter1 && !CheckMTFTrend(g_MTF_Timeframe1, MTF_EMA_Period1, g_MTF_Require_Perfect_Order1, trend_direction)) {
         if (EnableDebugLog) {
            Print("MTFフィルター1不適合: ", EnumToString(g_MTF_Timeframe1));
         }
         return 0;
      }
      
      if (g_Use_MTF_Filter2 && !CheckMTFTrend(g_MTF_Timeframe2, MTF_EMA_Period2, g_MTF_Require_Perfect_Order2, trend_direction)) {
         if (EnableDebugLog) {
            Print("MTFフィルター2不適合: ", EnumToString(g_MTF_Timeframe2));
         }
         return 0;
      }
      
      if (Use_MTF_Filter3 && !CheckMTFTrend(MTF_Timeframe3, MTF_EMA_Period3, MTF_Require_Perfect_Order3, trend_direction)) {
         if (EnableDebugLog) {
            Print("MTFフィルター3不適合: ", EnumToString(MTF_Timeframe3));
         }
         return 0;
      }
      
      return trend_direction;
   }
   
   // パーフェクトオーダー不要の場合は簡易判定
   if (ema12_current > ema100_current) return 1;
   if (ema12_current < ema100_current) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| EMA傾きチェック                                                   |
//+------------------------------------------------------------------+
bool CheckEMASlope(bool is_long)
{
   int lookback = MathMax(1, EMA_Slope_Bars);
   
   // 短期EMA傾き
   if (g_EMA_Min_Slope_Fast > 0) {
      double ema12_old = iMA(Symbol(), 0, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE, lookback + 1);
      double slope_fast = (ema12_current - ema12_old) / lookback;
      
      if (is_long && slope_fast < g_EMA_Min_Slope_Fast) return false;
      if (!is_long && slope_fast > -g_EMA_Min_Slope_Fast) return false;
   }
   
   // 長期EMA傾き
   if (g_EMA_Min_Slope_Slow > 0) {
      double ema100_old = iMA(Symbol(), 0, EMA_Long_Period, 0, MODE_EMA, PRICE_CLOSE, lookback + 1);
      double slope_slow = (ema100_current - ema100_old) / lookback;
      
      if (is_long && slope_slow < g_EMA_Min_Slope_Slow) return false;
      if (!is_long && slope_slow > -g_EMA_Min_Slope_Slow) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| MTFトレンドチェック                                               |
//+------------------------------------------------------------------+
bool CheckMTFTrend(ENUM_TIMEFRAMES timeframe, int ema_period, bool require_perfect_order, int trend_direction)
{
   // 上位足のEMA取得
   double mtf_ema12 = iMA(Symbol(), timeframe, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double mtf_ema25 = iMA(Symbol(), timeframe, EMA_Mid_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double mtf_ema100 = iMA(Symbol(), timeframe, EMA_Long_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double mtf_close = iClose(Symbol(), timeframe, 1);
   
   if (require_perfect_order) {
      // パーフェクトオーダー判定
      if (trend_direction == 1) {
         // 上昇トレンド: 12 > 25 > 100
         bool mtf_uptrend = (mtf_ema12 > mtf_ema25) && (mtf_ema25 > mtf_ema100);
         if (!mtf_uptrend) {
            if (EnableDebugLog) {
               Print("MTF[", EnumToString(timeframe), "]: パーフェクトオーダーなし（上昇）");
            }
            return false;
         }
      } else {
         // 下降トレンド: 12 < 25 < 100
         bool mtf_downtrend = (mtf_ema12 < mtf_ema25) && (mtf_ema25 < mtf_ema100);
         if (!mtf_downtrend) {
            if (EnableDebugLog) {
               Print("MTF[", EnumToString(timeframe), "]: パーフェクトオーダーなし（下降）");
            }
            return false;
         }
      }
   } else {
      // 簡易判定: 価格が指定EMAの正しい側にあるか
      double mtf_ema_ref = iMA(Symbol(), timeframe, ema_period, 0, MODE_EMA, PRICE_CLOSE, 1);
      
      if (trend_direction == 1) {
         // 上昇トレンド: 価格 > EMA
         if (mtf_close <= mtf_ema_ref) {
            if (EnableDebugLog) {
               Print("MTF[", EnumToString(timeframe), "]: 価格がEMA", ema_period, "の下（上昇トレンド不適合）");
            }
            return false;
         }
      } else {
         // 下降トレンド: 価格 < EMA
         if (mtf_close >= mtf_ema_ref) {
            if (EnableDebugLog) {
               Print("MTF[", EnumToString(timeframe), "]: 価格がEMA", ema_period, "の上（下降トレンド不適合）");
            }
            return false;
         }
      }
   }
   
   if (EnableDebugLog) {
      Print("MTF[", EnumToString(timeframe), "]: トレンド一致 OK");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| プルバック検出                                                    |
//+------------------------------------------------------------------+
bool DetectPullback(bool is_long)
{
   // 強トレンドモード: ADXが高い場合、EMA12タッチで即エントリー（自動判定対応）
   if (ShouldActivateStrongTrendMode()) {
      double adx = iADX(Symbol(), 0, ADX_Period, PRICE_CLOSE, MODE_MAIN, 1);
      
      if (adx > g_Strong_Trend_ADX_Level) {
         // EMA12の値を取得
         double ema12 = iMA(Symbol(), 0, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
         
         // 過去5本以内にEMA12タッチがあるかチェック
         for (int i = 1; i <= 5; i++) {
            double bar_high = iHigh(Symbol(), 0, i);
            double bar_low = iLow(Symbol(), 0, i);
            double bar_close = iClose(Symbol(), 0, i);
            
            double ema12_at_bar = iMA(Symbol(), 0, EMA_Short_Period, 0, MODE_EMA, PRICE_CLOSE, i);
            
            // ロング: 安値がEMA12にタッチ（または下回る）→ 終値がEMA12より上
            if (is_long && bar_low <= ema12_at_bar && bar_close > ema12_at_bar) {
               pullback_type = "強トレンドEMA12タッチ";
               if (EnableDebugLog) {
                  Print(">>> 強トレンドモード: ADX=", DoubleToString(adx, 2), " > ", g_Strong_Trend_ADX_Level, " → EMA12タッチで即エントリー[ロング]");
               }
               return true;
            }
            
            // ショート: 高値がEMA12にタッチ（または上回る）→ 終値がEMA12より下
            if (!is_long && bar_high >= ema12_at_bar && bar_close < ema12_at_bar) {
               pullback_type = "強トレンドEMA12タッチ";
               if (EnableDebugLog) {
                  Print(">>> 強トレンドモード: ADX=", DoubleToString(adx, 2), " > ", g_Strong_Trend_ADX_Level, " → EMA12タッチで即エントリー[ショート]");
               }
               return true;
            }
         }
      }
   }
   
   // 基準EMA値取得
   double reference_ema = GetReferenceEMA();
   int lookback = MathMin(Pullback_Lookback, 10);
   
   // 過去N本以内でプルバックを探す
   for (int i = 1; i <= lookback; i++) {
      double bar_high = iHigh(Symbol(), 0, i);
      double bar_low = iLow(Symbol(), 0, i);
      double bar_close = iClose(Symbol(), 0, i);
      double bar_open = iOpen(Symbol(), 0, i);
      
      double ema_at_bar = iMA(Symbol(), 0, GetEMAPeriod(Pullback_EMA), 0, MODE_EMA, PRICE_CLOSE, i);
      double ema_prev_bar = iMA(Symbol(), 0, GetEMAPeriod(Pullback_EMA), 0, MODE_EMA, PRICE_CLOSE, i+1);
      
      // タイプA: EMAタッチ
      if (g_Use_Touch_Pullback) {
         if (is_long && bar_low <= ema_at_bar && bar_high >= ema_at_bar) {
            pullback_type = "EMAタッチ";
            if (EnableDebugLog) {
               Print(">>> プルバック検出[", i, "本前]: ", pullback_type, " (ロング)");
            }
            return true;
         }
         if (!is_long && bar_high >= ema_at_bar && bar_low <= ema_at_bar) {
            pullback_type = "EMAタッチ";
            if (EnableDebugLog) {
               Print(">>> プルバック検出[", i, "本前]: ", pullback_type, " (ショート)");
            }
            return true;
         }
      }
      
      // タイプB: EMAクロス
      if (g_Use_Cross_Pullback) {
         double low_prev = iLow(Symbol(), 0, i+1);
         double high_prev = iHigh(Symbol(), 0, i+1);
         
         // ロング: 価格がEMAを下→上クロス
         if (is_long && low_prev < ema_prev_bar && bar_high > ema_at_bar) {
            pullback_type = "EMAクロス";
            if (EnableDebugLog) {
               Print(">>> プルバック検出[", i, "本前]: ", pullback_type, " (ロング)");
            }
            return true;
         }
         
         // ショート: 価格がEMAを上→下クロス
         if (!is_long && high_prev > ema_prev_bar && bar_low < ema_at_bar) {
            pullback_type = "EMAクロス";
            if (EnableDebugLog) {
               Print(">>> プルバック検出[", i, "本前]: ", pullback_type, " (ショート)");
            }
            return true;
         }
      }
      
      // タイプC: EMA完全ブレイク（終値基準）
      if (g_Use_Break_Pullback) {
         double close_prev = iClose(Symbol(), 0, i+1);
         
         // ロング: 終値がEMAを完全に下抜け → 上に戻る
         if (is_long && close_prev < ema_prev_bar && bar_close > ema_at_bar) {
            pullback_type = "EMA完全ブレイク";
            if (EnableDebugLog) {
               Print(">>> プルバック検出[", i, "本前]: ", pullback_type, " (ロング)");
            }
            return true;
         }
         
         // ショート: 終値がEMAを完全に上抜け → 下に戻る
         if (!is_long && close_prev > ema_prev_bar && bar_close < ema_at_bar) {
            pullback_type = "EMA完全ブレイク";
            if (EnableDebugLog) {
               Print(">>> プルバック検出[", i, "本前]: ", pullback_type, " (ショート)");
            }
            return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| ローソク足条件チェック                                            |
//+------------------------------------------------------------------+
bool CheckCandleCondition(bool is_long)
{
   double open1 = iOpen(Symbol(), 0, 1);
   double close1 = iClose(Symbol(), 0, 1);
   double high1 = iHigh(Symbol(), 0, 1);
   double low1 = iLow(Symbol(), 0, 1);
   
   double body = MathAbs(close1 - open1);
   double total_range = high1 - low1;
   
   // 実体比率チェック
   if (total_range > 0) {
      double body_percent = (body / total_range) * 100.0;
      if (body_percent < g_Min_Candle_Body_Percent) {
         if (EnableDebugLog) {
            Print("実体比率不足: ", DoubleToString(body_percent, 1), "%");
         }
         return false;
      }
   }
   
   // 陽線・陰線チェック
   if (is_long && Require_Bullish_Candle_Long) {
      if (close1 <= open1) {
         if (EnableDebugLog) Print("ロング: 陽線必須だが陰線");
         return false;
      }
   }
   
   if (!is_long && Require_Bearish_Candle_Short) {
      if (close1 >= open1) {
         if (EnableDebugLog) Print("ショート: 陰線必須だが陽線");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| ラウンドナンバー付近チェック                                      |
//| 戻り値: true=付近にいる（エントリー回避すべき）                    |
//|        false=付近にいない（エントリーOK）                         |
//+------------------------------------------------------------------+
bool IsNearRoundNumber(double price)
{
   if (!g_RN_Avoid_Entry_Near) return false;  // 機能無効時はOK
   
   double buffer = g_RN_Avoid_Buffer_Points;
   
   // 1000ライン（.00相当）チェック
   if (g_RN_Use_00_Line) {
      double rn_00 = GetNearestRoundNumber(price, true);
      if (MathAbs(price - rn_00) <= buffer) {
         if (EnableDebugLog) {
            Print(">>> 1000ライン付近検出: 価格=", DoubleToString(price, 0), 
                  " RN=", DoubleToString(rn_00, 0),
                  " 距離=", DoubleToString(MathAbs(price - rn_00), 0), " 指数ポイント");
         }
         return true;  // 付近にいる
      }
   }
   
   // 500ライン（.50相当）チェック
   if (g_RN_Use_50_Line) {
      double rn_50 = GetNearestRoundNumber(price, false);
      if (MathAbs(price - rn_50) <= buffer) {
         if (EnableDebugLog) {
            Print(">>> 500ライン付近検出: 価格=", DoubleToString(price, 0), 
                  " RN=", DoubleToString(rn_50, 0),
                  " 距離=", DoubleToString(MathAbs(price - rn_50), 0), " 指数ポイント");
         }
         return true;  // 付近にいる
      }
   }
   
   return false;  // 付近にいない
}

//+------------------------------------------------------------------+
//| エントリー実行                                                    |
//+------------------------------------------------------------------+
void ExecuteEntry(bool is_long)
{
   double entry_price;
   double sl_price;
   double tp_price;
   string direction;
   
   // エントリー価格を先に取得
   entry_price = is_long ? Ask : Bid;
   
   // ラウンドナンバー付近チェック（プルバックタッチ検出時は除外）
   if (!roundnumber_entry_detected && IsNearRoundNumber(entry_price)) {
      if (EnableDebugLog) {
         Print(">>> エントリースキップ: 1000/500付近（プルバックタッチなし）");
      }
      LogSkipReason("RN_NEAR_AVOID: ラウンドナンバー付近でエントリー回避");
      return;  // エントリーせずに終了
   }
   
   if (roundnumber_entry_detected && EnableDebugLog) {
      Print(">>> ラウンドナンバー付近だがプルバックタッチ検出済み → エントリー続行");
   }
   
   // Market Sentinelによるロットサイズ調整（EnableLotAdjustmentがtrueの場合のみ）
   // サービス削除済み - 調整なし
   // US Index: BaseLotSizeは整数
   int base_lot = BaseLotSize;
   int adjusted_lot = base_lot;
   
   // TradeOptimizerによるロットサイズ調整（オプトイン時のみ、EnableLotAdjustmentがtrueの場合のみ）
   // サービス削除済み - 調整なし
   
   if (is_long) {
      // entry_price = Ask; // 既に上で設定済み
      direction = "ロング";
      
      // SL/TP計算
      if (SLTP_Mode == SLTP_FIXED) {
         sl_price = entry_price - (g_StopLoss_Points * 1.0);
         tp_price = entry_price + (g_TakeProfit_Points * 1.0);
      } else {
         sl_price = entry_price - (current_atr * StopLoss_ATR_Multi);
         tp_price = entry_price + (current_atr * TakeProfit_ATR_Multi);
      }
   } else {
      // entry_price = Bid; // 既に上で設定済み
      direction = "ショート";
      
      // SL/TP計算
      if (SLTP_Mode == SLTP_FIXED) {
         sl_price = entry_price + (g_StopLoss_Points * 1.0);
         tp_price = entry_price - (g_TakeProfit_Points * 1.0);
      } else {
         sl_price = entry_price + (current_atr * StopLoss_ATR_Multi);
         tp_price = entry_price - (current_atr * TakeProfit_ATR_Multi);
      }
   }
   
   // 注文実行
   int ticket = -1;
   int cmd = is_long ? OP_BUY : OP_SELL;
   
   if (!Use_StopLoss) sl_price = 0;
   if (!Use_TakeProfit) tp_price = 0;
   
   ticket = OrderSend(Symbol(), cmd, adjusted_lot, entry_price, EffectiveSlippagePoints(),
                      NormalizeDouble(sl_price, Digits),
                      NormalizeDouble(tp_price, Digits),
                      "PullbackEntry_" + pullback_type, g_ActiveMagicNumber, 0, clrBlue);
   
   if (ticket > 0) {
      current_ticket = ticket;
      partial1_executed = false;
      partial2_executed = false;
      partial3_executed = false;
      trailing_active = false;
      roundnumber_entry_detected = false;  // フラグリセット
      
      Print("===== エントリー成功 =====");
      Print("方向: ", direction);
      Print("プルバックタイプ: ", pullback_type);
      Print("チケット: ", ticket);
      Print("ロットサイズ: ", adjusted_lot, (adjusted_lot != BaseLotSize ? " (調整済)" : ""), " lot (JP225)");
      Print("エントリー価格: ", DoubleToString(entry_price, Digits));
      Print("SL: ", DoubleToString(sl_price, Digits));
      Print("TP: ", DoubleToString(tp_price, Digits));
      Print("========================");
      
      LogTrade("ENTRY", direction, pullback_type, ticket, entry_price, sl_price, tp_price);
   } else {
      int error = GetLastError();
      Print("エントリー失敗: エラーコード ", error);
      LogTrade("ENTRY_FAILED", direction, pullback_type, -1, 0, 0, 0);
      roundnumber_entry_detected = false;  // フラグリセット
   }
}

//+------------------------------------------------------------------+
//| ポジション管理                                                    |
//+------------------------------------------------------------------+
void ManagePosition()
{
   if (current_ticket < 0) return;
   
   if (!OrderSelect(current_ticket, SELECT_BY_TICKET)) {
      current_ticket = -1;
      return;
   }
   
   if (OrderCloseTime() != 0) {
      // クローズ済み
      current_ticket = -1;
      return;
   }
   
   // 段階的利確
   if (g_EnablePartialClose) {
      CheckPartialClose();
   }
   
   // トレーリングストップ
   if (g_EnableTrailingAfterTP2 && trailing_active) {
      UpdateTrailingStop();
   }
}

//+------------------------------------------------------------------+
//| 段階的利確チェック                                                |
//+------------------------------------------------------------------+
void CheckPartialClose()
{
   if (!OrderSelect(current_ticket, SELECT_BY_TICKET)) return;
   
   double current_price = (OrderType() == OP_BUY) ? Bid : Ask;
   double entry_price = OrderOpenPrice();
   double profit_Points = 0;
   
   if (OrderType() == OP_BUY) {
      profit_Points = (current_price - entry_price) / 1.0;
   } else {
      profit_Points = (entry_price - current_price) / 1.0;
   }
   
   // 第1利確
   if (!partial1_executed && profit_Points >= g_PartialCloseLevel1_Points) {
      ExecutePartialClose(1, g_PartialClosePercent1);
   }
   
   // 第2利確
   if (g_PartialCloseLevels >= 2 && !partial2_executed && profit_Points >= g_PartialCloseLevel2_Points) {
      ExecutePartialClose(2, g_PartialClosePercent2);
   }
   
   // 第3利確
   if (g_PartialCloseLevels >= 3 && !partial3_executed && profit_Points >= g_PartialCloseLevel3_Points) {
      ExecutePartialClose(3, g_PartialClosePercent3);
   }
}

//+------------------------------------------------------------------+
//| 段階的利確実行                                                    |
//+------------------------------------------------------------------+
void ExecutePartialClose(int level, double percent)
{
   if (!OrderSelect(current_ticket, SELECT_BY_TICKET)) return;

   int old_ticket = current_ticket;
   string direction = (OrderType() == OP_BUY) ? "BUY" : "SELL";
   double old_sl = OrderStopLoss();
   double old_tp = OrderTakeProfit();
   
   double current_lots = OrderLots();
   double close_lots = NormalizeDouble(current_lots * percent / 100.0, 2);
   
   if (close_lots < 0.01) return;
   
   double close_price = (OrderType() == OP_BUY) ? Bid : Ask;
   
   bool result = OrderClose(current_ticket, close_lots, close_price, EffectiveSlippagePoints(), clrRed);
   
   if (result) {
      Print("第", level, "利確成功: ", close_lots, " lots @ ", DoubleToString(close_price, Digits));
      
      // 一部決済後、残ポジションの新しいチケット番号を取得
      Sleep(100);  // サーバー処理待機
      current_ticket = -1;
      int new_ticket = -1;
      double remaining_lots = 0.0;
      for (int i = OrdersTotal() - 1; i >= 0; i--) {
         if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_ActiveMagicNumber) {
               current_ticket = OrderTicket();
               new_ticket = current_ticket;
               remaining_lots = OrderLots();
               Print("★ 一部決済後の新チケット: #", current_ticket, ", 残ロット: ", DoubleToString(OrderLots(), 2));
               break;
            }
         }
      }

      string details = "Level=" + IntegerToString(level)
                       + ";percent=" + DoubleToString(percent, 1)
                       + ";closed_lots=" + DoubleToString(close_lots, 2)
                       + ";close_price=" + DoubleToString(close_price, Digits)
                       + ";old_ticket=" + IntegerToString(old_ticket)
                       + ";new_ticket=" + IntegerToString(new_ticket)
                       + ";remaining_lots=" + DoubleToString(remaining_lots, 2);
      LogTrade("PARTIAL_CLOSE", direction, "", old_ticket, close_price, old_sl, old_tp, details);
      
      if (level == 1) {
         partial1_executed = true;
         if (g_MoveToBreakevenOnPartial1) {
            MoveStopLossToBreakeven();
         }
      } else if (level == 2) {
         partial2_executed = true;
         if (MoveToTP1OnPartial2) {
            MoveStopLossToTP1();
         }
         if (g_EnableTrailingAfterTP2) {
            trailing_active = true;
            if (OrderType() == OP_BUY) {
               highest_price_trailing = Bid;
            } else {
               lowest_price_trailing = Ask;
            }
         }
      } else if (level == 3) {
         partial3_executed = true;
      }
   } else {
      int err = GetLastError();
      string details = "Level=" + IntegerToString(level)
                       + ";percent=" + DoubleToString(percent, 1)
                       + ";close_lots=" + DoubleToString(close_lots, 2)
                       + ";close_price=" + DoubleToString(close_price, Digits)
                       + ";ticket=" + IntegerToString(old_ticket)
                       + ";err=" + IntegerToString(err);
      LogTrade("PARTIAL_CLOSE_FAILED", direction, "", old_ticket, close_price, old_sl, old_tp, details);
   }
}

//+------------------------------------------------------------------+
//| SLを建値に移動                                                    |
//+------------------------------------------------------------------+
//| SLを建値に移動                                                    |
//+------------------------------------------------------------------+
void MoveStopLossToBreakeven()
{
   if (!OrderSelect(current_ticket, SELECT_BY_TICKET)) {
      Print("❌ MoveStopLossToBreakeven: OrderSelect失敗");
      return;
   }
   
   double entry_price = OrderOpenPrice();
   int order_type = OrderType();
   
   double new_sl = entry_price + (g_BreakevenOffset_Points * 1.0);
   if (order_type == OP_SELL) {
      new_sl = entry_price - (g_BreakevenOffset_Points * 1.0);
   }
   new_sl = NormalizeDouble(new_sl, Digits);
   
   Print("★ MoveStopLossToBreakeven呼出: 現在SL=", DoubleToString(OrderStopLoss(), Digits), 
         " → 目標SL=", DoubleToString(new_sl, Digits),
         " (建値+", DoubleToString(g_BreakevenOffset_Points, 1), ")");
   
   // 建値移動の条件: SLが建値より不利な位置にある場合のみ移動
   bool should_modify = false;
   if (order_type == OP_BUY) {
      // ロング: SLが建値より低い、またはSLが未設定の場合
      if (OrderStopLoss() == 0 || OrderStopLoss() < entry_price) {
         should_modify = true;
      }
   } else if (order_type == OP_SELL) {
      // ショート: SLが建値より高い、またはSLが未設定の場合
      if (OrderStopLoss() == 0 || OrderStopLoss() > entry_price) {
         should_modify = true;
      }
   }
   
   if (should_modify) {
      bool result = OrderModify(current_ticket, OrderOpenPrice(), 
                               new_sl,
                               OrderTakeProfit(), 0, clrGreen);
      if (result) {
         Print("✅ SLを建値+", DoubleToString(g_BreakevenOffset_Points, 1), "に移動成功: ", DoubleToString(new_sl, Digits));
      } else {
         Print("❌ SL移動失敗: エラー ", GetLastError());
      }
   } else {
      Print("⚠️ SL移動スキップ: 既にSLが目標以上");
   }
}

//+------------------------------------------------------------------+
//| SLを第1利確価格に移動                                             |
//+------------------------------------------------------------------+
void MoveStopLossToTP1()
{
   if (!OrderSelect(current_ticket, SELECT_BY_TICKET)) return;

   double entry_price = OrderOpenPrice();
   int order_type = OrderType();

   // 第1利確到達価格（TP1）へ移動
   double tp1_price = entry_price + (g_PartialCloseLevel1_Points * 1.0);
   if (order_type == OP_SELL) {
      tp1_price = entry_price - (g_PartialCloseLevel1_Points * 1.0);
   }
   tp1_price = NormalizeDouble(tp1_price, Digits);

   double current_sl = OrderStopLoss();
   bool should_modify = false;
   if (order_type == OP_BUY) {
      if (current_sl == 0 || current_sl < tp1_price) {
         should_modify = true;
      }
   } else if (order_type == OP_SELL) {
      if (current_sl == 0 || current_sl > tp1_price) {
         should_modify = true;
      }
   }

   if (should_modify) {
      bool result = OrderModify(current_ticket, OrderOpenPrice(),
                               tp1_price,
                               OrderTakeProfit(), 0, clrGreen);
      if (result) {
         Print("第2利確後、SLを第1利確価格(TP1)へ移動: ", DoubleToString(tp1_price, Digits));
      }
   }
}

//+------------------------------------------------------------------+
//| トレーリングストップ更新                                          |
//+------------------------------------------------------------------+
void UpdateTrailingStop()
{
   if (!OrderSelect(current_ticket, SELECT_BY_TICKET)) return;
   
   double trailing_distance = 0;
   if (g_Trailing_Mode == TRAILING_FIXED_POINTS) {
      trailing_distance = g_TrailingStop_Fixed_Points * 1.0;
   } else {
      double trailing_atr = iATR(Symbol(), 0, Trailing_ATR_Period, 1);
      trailing_distance = trailing_atr * g_TrailingStop_ATR_Multi;
   }
   
   double step = g_TrailingUpdate_Step_Points * 1.0;
   
   if (OrderType() == OP_BUY) {
      if (Bid > highest_price_trailing) {
         highest_price_trailing = Bid;
      }
      
      double new_sl = highest_price_trailing - trailing_distance;
      
      if (new_sl > OrderStopLoss() + step) {
         bool result = OrderModify(current_ticket, OrderOpenPrice(),
                                  NormalizeDouble(new_sl, Digits),
                                  OrderTakeProfit(), 0, clrGreen);
         if (result && EnableDebugLog) {
            Print("トレーリングSL更新[ロング]: ", DoubleToString(new_sl, Digits));
         }
      }
   } else if (OrderType() == OP_SELL) {
      if (Ask < lowest_price_trailing || lowest_price_trailing == 0) {
         lowest_price_trailing = Ask;
      }
      
      double new_sl = lowest_price_trailing + trailing_distance;
      
      if (new_sl < OrderStopLoss() - step || OrderStopLoss() == 0) {
         bool result = OrderModify(current_ticket, OrderOpenPrice(),
                                  NormalizeDouble(new_sl, Digits),
                                  OrderTakeProfit(), 0, clrGreen);
         if (result && EnableDebugLog) {
            Print("トレーリングSL更新[ショート]: ", DoubleToString(new_sl, Digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ポジション保有チェック                                            |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--) {
      if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
         if (OrderSymbol() == Symbol() && OrderMagicNumber() == g_ActiveMagicNumber) {
            current_ticket = OrderTicket();
            return true;
         }
      }
   }
   current_ticket = -1;
   return false;
}

//+------------------------------------------------------------------+
//| 取引時間チェック                                                  |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   datetime server_time = TimeCurrent();
   int server_hour = TimeHour(server_time);
   int server_minute = TimeMinute(server_time);
   
   // サーバー時間からGMTへ変換
   int gmt_offset_seconds = GMT_Offset * 3600;
   if (Use_DST) gmt_offset_seconds += 3600;
   datetime gmt_time = server_time - gmt_offset_seconds;
   
   // GMTから日本時間へ変換 (GMT+9)
   datetime jst_time = gmt_time + (9 * 3600);
   int jst_hour = TimeHour(jst_time);
   int jst_minute = TimeMinute(jst_time);
   
   // 時間範囲チェック
   int start_minutes = Custom_Start_Hour * 60 + Custom_Start_Minute;
   int end_minutes = Custom_End_Hour * 60 + Custom_End_Minute;
   int current_minutes = jst_hour * 60 + jst_minute;
   
   if (start_minutes <= end_minutes) {
      return (current_minutes >= start_minutes && current_minutes <= end_minutes);
   } else {
      return (current_minutes >= start_minutes || current_minutes <= end_minutes);
   }
}

//+------------------------------------------------------------------+
//| フォルダ作成（ダミーファイル経由）                                   |
//+------------------------------------------------------------------+
void CreateFolder(string folder_path)
{
   if(EnsureFolderPath(folder_path))
      Print("📁 フォルダ作成: ", folder_path);
}

//+------------------------------------------------------------------+
//| ログフォルダ作成（階層対応）                                     |
//+------------------------------------------------------------------+
bool EnsureFolderPath(string folderPath)
{
   string path = folderPath;
   StringReplace(path, "/", "\\");
   while(StringLen(path) > 0 && StringSubstr(path, StringLen(path) - 1, 1) == "\\")
      path = StringSubstr(path, 0, StringLen(path) - 1);

   // MQL4のファイルI/Oは通常 MQL4\\Files 配下の相対パスが前提
   if(StringLen(path) >= 2 && StringSubstr(path, 1, 1) == ":")
   {
      Print("[ERROR] CsvLogFolderは相対パスにしてください: ", path);
      return false;
   }

   string parts[];
   int n = StringSplit(path, '\\', parts);
   if(n <= 0)
      return false;

   string current = "";
   for(int i = 0; i < n; i++)
   {
      if(StringLen(parts[i]) == 0)
         continue;
      current = (StringLen(current) == 0) ? parts[i] : (current + "\\" + parts[i]);
      FolderCreate(current);
   }
   return true;
}

//+------------------------------------------------------------------+
//| CSVログ初期化                                                     |
//+------------------------------------------------------------------+
void InitializeCsvLog()
{
   // サブフォルダパスの構築
   string symbol_name = Symbol();
   string timeframe = GetTimeframeString(Period());
   
   g_Trade_History_Folder = CsvLogFolder + "\\Trade_History";
   g_AI_Learning_Folder = CsvLogFolder + "\\AI_Learning";
   
   // フォルダ自動作成
   CreateFolder(g_Trade_History_Folder);
   CreateFolder(g_AI_Learning_Folder);
   
   // トレードログファイル名（MT4_ID + 銘柄 + 時間軸）
   g_Trade_LogFile = "Trade_Log_" + MT4_ID + "_" + symbol_name + "_" + timeframe + ".csv";
   csv_file_path = g_Trade_History_Folder + "\\" + g_Trade_LogFile;
   
   int file_handle = FileOpen(csv_file_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   
   if (file_handle == INVALID_HANDLE) {
      Print("❌ CSVログファイル作成失敗: ", csv_file_path);
      Print("   エラーコード: ", GetLastError());
      return;
   }
   
   if (FileSize(file_handle) == 0) {
      FileWrite(file_handle, "Timestamp", "Symbol", "Event", "Direction", "PullbackType",
                "Ticket", "Price", "SL", "TP", "Details");
   }
   
   FileClose(file_handle);
   Print("✅ トレードログ初期化完了: ", csv_file_path);
}

//+------------------------------------------------------------------+
//| 時間軸を文字列に変換                                               |
//+------------------------------------------------------------------+
string GetTimeframeString(int period)
{
   switch(period) {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default: return "M" + IntegerToString(period);
   }
}

//+------------------------------------------------------------------+
//| 強トレンドモード自動判定（ボラティリティ急増検知）                      |
//+------------------------------------------------------------------+
bool ShouldActivateStrongTrendMode()
{
   if (!g_Auto_Strong_Trend_Mode) return g_Use_Strong_Trend_Mode;  // 手動設定を返す
   
   // 1. ATRスパイク検知（指数ポイント/価格単位）
   double current_atr_value = iATR(Symbol(), 0, 14, 1);
   double baseline_atr = 0;
   for (int i = 2; i <= g_Auto_Detection_Period + 1; i++) {
      baseline_atr += iATR(Symbol(), 0, 14, i);
   }
   baseline_atr /= g_Auto_Detection_Period;
   
   double atr_spike_ratio = (baseline_atr > 0) ? current_atr_value / baseline_atr : 1.0;
   
   // 2. ティックボリューム急増検知
   long current_volume = iVolume(Symbol(), 0, 1);
   long baseline_volume = 0;
   for (int i = 2; i <= g_Auto_Detection_Period + 1; i++) {
      baseline_volume += iVolume(Symbol(), 0, i);
   }
   baseline_volume /= g_Auto_Detection_Period;
   
   double volume_surge_ratio = (baseline_volume > 0) ? (double)current_volume / baseline_volume : 1.0;
   
   // 3. 判定ロジック
   bool atr_spike_detected = (atr_spike_ratio >= g_Auto_ATR_Spike_Threshold);
   bool volume_surge_detected = (volume_surge_ratio >= g_Auto_Volume_Surge_Threshold);
   
   // どちらか一方でも検知したら強トレンドモードON
   bool should_activate = (atr_spike_detected || volume_surge_detected);
   
   if (EnableDebugLog && should_activate) {
      Print("★ 強トレンドモード自動ON検知:");
      if (atr_spike_detected) {
         Print("  - ATRスパイク: ", DoubleToString(atr_spike_ratio, 2), "倍 (閾値: ", 
               DoubleToString(g_Auto_ATR_Spike_Threshold, 2), "倍)");
      }
      if (volume_surge_detected) {
         Print("  - ボリューム急増: ", DoubleToString(volume_surge_ratio, 2), "倍 (閾値: ", 
               DoubleToString(g_Auto_Volume_Surge_Threshold, 2), "倍)");
      }
      Print("  → 不利なエントリー回避のため、押し目なしトレンドに追随");
   }
   
   return should_activate;
}

//+------------------------------------------------------------------+
//| トレードログ記録                                                  |
//+------------------------------------------------------------------+
void LogTrade(string event, string direction, string pullback, int ticket,
              double price, double sl, double tp, string details = "")
{
   if (!EnableCsvLogging) return;
   
   int file_handle = FileOpen(csv_file_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if (file_handle == INVALID_HANDLE) return;
   
   FileSeek(file_handle, 0, SEEK_END);
   
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
   
   FileWrite(file_handle, timestamp, Symbol(), event, direction, pullback,
             IntegerToString(ticket),
             DoubleToString(price, Digits),
             DoubleToString(sl, Digits),
             DoubleToString(tp, Digits),
             details);
   
   FileClose(file_handle);
}

//+------------------------------------------------------------------+
//| スキップ理由ログ                                                  |
//+------------------------------------------------------------------+
void LogSkipReason(string reason)
{
   if (!LogSkipEvents) return;
   
   // クールダウンチェック
   if (SkipLogCooldownSeconds > 0) {
      if (last_skip_reason == reason && 
          TimeCurrent() - last_skip_log_time < SkipLogCooldownSeconds) {
         return;
      }
   }
   
   last_skip_reason = reason;
   last_skip_log_time = TimeCurrent();
   
   if (EnableDebugLog) {
      Print(">>> スキップ: ", reason);
   }
   
   if (EnableCsvLogging) {
      int file_handle = FileOpen(csv_file_path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
      if (file_handle != INVALID_HANDLE) {
         FileSeek(file_handle, 0, SEEK_END);
         string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES);
         FileWrite(file_handle, timestamp, Symbol(), "SKIP", "", "", "", "", "", "", reason);
         FileClose(file_handle);
      }
   }
}

//+------------------------------------------------------------------+
//| ヘルパー関数: 基準EMA取得                                         |
//+------------------------------------------------------------------+
double GetReferenceEMA()
{
   switch (Pullback_EMA) {
      case PULLBACK_EMA_12:  return ema12_current;
      case PULLBACK_EMA_25:  return ema25_current;
      case PULLBACK_EMA_100: return ema100_current;
   }
   return ema25_current;
}

//+------------------------------------------------------------------+
//| ヘルパー関数: EMA期間取得                                         |
//+------------------------------------------------------------------+
int GetEMAPeriod(PullbackEMAReference ref)
{
   switch (ref) {
      case PULLBACK_EMA_12:  return EMA_Short_Period;
      case PULLBACK_EMA_25:  return EMA_Mid_Period;
      case PULLBACK_EMA_100: return EMA_Long_Period;
   }
   return EMA_Mid_Period;
}

//+------------------------------------------------------------------+
//| ヘルパー関数: EMA名取得                                           |
//+------------------------------------------------------------------+
string GetEMAName(PullbackEMAReference ref)
{
   switch (ref) {
      case PULLBACK_EMA_12:  return "EMA12";
      case PULLBACK_EMA_25:  return "EMA25";
      case PULLBACK_EMA_100: return "EMA100";
   }
   return "EMA25";
}

//+------------------------------------------------------------------+
//| 戦略プリセット適用                                                |
//+------------------------------------------------------------------+
void ApplyStrategyPreset()
{
   // AI学習ログファイル名の構築（MT4_ID + 銘柄 + 時間軸）
   string symbol_name = Symbol();
   string timeframe = GetTimeframeString(Period());
   g_AI_Learning_LogFile = "AI_Learning_Data_" + MT4_ID + "_" + symbol_name + "_" + timeframe + ".csv";
   g_AI_Learning_Folder = CsvLogFolder + "\\AI_Learning";
   g_Trade_History_Folder = CsvLogFolder + "\\Trade_History";
   
   // デフォルト値をinputパラメータから読み込み
   g_StopLoss_Points = StopLoss_Fixed_Points;
   g_TakeProfit_Points = TakeProfit_Fixed_Points;
   g_EnablePartialClose = EnablePartialClose;
   g_PartialCloseLevels = PartialCloseLevels;
   g_PartialClosePercent1 = PartialClosePercent1;
   g_PartialCloseLevel1_Points = PartialCloseLevel1_Points;
   g_PartialClosePercent2 = PartialClosePercent2;
   g_PartialCloseLevel2_Points = PartialCloseLevel2_Points;
   g_PartialClosePercent3 = PartialClosePercent3;
   g_PartialCloseLevel3_Points = PartialCloseLevel3_Points;
   g_MoveToBreakevenOnPartial1 = MoveToBreakevenOnPartial1;
   g_BreakevenOffset_Points = BreakevenOffset_Points;
   g_EnableTrailingAfterTP2 = EnableTrailingAfterTP2;
   g_Trailing_Mode = Trailing_Mode;
   g_TrailingStop_Fixed_Points = TrailingStop_Fixed_Points;
   g_TrailingStop_ATR_Multi = TrailingStop_ATR_Multi;
   g_TrailingUpdate_Step_Points = TrailingUpdate_Step_Points;
   g_Entry_Confirmations = Entry_Confirmations;
   g_Min_Candle_Body_Percent = Min_Candle_Body_Percent;
   g_Use_MTF_Filter1 = Use_MTF_Filter1;
   g_MTF_Timeframe1 = MTF_Timeframe1;
   g_MTF_Require_Perfect_Order1 = MTF_Require_Perfect_Order1;
   g_Use_MTF_Filter2 = Use_MTF_Filter2;
   g_MTF_Timeframe2 = MTF_Timeframe2;
   g_MTF_Require_Perfect_Order2 = MTF_Require_Perfect_Order2;
   g_Require_Perfect_Order = Require_Perfect_Order;
   g_EMA_Min_Slope_Fast = EMA_Min_Slope_Fast;
   g_EMA_Min_Slope_Slow = EMA_Min_Slope_Slow;
   g_Use_FailedBreak = Use_FailedBreak;
   g_Use_Failed_Break_Reversal = Use_Failed_Break_Reversal;
   g_Use_Immediate_Entry = Use_Immediate_Entry;
   g_Use_Confirmation_Bar = Use_Confirmation_Bar;
   g_Confirmation_Bar_Min_Size = Confirmation_Bar_Min_Size;
   g_Confirmation_Bar_Max_Size = Confirmation_Bar_Max_Size;
   g_Use_Touch_Pullback = Use_Touch_Pullback;
   g_Use_Cross_Pullback = Use_Cross_Pullback;
   g_Use_Break_Pullback = Use_Break_Pullback;
   g_Use_Strong_Trend_Mode = Use_Strong_Trend_Mode;
   g_Strong_Trend_ADX_Level = Strong_Trend_ADX_Level;
   g_Auto_Strong_Trend_Mode = Auto_Strong_Trend_Mode;
   g_Auto_ATR_Spike_Threshold = Auto_ATR_Spike_Threshold;
   g_Auto_Volume_Surge_Threshold = Auto_Volume_Surge_Threshold;
   g_Auto_Detection_Period = Auto_Detection_Period;

   // 環境フィルター設定（プリセットで上書き可能）
   g_Use_ADX_Filter = Use_ADX_Filter;
   g_ADX_Min_Level = ADX_Min_Level;
   g_Use_Channel_Width_Filter = Use_Channel_Width_Filter;
   g_Min_Channel_Width_Points = Min_Channel_Width_Points;
   g_ATR_Threshold_Points = ATR_Threshold_Points;
   
   switch (Selected_Strategy) {
      case STRATEGY_STANDARD:
         // 標準型（RELAXEDベース、バランス重視、M15推奨）
         g_StopLoss_Points = 180.0;  // 18 pips相当
         g_TakeProfit_Points = 450.0;  // 45 pips相当
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 200.0;  // 20 pips相当
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 450.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 25.0;  // 2.5 pips相当
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_POINTS;
         g_TrailingStop_Fixed_Points = 120.0;  // 12 pips相当
         g_TrailingUpdate_Step_Points = 30.0;  // 3 pips相当
         // 環境フィルター（バランス型）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 20.0;
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 100.0;  // 20 pips相当（10倍）
         g_ATR_Threshold_Points = 70.0;  // 7 pips相当（10倍、実運用最適値）
         // EMA設定（標準）
         g_Entry_Confirmations = 1;
         g_Min_Candle_Body_Percent = 55.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: 標準型（M15推奨）");
         Print("SL: 180 指数ポイント / TP: 450 指数ポイント");
         Print("ADX >= 20.0、チャネル >= 100 指数ポイント、ATR >= 70 指数ポイント");
         Print("→ バランス重視、初心者推奨");
         Print("★ AI機能: inputパラメータでON/OFF可能");
         if (g_Use_Micro_Volatility_Filter) Print("  - HFTノイズ除外: ON");
         if (g_Use_Algo_Price_Levels) Print("  - アルゴ価格レベル: ON");
         if (g_Use_OrderFlow_Detection) Print("  - オーダーフロー検出: ON");
         Print("========================================");
         break;
         
      case STRATEGY_CONSERVATIVE:
         // 保守型（厳格フィルター、質重視、M30推奨）
         g_StopLoss_Points = 220.0;  // 22 pips相当
         g_TakeProfit_Points = 550.0;  // 55 pips相当
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 250.0;  // 25 pips相当
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 550.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 30.0;  // 3 pips相当
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_POINTS;
         g_TrailingStop_Fixed_Points = 150.0;  // 15 pips相当
         g_TrailingUpdate_Step_Points = 40.0;  // 4 pips相当
         // 環境フィルター（厳格）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 25.0;
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 150.0;  // 30 pips相当（5倍）
         g_ATR_Threshold_Points = 75.0;  // 15 pips相当（5倍）
         g_Min_Bar_Range_Points = 40.0;  // 4 pips相当（10倍）
         // EMA設定（厳格）
         g_Entry_Confirmations = 2;
         g_Min_Candle_Body_Percent = 60.0;
         g_Use_MTF_Filter1 = true;
         g_MTF_Timeframe1 = PERIOD_H1;
         g_MTF_Require_Perfect_Order1 = true;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         g_Use_Immediate_Entry = false;
         g_Use_Confirmation_Bar = true;
         g_Confirmation_Bar_Min_Size = 80.0;  // 8 pips相当
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = false;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: 保守型（M30推奨）");
         Print("SL: 220 指数ポイント / TP: 550 指数ポイント");
         Print("ADX >= 25.0、チャネル >= 150 指数ポイント、ATR >= 75 指数ポイント");
         Print("→ 質重視、勝率優先");
         Print("★ AI機能: inputパラメータでON/OFF可能");
         if (g_Use_Micro_Volatility_Filter) Print("  - HFTノイズ除外: ON");
         if (g_Use_Algo_Price_Levels) Print("  - アルゴ価格レベル: ON");
         if (g_Use_OrderFlow_Detection) Print("  - オーダーフロー検出: ON");
         Print("========================================");
         break;
         
      case STRATEGY_AGGRESSIVE:
         // 積極型（フィルター最小、量重視、M5推奨）
         g_StopLoss_Points = 150.0;  // 15 pips相当
         g_TakeProfit_Points = 350.0;  // 35 pips相当
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 150.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 350.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;  // 2 pips相当
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_POINTS;
         g_TrailingStop_Fixed_Points = 100.0;  // 10 pips相当
         g_TrailingUpdate_Step_Points = 25.0;  // 2.5 pips相当
         // 環境フィルター（最小）
         g_Use_ADX_Filter = false;
         g_ADX_Min_Level = 0.0;
         g_Use_Channel_Width_Filter = false;
         g_Min_Channel_Width_Points = 0.0;
         g_ATR_Threshold_Points = 25.0;  // 5 pips相当（5倍）
         g_Min_Bar_Range_Points = 20.0;  // 2 pips相当（10倍）
         // EMA設定（緩和）
         g_Entry_Confirmations = 0;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = true;
         Print("========================================");
         Print("戦略: 積極型（M5推奨）");
         Print("SL: 150 指数ポイント / TP: 350 指数ポイント");
         Print("環境フィルター最小（ATR >= 25 指数ポイントのみ）");
         Print("→ 取引回数最大化、量重視");
         Print("★ AI機能: inputパラメータでON/OFF可能");
         if (g_Use_Micro_Volatility_Filter) Print("  - HFTノイズ除外: ON");
         if (g_Use_Algo_Price_Levels) Print("  - アルゴ価格レベル: ON");
         if (g_Use_OrderFlow_Detection) Print("  - オーダーフロー検出: ON");
         Print("========================================");
         break;
         
      case STRATEGY_AI_ADAPTIVE:
         // AI適応型（HFTノイズ除外+アルゴレベル検出、M5推奨）
         g_StopLoss_Points = 120.0;  // 12 pips相当
         g_TakeProfit_Points = 300.0;  // 30 pips相当
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 60.0;
         g_PartialCloseLevel1_Points = 120.0;
         g_PartialClosePercent2 = 40.0;
         g_PartialCloseLevel2_Points = 300.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 15.0;  // 1.5 pips相当
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_POINTS;
         g_TrailingStop_Fixed_Points = 80.0;  // 8 pips相当
         g_TrailingUpdate_Step_Points = 20.0;  // 2 pips相当
         // AI対応フィルター
         g_Use_Micro_Volatility_Filter = true;
         g_Min_Bar_Range_Pips = 30.0;  // 3 pips相当（10倍）
         g_Min_Bar_Range_Points = 30.0;  // AI関数用
         g_Noise_Detection_Period = 10;
         g_Noise_Ratio_Threshold = 0.6;
         g_Use_Algo_Price_Levels = true;
         g_Algo_Price_Clustering = 50.0;  // 5 pips相当（10倍）
         g_Use_Quarter_Levels = true;
         g_Use_OrderFlow_Detection = true;
         g_OrderFlow_Volume_Multi = 2.0;
         g_OrderFlow_Avg_Period = 9;
         g_Use_Algo_TimeFilter = false;
         // 環境フィルター（中程度）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 22.0;
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 125.0;  // 25 pips相当（5倍）
         g_ATR_Threshold_Points = 50.0;  // 10 pips相当（5倍）
         // EMA設定（バランス）
         g_Entry_Confirmations = 1;
         g_Min_Candle_Body_Percent = 55.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: AI適応型（M5推奨）");
         Print("SL: 120 指数ポイント / TP: 300 指数ポイント");
         Print("★ HFTノイズ除外 + アルゴ価格レベル検出");
         Print("★ オーダーフロー分析 + 0.25刻みレベル");
         Print("→ AI時代対応、GPU不要の軽量アルゴリズム");
         Print("========================================");
         break;
         
      case STRATEGY_AI_SCOUT:
         // AIスカウト型（データ収集+パターン学習）
         g_StopLoss_Points = 150.0;  // 15 pips相当
         g_TakeProfit_Points = 350.0;  // 35 pips相当
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 150.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 350.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_POINTS;
         g_TrailingStop_Fixed_Points = 100.0;
         g_TrailingUpdate_Step_Points = 25.0;
         // AI学習モード（全フィルター有効）
         g_Use_Micro_Volatility_Filter = true;
         g_Min_Bar_Range_Pips = 25.0;  // 2.5 pips相当（10倍）
         g_Min_Bar_Range_Points = 25.0;  // AI関数用
         g_Noise_Detection_Period = 15;
         g_Noise_Ratio_Threshold = 0.5;
         g_Use_Algo_Price_Levels = true;
         g_Algo_Price_Clustering = 70.0;  // 7 pips相当（10倍）
         g_Use_Quarter_Levels = true;
         g_Use_OrderFlow_Detection = true;
         g_OrderFlow_Volume_Multi = 1.8;
         g_OrderFlow_Avg_Period = 12;
         g_Use_Algo_TimeFilter = false;
         g_Enable_AI_Learning_Log = true;
         // 環境フィルター（緩和）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 18.0;
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 75.0;  // 15 pips相当（5倍）
         g_ATR_Threshold_Points = 40.0;  // 8 pips相当（5倍）
         // EMA設定（緩和）
         g_Entry_Confirmations = 0;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = true;
         Print("========================================");
         Print("戦略: AIスカウト型（実験モード）");
         Print("SL: 150 指数ポイント / TP: 350 指数ポイント");
         Print("★ DLL推論EA用データ収集モード");
         Print("★ 全パターン記録 + 統計分析");
         Print("→ 学習データをCSV出力（" + g_AI_Learning_LogFile + "）");
         Print("========================================");
         break;
         
      /*
      case STRATEGY_BALANCED:
         // 提案2: バランス型（段階利確）
         g_StopLoss_Points = 150.0;
         g_TakeProfit_Points = 500.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 150.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 500.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;
         g_EnableTrailingAfterTP2 = true;
         g_TrailingStop_Fixed_Points = 120.0;
         g_Entry_Confirmations = 2;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         Print("========================================");
         Print("戦略: バランス型（段階利確）");
         Print("SL: 150 指数ポイント / TP: 500 指数ポイント");
         Print("段階利確: 150指数ポイント@50% → 500指数ポイント@50%");
         Print("トレーリング有効");
         Print("========================================");
         break;
         
      case STRATEGY_HIGH_ACCURACY:
         // 提案4: 高精度型（厳格化）
         g_StopLoss_Points = 200.0;
         g_TakeProfit_Points = 600.0;
         g_EnablePartialClose = false;
         g_Entry_Confirmations = 3;
         g_Min_Candle_Body_Percent = 60.0;
         g_Use_MTF_Filter1 = true;
         g_MTF_Timeframe1 = PERIOD_H1;
         g_MTF_Require_Perfect_Order1 = true;
         g_Use_MTF_Filter2 = true;
         g_MTF_Timeframe2 = PERIOD_H4;
         g_MTF_Require_Perfect_Order2 = true;
         g_Require_Perfect_Order = true;
         g_EnableTrailingAfterTP2 = false;
         Print("========================================");
         Print("戦略: 高精度型（厳格化）");
         Print("SL: 200 指数ポイント / TP: 600 指数ポイント (1:3)");
         Print("補助条件: 3つ必須");
         Print("MTFフィルター: H1 + H4");
         Print("実体比率: 60%以上");
         Print("========================================");
         break;
         
      case STRATEGY_SCALPING:
         // 提案5: スキャルピング型
         g_StopLoss_Points = 80.0;
         g_TakeProfit_Points = 120.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 70.0;
         g_PartialCloseLevel1_Points = 80.0;
         g_PartialClosePercent2 = 30.0;
         g_PartialCloseLevel2_Points = 200.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;
         g_Entry_Confirmations = 1;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_EnableTrailingAfterTP2 = false;
         Print("========================================");
         Print("戦略: スキャルピング型");
         Print("SL: 80 指数ポイント / TP: 120 指数ポイント (1:1.5)");
         Print("段階利確: 80指数ポイント@70% → 200指数ポイント@30%");
         Print("補助条件: 1つのみ");
         Print("即座エントリー");
         Print("========================================");
         break;
         
      case STRATEGY_TREND_RIDER:
         // 提案6: トレンド継続型
         g_StopLoss_Points = 150.0;
         g_TakeProfit_Points = 450.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 30.0;
         g_PartialCloseLevel1_Points = 200.0;
         g_PartialClosePercent2 = 40.0;
         g_PartialCloseLevel2_Points = 400.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 1.5;
         g_TrailingUpdate_Step_Points = 30.0;
         g_Use_Immediate_Entry = false;
         g_Use_Confirmation_Bar = true;
         g_Confirmation_Bar_Min_Size = 80.0;
         g_Min_Candle_Body_Percent = 65.0;
         g_Entry_Confirmations = 2;
         g_Use_Break_Pullback = true;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         Print("========================================");
         Print("戦略: トレンド継続型");
         Print("SL: 150 指数ポイント / TP: 450 指数ポイント (1:3)");
         Print("段階利確: 200指数ポイント@30% → 400指数ポイント@40% → 残り30%トレーリング");
         Print("トレーリング: ATR 1.5倍");
         Print("確認足必須、実体比率65%");
         Print("========================================");
         break;
         
      case STRATEGY_TREND_RIDER_V2:
         // トレンド継続型V2（改良版）- 取引機会を増やしつつ品質維持
         g_StopLoss_Points = 180.0;
         g_TakeProfit_Points = 540.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 25.0;
         g_PartialCloseLevel1_Points = 250.0;
         g_PartialClosePercent2 = 35.0;
         g_PartialCloseLevel2_Points = 450.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 30.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         g_TrailingUpdate_Step_Points = 30.0;
         g_Use_Immediate_Entry = false;
         g_Use_Confirmation_Bar = true;
         g_Confirmation_Bar_Min_Size = 60.0;
         g_Confirmation_Bar_Max_Size = 300.0;
         g_Min_Candle_Body_Percent = 55.0;
         g_Entry_Confirmations = 1;
         g_Use_Break_Pullback = false;
         g_Use_MTF_Filter1 = true;
         g_MTF_Timeframe1 = PERIOD_H1;
         g_MTF_Require_Perfect_Order1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         g_EMA_Min_Slope_Fast = 0.0;
         g_EMA_Min_Slope_Slow = 0.0;
         Print("========================================");
         Print("戦略: トレンド継続型V2（改良版）");
         Print("SL: 180 指数ポイント / TP: 540 指数ポイント (1:3)");
         Print("段階利確: 250指数ポイント@25% → 450指数ポイント@35% → 残り40%ATRトレーリング");
         Print("トレーリング: ATR 2.0倍（利益最大化）");
         Print("MTFフィルター: H1（Perfect Order不要）");
         Print("補助条件: 1つ（緩和）");
         Print("実体比率: 55%（緩和）");
         Print("EMA傾きフィルター: 無効（取引機会増加）");
         Print("========================================");
         break;
         
      case STRATEGY_TREND_RIDER_V3:
         // トレンド継続型V3（バランス型ベース + ATRトレーリング強化）
         // バランス型の優秀な設定を維持しつつ、大きなトレンドで利益を伸ばす
         g_StopLoss_Points = 150.0;
         g_TakeProfit_Points = 500.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 150.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 500.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;              // ATRトレーリングに変更
         g_TrailingStop_ATR_Multi = 2.0;              // ATR 2.0倍（バランス型は固定12指数ポイント）
         g_TrailingUpdate_Step_Points = 30.0;            // 更新ステップ5指数ポイント
         g_Entry_Confirmations = 2;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         g_Use_Immediate_Entry = true;                // バランス型と同じ
         g_Use_Confirmation_Bar = false;              // バランス型と同じ
         g_Use_Touch_Pullback = true;                 // 重要: プルバックタイプ有効化
         g_Use_Cross_Pullback = true;                 // 重要: プルバックタイプ有効化
         g_Use_Break_Pullback = false;                // バランス型と同じ
         g_EMA_Min_Slope_Fast = 0.0;
         g_EMA_Min_Slope_Slow = 0.0;
         Print("========================================");
         Print("戦略: トレンド継続型V3（バランス型ベース）");
         Print("SL: 150 指数ポイント / TP: 500 指数ポイント");
         Print("段階利確: 150指数ポイント@50% → 500指数ポイント@50%");
         Print("トレーリング: ATR 2.0倍（大トレンドで利益最大化）");
         Print("補助条件: 2つ（バランス型と同じ）");
         Print("※ M30での運用を推奨");
         Print("========================================");
         break;
         
      case STRATEGY_HYBRID:
         // 提案7: ハイブリッド型（レンジ対応）
         g_StopLoss_Points = 120.0;
         g_TakeProfit_Points = 240.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 1;
         g_PartialClosePercent1 = 60.0;
         g_PartialCloseLevel1_Points = 120.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 15.0;
         g_Require_Perfect_Order = false;
         g_EMA_Min_Slope_Fast = 0.00005;
         g_EMA_Min_Slope_Slow = 0.00002;
         g_Use_FailedBreak = true;
         g_Use_Failed_Break_Reversal = true;
         g_Entry_Confirmations = 1;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_EnableTrailingAfterTP2 = false;
         Print("========================================");
         Print("戦略: ハイブリッド型（レンジ対応）");
         Print("SL: 120 指数ポイント / TP: 240 指数ポイント (1:2)");
         Print("段階利確: 120指数ポイント@60%");
         Print("パーフェクトオーダー不要");
         Print("失敗ブレイク重視");
         Print("========================================");
         break;
         
      case STRATEGY_TRENDLINE:
         // トレンドライン順張り型
         g_StopLoss_Points = 180.0;
         g_TakeProfit_Points = 450.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 40.0;
         g_PartialCloseLevel1_Points = 180.0;
         g_PartialClosePercent2 = 60.0;
         g_PartialCloseLevel2_Points = 450.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 30.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         g_TrailingUpdate_Step_Points = 40.0;
         // トレンドライン設定
         g_TL_Channel_Mode = MODE_TRENDLINE_TREND;
         g_TL_Touch_Buffer_Points = 20.0;
         g_TL_Use_Touch = true;
         g_TL_Use_Cross = true;
         g_TL_Use_Break = false;
         g_TL_Lookback_Bars = 5;
         g_PA_Require_Reversal = false;  // 順張りなのでfalse
         g_PA_Use_Pinbar = false;
         g_PA_Use_Engulfing = false;
         // EMA設定
         g_Entry_Confirmations = 2;
         g_Min_Candle_Body_Percent = 55.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         Print("========================================");
         Print("戦略: トレンドライン順張り型");
         Print("SL: 180 指数ポイント / TP: 450 指数ポイント (1:2.5)");
         Print("段階利確: 180指数ポイント@40% → 450指数ポイント@60%");
         Print("トレーリング: ATR 2.0倍");
         Print("手動トレンドライン使用（TL_Upper/TL_Lower）");
         Print("タッチ・クロスでエントリー");
         Print("========================================");
         break;
         
      case STRATEGY_CHANNEL_RANGE:
         // チャネル逆張り型
         g_StopLoss_Points = 150.0;
         g_TakeProfit_Points = 300.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 60.0;
         g_PartialCloseLevel1_Points = 150.0;
         g_PartialClosePercent2 = 40.0;
         g_PartialCloseLevel2_Points = 300.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 25.0;
         g_EnableTrailingAfterTP2 = false;  // 逆張りなのでトレーリング無効
         // チャネル設定
         g_TL_Channel_Mode = MODE_CHANNEL_RANGE;
         g_TL_Touch_Buffer_Points = 15.0;
         g_TL_Use_Touch = true;
         g_TL_Use_Cross = false;
         g_TL_Use_Break = false;
         g_TL_Lookback_Bars = 3;
         g_PA_Require_Reversal = true;  // 逆張りなので反転パターン必須
         g_PA_Use_Pinbar = true;
         g_PA_Use_Engulfing = true;
         g_PA_Pinbar_Shadow_Ratio = 0.6;
         g_PA_Pinbar_Opposite_Shadow_Ratio = 0.3;
         // EMA設定（緩め）
         g_Entry_Confirmations = 1;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;  // レンジ想定なので不要
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         Print("========================================");
         Print("戦略: チャネル逆張り型");
         Print("SL: 150 指数ポイント / TP: 300 指数ポイント (1:2)");
         Print("段階利確: 150指数ポイント@60% → 300指数ポイント@40%");
         Print("手動チャネルライン使用（TL_Upper/TL_Lower）");
         Print("タッチでエントリー + プライスアクション反転必須");
         Print("ピンバー・エンゴルフィング検出");
         Print("========================================");
         break;
         
      case STRATEGY_MULTI_LAYER:
         // マルチレイヤー型（EMA + ラウンドナンバー）
         g_StopLoss_Points = 150.0;
         g_TakeProfit_Points = 400.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 150.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 400.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_POINTS;
         g_TrailingStop_Fixed_Points = 120.0;
         g_TrailingUpdate_Step_Points = 30.0;
         // 環境フィルター（M15のボトルネック対策: ATR不足が多いため少し緩和）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 20.0;
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 100.0;
         g_ATR_Threshold_Points = 25.0;
         // ラウンドナンバー設定
         g_Use_RoundNumber_Lines = true;
         g_RN_Use_00_Line = true;
         g_RN_Use_50_Line = true;
         // M15でRNタッチが厳しすぎるとシグナルが出づらいので、バッファを少し拡大
         g_RN_Touch_Buffer_Points = 45.0;
         g_RN_Use_Touch = true;
         g_RN_Use_Cross = true;
         g_RN_Use_Break = false;
         g_RN_Lookback_Bars = 6;
         g_RN_Counter_Trend = false;  // 順張り
         g_RN_Digit_Level = 0;  // 日経225: 39000, 39500など
         // マルチレイヤー設定
         // 勝率優先: EMAレイヤーは必須に（RN+TLだけのシグナルを排除）
         g_ML_Require_EMA = true;
         g_ML_Require_Trendline = false;
         g_ML_Require_RoundNumber = false;  // ラウンドナンバー必須ではない
         g_ML_Min_Layers = 2;  // 2レイヤー一致推奨
         g_ML_Bonus_Multi_Layer = true;
         // EMA設定
         g_Entry_Confirmations = 0;  // 補助条件不要（マルチレイヤーで十分）
         g_Min_Candle_Body_Percent = 40.0;  // やや緩和
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;  // パーフェクトオーダー不要
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: マルチレイヤー型（EMA + ラウンドナンバー）");
         Print("SL: 150 指数ポイント / TP: 400 指数ポイント");
         Print("段階利確: 150指数ポイント@50% → 400指数ポイント@50%");
         Print("トレーリング: 固定120 指数ポイント");
         Print("マルチレイヤー検出: 2レイヤー推奨（柔軟）");
         Print("EMA/ラウンドナンバー/トレンドラインのいずれか2つ一致");
         Print("補助条件: 不要（マルチレイヤーで十分）");
         Print("========================================");
         break;
         
      case STRATEGY_ENV_FILTER_STRICT:
         // 環境フィルター厳格型（強いトレンド+広いチャネルのみ）
         g_StopLoss_Points = 120.0;
         g_TakeProfit_Points = 360.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 180.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 360.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 15.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         // 環境フィルター（厳格）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 30.0;  // 強いトレンドのみ
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 200.0;  // 広いチャネルのみ
         g_ATR_Threshold_Points = 80.0;  // 高ボラティリティ必須
         // EMA設定（V3ベース）
         g_Entry_Confirmations = 2;
         g_Min_Candle_Body_Percent = 60.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: 環境フィルター厳格型");
         Print("SL: 120 指数ポイント / TP: 360 指数ポイント (1:3)");
         Print("ADX >= 30.0（強トレンド）");
         Print("チャネル幅 >= 200 指数ポイント（広い値幅）");
         Print("ATR >= 80 指数ポイント（高ボラティリティ）");
         Print("→ HFTノイズ・狭小レンジを完全除外");
         Print("========================================");
         break;
         
      case STRATEGY_ENV_FILTER_MODERATE:
         // 環境フィルター標準型（今回のデフォルト設定）
         g_StopLoss_Points = 150.0;
         g_TakeProfit_Points = 400.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 150.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 400.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         // 環境フィルター（標準）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 25.0;  // 中程度のトレンド
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 150.0;  // デフォルト値
         g_ATR_Threshold_Points = 60.0;  // 標準ボラティリティ
         // EMA設定（バランス型ベース）
         g_Entry_Confirmations = 1;
         g_Min_Candle_Body_Percent = 55.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: 環境フィルター標準型");
         Print("SL: 150 指数ポイント / TP: 400 指数ポイント");
         Print("ADX >= 25.0（標準トレンド）");
         Print("チャネル幅 >= 150 指数ポイント（標準値幅）");
         Print("ATR >= 60 指数ポイント（標準ボラティリティ）");
         Print("→ バランスの取れたフィルタリング");
         Print("========================================");
         break;
         
      case STRATEGY_ENV_FILTER_RELAXED:
         // 環境フィルター緩和型（エントリー機会確保）
         g_StopLoss_Points = 180.0;
         g_TakeProfit_Points = 450.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 200.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 450.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 25.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_POINTS;
         g_TrailingStop_Fixed_Points = 120.0;
         g_TrailingUpdate_Step_Points = 30.0;
         // 環境フィルター（緩和）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 20.0;  // 弱いトレンドでもOK
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 100.0;  // 狭めでもOK
         g_ATR_Threshold_Points = 50.0;  // 低ボラティリティでもOK
         // EMA設定（緩め）
         g_Entry_Confirmations = 0;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;  // パーフェクトオーダー不要
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: 環境フィルター緩和型");
         Print("SL: 180 指数ポイント / TP: 450 指数ポイント");
         Print("ADX >= 20.0（緩いトレンド）");
         Print("チャネル幅 >= 100 指数ポイント（狭めでもOK）");
         Print("ATR >= 50 指数ポイント（低ボラでもOK）");
         Print("→ エントリー機会を確保しつつフィルタリング");
         Print("========================================");
         break;
         
      case STRATEGY_ENV_FILTER_OPTIMIZED:
         // 環境フィルター最適化型（RELAXED改良版）
         g_StopLoss_Points = 180.0;
         g_TakeProfit_Points = 450.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 200.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 450.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 25.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_POINTS;
         g_TrailingStop_Fixed_Points = 120.0;
         g_TrailingUpdate_Step_Points = 30.0;
         // 環境フィルター（最適化）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 18.0;  // RELAXEDより緩め
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 75.0;  // RELAXEDより緩め
         g_ATR_Threshold_Points = 40.0;  // RELAXEDより緩め
         // EMA設定（緩め）
         g_Entry_Confirmations = 0;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;  // パーフェクトオーダー不要
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: 環境フィルター最適化型");
         Print("SL: 180 指数ポイント / TP: 450 指数ポイント");
         Print("ADX >= 18.0（RELAXEDより緩め）");
         Print("チャネル幅 >= 75 指数ポイント（RELAXEDより緩め）");
         Print("ATR >= 40 指数ポイント（RELAXEDより緩め）");
         Print("→ 取引回数300~400回を目指しPF維持");
         Print("========================================");
         break;
         
      case STRATEGY_V3_FILTERED:
         // V3+環境フィルター（最強版）
         // V3の設定をベースにRELAXEDフィルターを追加
         g_StopLoss_Points = 200.0;
         g_TakeProfit_Points = 500.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Points = 250.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Points = 500.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Points = 20.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         // 環境フィルター（RELAXEDレベル）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 20.0;  // 最低限のトレンド
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Points = 100.0;  // 最低限の値幅
         g_ATR_Threshold_Points = 50.0;  // 最低限のボラ
         // V3のEMA設定（厳格）
         g_Entry_Confirmations = 2;  // 補助条件2個必須
         g_Min_Candle_Body_Percent = 60.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;  // パーフェクトオーダー必須
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: V3+環境フィルター（最強版）");
         Print("SL: 200 指数ポイント / TP: 500 指数ポイント (1:2.5)");
         Print("V3設定: パーフェクトオーダー+補助条件2個");
         Print("環境フィルター: ADX>=20, チャネル>=100指数ポイント, ATR>=50指数ポイント");
         Print("→ V3の高精度+RELAXEDの環境フィルター");
         Print("→ 目標: 取引400~600回、PF 1.12+");
         Print("========================================");
         break;
      */
         
      case STRATEGY_CUSTOM:
         // カスタム設定（手動パラメータを使用）
         Print("========================================");
         Print("戦略: カスタム（手動設定）");
         Print("すべてのパラメータを手動で設定してください");
         Print("========================================");
         break;
   }
}

//+------------------------------------------------------------------+
//| インサイドバー検出（はらみ足）                                      |
//+------------------------------------------------------------------+
bool IsInsideBar(int shift)
{
   double parent_high = iHigh(Symbol(), 0, shift + 1);
   double parent_low = iLow(Symbol(), 0, shift + 1);
   double current_high = iHigh(Symbol(), 0, shift);
   double current_low = iLow(Symbol(), 0, shift);
   
   // 現在の足が前の足の範囲内に収まっている
   return (current_high < parent_high && current_low > parent_low);
}

//+------------------------------------------------------------------+
//| ダブルバーブレイクアウト検出（Volman式）                            |
//| 2本連続でEMAタッチ→3本目でブレイク                                |
//+------------------------------------------------------------------+
bool CheckDoubleBarBreakout(bool is_long)
{
   if (!Use_Double_Bar_Breakout) return false;
   
   double ref_ema = GetReferenceEMA();
   
   for (int i = 2; i <= Volman_Lookback; i++) {
      double db_bar1_high = iHigh(Symbol(), 0, i);
      double db_bar1_low = iLow(Symbol(), 0, i);
      double db_bar2_high = iHigh(Symbol(), 0, i+1);
      double db_bar2_low = iLow(Symbol(), 0, i+1);
      double db_bar3_close = iClose(Symbol(), 0, i-1);
      
      if (is_long) {
         // 2本連続で安値がEMAタッチ
         bool bar1_touch = (db_bar1_low <= ref_ema && db_bar1_low >= ref_ema - 3*pip);
         bool bar2_touch = (db_bar2_low <= ref_ema && db_bar2_low >= ref_ema - 3*pip);
         // 3本目で上抜け
         bool bar3_break = (db_bar3_close > MathMax(db_bar1_high, db_bar2_high));
         
         if (bar1_touch && bar2_touch && bar3_break) {
            if (EnableDebugLog) Print(">>> ダブルバーブレイクアウト[ロング]検出 @ Bar", i);
            return true;
         }
      } else {
         // 2本連続で高値がEMAタッチ
         bool bar1_touch = (db_bar1_high >= ref_ema && db_bar1_high <= ref_ema + 3*pip);
         bool bar2_touch = (db_bar2_high >= ref_ema && db_bar2_high <= ref_ema + 3*pip);
         // 3本目で下抜け
         bool bar3_break = (db_bar3_close < MathMin(db_bar1_low, db_bar2_low));
         
         if (bar1_touch && bar2_touch && bar3_break) {
            if (EnableDebugLog) Print(">>> ダブルバーブレイクアウト[ショート]検出 @ Bar", i);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| IRB（インサイドバーリバーサル）検出                                |
//| インサイドバー形成→ブレイク方向にエントリー                         |
//+------------------------------------------------------------------+
bool CheckIRB(bool is_long)
{
   if (!Use_IRB) return false;
   
   for (int i = 1; i <= Volman_Lookback; i++) {
      if (IsInsideBar(i)) {
         double inside_high = iHigh(Symbol(), 0, i);
         double inside_low = iLow(Symbol(), 0, i);
         double current_close = iClose(Symbol(), 0, 1);
         
         if (is_long && current_close > inside_high) {
            if (EnableDebugLog) Print(">>> IRB[ロング]検出 @ Bar", i);
            return true;
         }
         if (!is_long && current_close < inside_low) {
            if (EnableDebugLog) Print(">>> IRB[ショート]検出 @ Bar", i);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| フェイルドブレイクリバーサル検出（Volman式）                        |
//| 高値/安値更新失敗→即反転                                          |
//+------------------------------------------------------------------+
bool CheckFailedBreakReversal(bool is_long)
{
   if (!Use_Failed_Break_Reversal) return false;
   
   double bar1_high = iHigh(Symbol(), 0, 1);
   double bar1_low = iLow(Symbol(), 0, 1);
   double bar1_close = iClose(Symbol(), 0, 1);
   
   for (int i = 2; i <= Volman_Lookback; i++) {
      double fbr_prev_high = iHigh(Symbol(), 0, i);
      double fbr_prev_low = iLow(Symbol(), 0, i);
      
      if (is_long) {
         // 安値更新試みるも失敗→反転上昇
         bool attempted_lower = (bar1_low <= fbr_prev_low);
         bool failed_close = (bar1_close > fbr_prev_low + 2*pip);
         bool rising = (bar1_close > iClose(Symbol(), 0, 2));
         
         if (attempted_lower && failed_close && rising) {
            if (EnableDebugLog) Print(">>> フェイルドブレイク[ロング]検出");
            return true;
         }
      } else {
         // 高値更新試みるも失敗→反転下降
         bool attempted_higher = (bar1_high >= fbr_prev_high);
         bool failed_close = (bar1_close < fbr_prev_high - 2*pip);
         bool falling = (bar1_close < iClose(Symbol(), 0, 2));
         
         if (attempted_higher && failed_close && falling) {
            if (EnableDebugLog) Print(">>> フェイルドブレイク[ショート]検出");
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| MACD反転検出                                                       |
//+------------------------------------------------------------------+
bool CheckMACDReversal(bool is_long)
{
   if (!Use_MACD) return false;
   
   // MACD値取得
   double macd_current = iMACD(Symbol(), 0, MACD_FastEMA, MACD_SlowEMA, MACD_Signal, PRICE_CLOSE, MODE_MAIN, 1);
   double macd_previous = iMACD(Symbol(), 0, MACD_FastEMA, MACD_SlowEMA, MACD_Signal, PRICE_CLOSE, MODE_MAIN, 2);
   double signal_current = iMACD(Symbol(), 0, MACD_FastEMA, MACD_SlowEMA, MACD_Signal, PRICE_CLOSE, MODE_SIGNAL, 1);
   double signal_previous = iMACD(Symbol(), 0, MACD_FastEMA, MACD_SlowEMA, MACD_Signal, PRICE_CLOSE, MODE_SIGNAL, 2);
   
   // MACDラインクロス
   bool macd_cross_up = (macd_previous < signal_previous) && (macd_current > signal_current);
   bool macd_cross_down = (macd_previous > signal_previous) && (macd_current < signal_current);
   
   // ヒストグラム反転
   double hist_current = macd_current - signal_current;
   double hist_previous = macd_previous - signal_previous;
   bool hist_reversal_up = (hist_previous < 0) && (hist_current > 0);
   bool hist_reversal_down = (hist_previous > 0) && (hist_current < 0);
   
   if (is_long && (macd_cross_up || hist_reversal_up)) {
      if (EnableDebugLog) Print(">>> MACD上昇反転検出");
      return true;
   }
   
   if (!is_long && (macd_cross_down || hist_reversal_down)) {
      if (EnableDebugLog) Print(">>> MACD下降反転検出");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 失敗ブレイク検出（トレンド転換シグナル）                           |
//+------------------------------------------------------------------+
bool CheckFailedBreak(bool is_long)
{
   if (!Use_FailedBreak) return false;
   
   // BBミドルライン取得
   double bb_middle;
   if (BB_Use_EMA_Middle) {
      bb_middle = iMA(Symbol(), 0, BB_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   } else {
      bb_middle = iBands(Symbol(), 0, BB_Period, BB_Deviation, 0, PRICE_CLOSE, MODE_MAIN, 1);
   }
   
   // BB上下限を計算
   double stddev = iStdDev(Symbol(), 0, BB_Period, 0, MODE_SMA, PRICE_CLOSE, 1);
   double bb_upper = bb_middle + (BB_Deviation * stddev);
   double bb_lower = bb_middle - (BB_Deviation * stddev);
   
   double bar1_high = iHigh(Symbol(), 0, 1);
   double bar1_low = iLow(Symbol(), 0, 1);
   double bar1_close = iClose(Symbol(), 0, 1);
   
   double bar2_high = iHigh(Symbol(), 0, 2);
   double bar2_low = iLow(Symbol(), 0, 2);
   
   // ロング: 下降トレンド終了 → 下限タッチ後の反発
   if (is_long) {
      bool break_lower = (bar2_low < bb_lower);  // 前々足で下抜け
      bool return_inside = (bar1_close > bb_lower);  // 前足で戻る
      bool price_rising = (bar1_close > iClose(Symbol(), 0, 2));  // 価格上昇中
      
      if (break_lower && return_inside && price_rising) {
         if (EnableDebugLog) Print(">>> 失敗ブレイク[下限反発→上昇]検出");
         return true;
      }
   }
   
   // ショート: 上昇トレンド終了 → 上限タッチ後の反落
   if (!is_long) {
      bool break_upper = (bar2_high > bb_upper);  // 前々足で上抜け
      bool return_inside = (bar1_close < bb_upper);  // 前足で戻る
      bool price_falling = (bar1_close < iClose(Symbol(), 0, 2));  // 価格下落中
      
      if (break_upper && return_inside && price_falling) {
         if (EnableDebugLog) Print(">>> 失敗ブレイク[上限反落→下降]検出");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 補助条件チェック（Entry_Confirmations数を満たすか）                |
//+------------------------------------------------------------------+
bool CheckAuxiliaryConditions(bool is_long)
{
   if (g_Entry_Confirmations == 0) return true;  // 補助条件不要
   
   int confirmations = 0;
   
   // 1. Volmanダブルバー
   if (Use_Volman_Patterns && CheckDoubleBarBreakout(is_long)) {
      confirmations++;
      if (EnableDebugLog) Print("  [補助+1] ダブルバーブレイクアウト");
   }
   
   // 2. IRB
   if (Use_Volman_Patterns && CheckIRB(is_long)) {
      confirmations++;
      if (EnableDebugLog) Print("  [補助+1] IRB");
   }
   
   // 3. フェイルドブレイクリバーサル
   if (Use_Volman_Patterns && CheckFailedBreakReversal(is_long)) {
      confirmations++;
      if (EnableDebugLog) Print("  [補助+1] フェイルドブレイクリバーサル");
   }
   
   // 4. MACD反転
   if (CheckMACDReversal(is_long)) {
      confirmations++;
      if (EnableDebugLog) Print("  [補助+1] MACD反転");
   }
   
   // 5. 失敗ブレイク
   if (CheckFailedBreak(is_long)) {
      confirmations++;
      if (EnableDebugLog) Print("  [補助+1] 失敗ブレイク");
   }
   
   if (EnableDebugLog) {
      Print("補助条件スコア: ", confirmations, " / ", Entry_Confirmations);
   }
   
   return (confirmations >= g_Entry_Confirmations);
}

//+------------------------------------------------------------------+
//| トレンドライン価格取得（手動オブジェクト）                          |
//+------------------------------------------------------------------+
double GetTrendlinePrice(string obj_name, int shift)
{
   if (ObjectFind(0, obj_name) < 0) {
      return 0.0;  // オブジェクトが存在しない
   }
   
   // トレンドラインの価格を取得
   datetime time1 = (datetime)ObjectGet(obj_name, OBJPROP_TIME1);
   double price1 = ObjectGet(obj_name, OBJPROP_PRICE1);
   datetime time2 = (datetime)ObjectGet(obj_name, OBJPROP_TIME2);
   double price2 = ObjectGet(obj_name, OBJPROP_PRICE2);
   
   // 現在バーの時刻
   datetime bar_time = iTime(Symbol(), 0, shift);
   
   // トレンドラインの傾き計算
   double slope = (price2 - price1) / (time2 - time1);
   
   // shift本前の価格計算
   double tl_price = price2 + slope * (bar_time - time2);
   
   return tl_price;
}

//+------------------------------------------------------------------+
//| トレンドラインプルバック検出（順張り）                             |
//+------------------------------------------------------------------+
bool DetectTrendlinePullback(bool is_long, int &signal_type)
{
   // signal_type: 1=ロング, -1=ショート, 0=シグナルなし
   
   if (g_TL_Channel_Mode != MODE_TRENDLINE_TREND) {
      return false;
   }
   
   // トレンドライン名決定
   string tl_name = is_long ? g_TL_Lower_Name : g_TL_Upper_Name;
   
   if (ObjectFind(0, tl_name) < 0) {
      if (EnableDebugLog) Print("トレンドライン [", tl_name, "] が見つかりません");
      return false;
   }
   
   double buffer = g_TL_Touch_Buffer_Points * point_size;
   
   // 過去N本でプルバック検出
   for (int i = 1; i <= g_TL_Lookback_Bars; i++) {
      double bar_high = iHigh(Symbol(), 0, i);
      double bar_low = iLow(Symbol(), 0, i);
      double bar_close = iClose(Symbol(), 0, i);
      
      double tl_price = GetTrendlinePrice(tl_name, i);
      if (tl_price == 0.0) continue;
      
      // タイプA: タッチ
      if (g_TL_Use_Touch) {
         if (is_long && bar_low <= (tl_price + buffer) && bar_low >= (tl_price - buffer)) {
            pullback_type = "トレンドラインタッチ（順張り）";
            signal_type = 1;
            if (EnableDebugLog) Print(">>> トレンドラインタッチ検出 [", i, "本前]: ロングシグナル");
            return true;
         }
         if (!is_long && bar_high >= (tl_price - buffer) && bar_high <= (tl_price + buffer)) {
            pullback_type = "トレンドラインタッチ（順張り）";
            signal_type = -1;
            if (EnableDebugLog) Print(">>> トレンドラインタッチ検出 [", i, "本前]: ショートシグナル");
            return true;
         }
      }
      
      // タイプB/C: クロス、ブレイク（実装省略、必要に応じて追加）
   }
   
   signal_type = 0;
   return false;
}

//+------------------------------------------------------------------+
//| チャネルラインレンジ逆張り検出                                     |
//+------------------------------------------------------------------+
bool DetectChannelRangePullback(int &signal_type)
{
   // signal_type: 1=ロング, -1=ショート, 0=シグナルなし
   
   if (g_TL_Channel_Mode != MODE_CHANNEL_RANGE) {
      return false;
   }
   
   // 上限/下限ライン存在確認
   if (ObjectFind(0, g_TL_Upper_Name) < 0 || ObjectFind(0, g_TL_Lower_Name) < 0) {
      if (EnableDebugLog) Print("チャネルライン [", g_TL_Upper_Name, "]/[", g_TL_Lower_Name, "] が見つかりません");
      return false;
   }
   
   double buffer = g_TL_Touch_Buffer_Points * point_size;
   
   // 過去N本で逆張りシグナル検出
   for (int i = 1; i <= g_TL_Lookback_Bars; i++) {
      double bar_high = iHigh(Symbol(), 0, i);
      double bar_low = iLow(Symbol(), 0, i);
      
      double upper_price = GetTrendlinePrice(g_TL_Upper_Name, i);
      double lower_price = GetTrendlinePrice(g_TL_Lower_Name, i);
      
      if (upper_price == 0.0 || lower_price == 0.0) continue;
      
      // チャネル幅検証
      double channel_width = upper_price - lower_price;
      if (channel_width < 10 * point_size) continue;
      
      // 下限タッチ → ロング（逆張り）
      if (g_TL_Use_Touch && bar_low <= (lower_price + buffer) && bar_low >= (lower_price - buffer)) {
         // プライスアクション反転パターン確認
         if (CheckBullishReversal(i)) {
            pullback_type = "チャネル下限反発（逆張り）";
            signal_type = 1;
            if (EnableDebugLog) Print(">>> チャネル逆張り: 下限タッチ → ロングシグナル [", i, "本前]");
            return true;
         }
      }
      
      // 上限タッチ → ショート（逆張り）
      if (g_TL_Use_Touch && bar_high >= (upper_price - buffer) && bar_high <= (upper_price + buffer)) {
         // プライスアクション反転パターン確認
         if (CheckBearishReversal(i)) {
            pullback_type = "チャネル上限反発（逆張り）";
            signal_type = -1;
            if (EnableDebugLog) Print(">>> チャネル逆張り: 上限タッチ → ショートシグナル [", i, "本前]");
            return true;
         }
      }
   }
   
   signal_type = 0;
   return false;
}

//+------------------------------------------------------------------+
//| 強気反転パターン検出（ピンバー: ハンマー）                         |
//+------------------------------------------------------------------+
bool CheckBullishPinbar(int shift)
{
   if (!g_PA_Use_Pinbar) return false;
   
   double open = iOpen(Symbol(), 0, shift);
   double close = iClose(Symbol(), 0, shift);
   double high = iHigh(Symbol(), 0, shift);
   double low = iLow(Symbol(), 0, shift);
   double body = MathAbs(close - open);
   
   if (body < 0.1 * Point * 10) return false;  // 実体が小さすぎる
   
   // 下ヒゲ（ロングの場合）
   double lower_shadow = (close > open) ? (open - low) : (close - low);
   double upper_shadow = (close > open) ? (high - close) : (high - open);
   
   // ピンバー判定: 下ヒゲが実体の2倍以上、上ヒゲが実体の0.5倍以下
   if (lower_shadow > body * g_PA_Pinbar_Shadow_Ratio && 
       upper_shadow < body * g_PA_Pinbar_Opposite_Shadow_Ratio) {
      if (EnableDebugLog) Print("  → 強気ピンバー（ハンマー）検出 [", shift, "本前]");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 弱気反転パターン検出（ピンバー: シューティングスター）              |
//+------------------------------------------------------------------+
bool CheckBearishPinbar(int shift)
{
   if (!g_PA_Use_Pinbar) return false;
   
   double open = iOpen(Symbol(), 0, shift);
   double close = iClose(Symbol(), 0, shift);
   double high = iHigh(Symbol(), 0, shift);
   double low = iLow(Symbol(), 0, shift);
   double body = MathAbs(close - open);
   
   if (body < 0.1 * Point * 10) return false;
   
   // 上ヒゲ（ショートの場合）
   double lower_shadow = (close > open) ? (open - low) : (close - low);
   double upper_shadow = (close > open) ? (high - close) : (high - open);
   
   // シューティングスター: 上ヒゲが実体の2倍以上、下ヒゲが実体の0.5倍以下
   if (upper_shadow > body * g_PA_Pinbar_Shadow_Ratio && 
       lower_shadow < body * g_PA_Pinbar_Opposite_Shadow_Ratio) {
      if (EnableDebugLog) Print("  → 弱気ピンバー（シューティングスター）検出 [", shift, "本前]");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 強気エンゴルフィング検出                                          |
//+------------------------------------------------------------------+
bool CheckBullishEngulfing(int shift)
{
   if (!g_PA_Use_Engulfing) return false;
   
   double open_current = iOpen(Symbol(), 0, shift);
   double close_current = iClose(Symbol(), 0, shift);
   double open_prev = iOpen(Symbol(), 0, shift + 1);
   double close_prev = iClose(Symbol(), 0, shift + 1);
   
   // 現在足が陽線、前足が陰線
   if (close_current <= open_current) return false;
   if (close_prev >= open_prev) return false;
   
   // エンゴルフィング判定: 現在足が前足を完全に包む
   if (close_current > open_prev && open_current < close_prev) {
      if (EnableDebugLog) Print("  → 強気エンゴルフィング検出 [", shift, "本前]");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 弱気エンゴルフィング検出                                          |
//+------------------------------------------------------------------+
bool CheckBearishEngulfing(int shift)
{
   if (!g_PA_Use_Engulfing) return false;
   
   double open_current = iOpen(Symbol(), 0, shift);
   double close_current = iClose(Symbol(), 0, shift);
   double open_prev = iOpen(Symbol(), 0, shift + 1);
   double close_prev = iClose(Symbol(), 0, shift + 1);
   
   // 現在足が陰線、前足が陽線
   if (close_current >= open_current) return false;
   if (close_prev <= open_prev) return false;
   
   // エンゴルフィング判定
   if (close_current < open_prev && open_current > close_prev) {
      if (EnableDebugLog) Print("  → 弱気エンゴルフィング検出 [", shift, "本前]");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 強気反転パターン統合チェック                                       |
//+------------------------------------------------------------------+
bool CheckBullishReversal(int shift)
{
   if (!g_PA_Require_Reversal) return true;  // 反転パターン不要
   
   // ピンバーまたはエンゴルフィング
   if (CheckBullishPinbar(shift) || CheckBullishEngulfing(shift)) {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 弱気反転パターン統合チェック                                       |
//+------------------------------------------------------------------+
bool CheckBearishReversal(int shift)
{
   if (!g_PA_Require_Reversal) return true;
   
   if (CheckBearishPinbar(shift) || CheckBearishEngulfing(shift)) {
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 最も近いラウンドナンバーを取得                                     |
//| 日経225: RN_Digit_Level=0 → 39000, 39500                        |
//|         RN_Digit_Level=1 → 39100, 39200...                     |
//+------------------------------------------------------------------+
double GetNearestRoundNumber(double price, bool is_00_line)
{
   int divisor = 1000;  // デフォルト: 1000単位（39000, 40000...）
   
   if (g_RN_Digit_Level == 1) {
      divisor = 100;  // 100単位（39100, 39200...）
   } else if (g_RN_Digit_Level == 2) {
      divisor = 10;   // 10単位（39010, 39020...）
   }
   
   // .00ライン: divisor単位でRound（39000, 40000 or 39100, 39200...）
   if (is_00_line) {
      double rounded = MathFloor(price / divisor) * divisor;
      double upper = rounded + divisor;
      
      // 近い方を返す
      if (MathAbs(price - rounded) < MathAbs(price - upper)) {
         return rounded;
      } else {
         return upper;
      }
   }
   // .50ライン: divisor/2単位でOffset（39500, 40500 or 39150, 39250...）
   else {
      int half_divisor = divisor / 2;
      double rounded = MathFloor(price / divisor) * divisor + half_divisor;
      double upper = rounded + divisor;
      
      // 近い方を返す
      if (MathAbs(price - rounded) < MathAbs(price - upper)) {
         return rounded;
      } else {
         return upper;
      }
   }
}

//+------------------------------------------------------------------+
//| ラウンドナンバープルバック検出                                     |
//| ★重要: タッチだけでなく反発確認が必須                            |
//+------------------------------------------------------------------+
bool DetectRoundNumberPullback(bool is_long, int &signal_type)
{
   // signal_type: 1=ロング, -1=ショート, 0=シグナルなし
   
   if (!g_Use_RoundNumber_Lines) {
      return false;
   }
   
   double buffer = g_RN_Touch_Buffer_Points * 1.0;  // Points単位
   
   // 過去N本でラウンドナンバープルバック検出
   for (int i = 1; i <= g_RN_Lookback_Bars; i++) {
      double bar_high = iHigh(Symbol(), 0, i);
      double bar_low = iLow(Symbol(), 0, i);
      double bar_close = iClose(Symbol(), 0, i);
      
      // .00ラインチェック（1000/100/10単位）
      if (g_RN_Use_00_Line) {
         double rn_00 = GetNearestRoundNumber(bar_low, true);
         
         // 順張りモード: トレンド方向のプルバック＋反発確認必須
         if (!g_RN_Counter_Trend) {
            // ロング: .00ラインタッチ後の反発（反発確認必須）
            if (is_long && g_RN_Use_Touch && 
                bar_low <= (rn_00 + buffer) && bar_low >= (rn_00 - buffer)) {
               // ★反発確認: 陽線で終わっているか確認
               if (CheckBullishReversal(i)) {
                  pullback_type = "ラウンドナンバー.00タッチ＋反発（順張り）";
                  signal_type = 1;
                  roundnumber_entry_detected = true;
                  if (EnableDebugLog) Print(">>> RN.00タッチ＋反発確認 [", i, "本前]: ", DoubleToString(rn_00, Digits), " → ロング");
                  return true;
               } else {
                  if (EnableDebugLog) Print(">>> RN.00タッチ検出だが反発未確認 [", i, "本前]: ", DoubleToString(rn_00, Digits));
               }
            }
            
            // ショート: .00ラインタッチ後の反落（反落確認必須）
            if (!is_long && g_RN_Use_Touch && 
                bar_high >= (rn_00 - buffer) && bar_high <= (rn_00 + buffer)) {
               // ★反落確認: 陰線で終わっているか確認
               if (CheckBearishReversal(i)) {
                  pullback_type = "ラウンドナンバー.00タッチ＋反落（順張り）";
                  signal_type = -1;
                  roundnumber_entry_detected = true;
                  if (EnableDebugLog) Print(">>> RN.00タッチ＋反落確認 [", i, "本前]: ", DoubleToString(rn_00, Digits), " → ショート");
                  return true;
               } else {
                  if (EnableDebugLog) Print(">>> RN.00タッチ検出だが反落未確認 [", i, "本前]: ", DoubleToString(rn_00, Digits));
               }
            }
         }
         // 逆張りモード: ラウンドナンバーでの反転
         else {
            // .00ライン下限タッチ → ロング（逆張り）
            if (g_RN_Use_Touch && bar_low <= (rn_00 + buffer) && bar_low >= (rn_00 - buffer)) {
               if (CheckBullishReversal(i)) {
                  pullback_type = "ラウンドナンバー.00反発（逆張り）";
                  signal_type = 1;
                  roundnumber_entry_detected = true;
                  if (EnableDebugLog) Print(">>> RN.00逆張り [", i, "本前]: ", DoubleToString(rn_00, Digits), " → ロング");
                  return true;
               }
            }
            
            // .00ライン上限タッチ → ショート（逆張り）
            if (g_RN_Use_Touch && bar_high >= (rn_00 - buffer) && bar_high <= (rn_00 + buffer)) {
               if (CheckBearishReversal(i)) {
                  pullback_type = "ラウンドナンバー.00反落（逆張り）";
                  signal_type = -1;
                  roundnumber_entry_detected = true;
                  if (EnableDebugLog) Print(">>> RN.00逆張り [", i, "本前]: ", DoubleToString(rn_00, Digits), " → ショート");
                  return true;
               }
            }
         }
      }
      
      // .50ラインチェック（500/50/5単位）
      if (g_RN_Use_50_Line) {
         double rn_50 = GetNearestRoundNumber(bar_low, false);
         
         // 順張りモード: 反発確認必須
         if (!g_RN_Counter_Trend) {
            if (is_long && g_RN_Use_Touch && 
                bar_low <= (rn_50 + buffer) && bar_low >= (rn_50 - buffer)) {
               if (CheckBullishReversal(i)) {
                  pullback_type = "ラウンドナンバー.50タッチ＋反発（順張り）";
                  signal_type = 1;
                  roundnumber_entry_detected = true;
                  if (EnableDebugLog) Print(">>> RN.50タッチ＋反発確認 [", i, "本前]: ", DoubleToString(rn_50, Digits), " → ロング");
                  return true;
               } else {
                  if (EnableDebugLog) Print(">>> RN.50タッチ検出だが反発未確認 [", i, "本前]: ", DoubleToString(rn_50, Digits));
               }
            }
            
            if (!is_long && g_RN_Use_Touch && 
                bar_high >= (rn_50 - buffer) && bar_high <= (rn_50 + buffer)) {
               if (CheckBearishReversal(i)) {
                  pullback_type = "ラウンドナンバー.50タッチ＋反落（順張り）";
                  signal_type = -1;
                  roundnumber_entry_detected = true;
                  if (EnableDebugLog) Print(">>> RN.50タッチ＋反落確認 [", i, "本前]: ", DoubleToString(rn_50, Digits), " → ショート");
                  return true;
               } else {
                  if (EnableDebugLog) Print(">>> RN.50タッチ検出だが反落未確認 [", i, "本前]: ", DoubleToString(rn_50, Digits));
               }
            }
         } else {
            // 逆張りモード
            if (g_RN_Use_Touch && bar_low <= (rn_50 + buffer) && bar_low >= (rn_50 - buffer)) {
               if (CheckBullishReversal(i)) {
                  pullback_type = "ラウンドナンバー.50反発（逆張り）";
                  signal_type = 1;
                  roundnumber_entry_detected = true;
                  if (EnableDebugLog) Print(">>> RN.50逆張り [", i, "本前]: ", DoubleToString(rn_50, Digits), " → ロング");
                  return true;
               }
            }
            
            if (g_RN_Use_Touch && bar_high >= (rn_50 - buffer) && bar_high <= (rn_50 + buffer)) {
               if (CheckBearishReversal(i)) {
                  pullback_type = "ラウンドナンバー.50反落（逆張り）";
                  signal_type = -1;
                  roundnumber_entry_detected = true;
                  if (EnableDebugLog) Print(">>> RN.50逆張り [", i, "本前]: ", DoubleToString(rn_50, Digits), " → ショート");
                  return true;
               }
            }
         }
      }
   }
   
   signal_type = 0;
   return false;
}

