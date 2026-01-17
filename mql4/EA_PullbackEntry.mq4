//+------------------------------------------------------------------+
//|                                              EA_PullbackEntry.mq4 |
//|                                  Pullback Entry Specialist System |
//|                          トレンド中のプルバックのみを狙う専用EA     |
//+------------------------------------------------------------------+
#property copyright "Pullback Entry Specialist"
#property link      ""
#property version   "1.11"
#property strict

// Market Sentinel連携（経済指標・要人発言による売買制御）※サービス削除済み - 無効
// #include <MarketSentinel.mqh>  // サービス削除済み - 不要

// マジックナンバー自動生成
#include <MagicNumberGenerator.mqh>

// AIポートフォリオマネージャー連携（口座状態CSV）
#include <AccountStatusCsv.mqh>

// TradeOptimizer連携（パラメータ自動最適化）※サービス削除済み - 無効
// #include <EAParamsLoader.mqh>  // サービス削除済み - 不要

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
   SLTP_FIXED,    // 固定pips
   SLTP_ATR       // ATR基準
};

// Trailing Mode
enum TrailingMode {
   TRAILING_FIXED_PIPS,   // 固定pips
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
input string InpTerminalId = "10900k-A";         // 論理ターミナルID（例: 10900k-mt4-fx）

//--- 基本設定
input bool   AutoMagicNumber = true;            // マジックナンバー自動生成
input int    MagicNumber = 99999;                // マジックナンバー（自動生成時は無視）
input double LotSize = 0.1;                      // 基準ロットサイズ
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
input double Confirmation_Bar_Min_Size = 5.0;    // 確認足最小サイズ(pips)
input double Confirmation_Bar_Max_Size = 20.0;   // 確認足最大サイズ(pips、0=無制限)

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
input double Entry_Buffer_Pips = 1.0;            // ブレイクバッファ(pips)
input int    Max_Slippage_Pips = 3;              // 最大スリッページ(pips)
input int    Max_Slippage_Points = 0;            // 最大スリッページ(points) ※互換用、0=pips換算を使用
input bool   Use_Slippage_Pips_Conversion = false; // スリッページのpips→points換算を有効化（true推奨）※互換のため既定false
input double Max_Spread_Pips = 5.0;              // 最大スプレッド(pips)

//--- 相場環境フィルター
input bool   Use_ADX_Filter = true;              // ADXフィルター使用
input int    ADX_Period = 14;                    // ADX期間
input double ADX_Min_Level = 20.0;               // ADX最低値（20以下=レンジ）
input double Max_Spread_Multiplier = 3.0;        // 通常スプレッドの何倍まで許容
input bool   Use_Channel_Width_Filter = true;    // チャネル幅フィルター使用
input int    Channel_Width_Period = 20;          // チャネル幅計算期間
input double Min_Channel_Width_Pips = 30.0;      // 最低チャネル幅（pips）

//--- ATR設定
input int    ATR_Period = 14;                    // ATR期間
input double ATR_Threshold_Pips = 7.0;           // ATR最低値（互換用。ログは price units / MT4pt を併記）

//--- SL/TP設定
input bool   Use_StopLoss = true;                // SL使用
input bool   Use_TakeProfit = true;              // TP使用
input SLTPMode SLTP_Mode = SLTP_FIXED;           // SLTP モード
input double StopLoss_Fixed_Pips = 15.0;         // 固定SL(pips)
input double TakeProfit_Fixed_Pips = 30.0;       // 固定TP(pips)
input double StopLoss_ATR_Multi = 1.5;           // SL用ATR倍率
input double TakeProfit_ATR_Multi = 2.0;         // TP用ATR倍率

//--- 段階的利確設定
input bool   EnablePartialClose = false;         // 段階的利確有効化
input int    PartialCloseLevels = 2;             // 利確レベル数(1, 2, 3)
input bool   UseTPForFinalLevel = true;          // 最終レベルをMT4のTPとして設定
input double PartialClosePercent1 = 50.0;        // 第1利確割合(%)
input double PartialCloseLevel1_Pips = 15.0;     // 第1利確レベル(pips)
input double PartialClosePercent2 = 50.0;        // 第2利確割合(%)
input double PartialCloseLevel2_Pips = 30.0;     // 第2利確レベル(pips)
input double PartialClosePercent3 = 0.0;         // 第3利確割合(%)
input double PartialCloseLevel3_Pips = 45.0;     // 第3利確レベル(pips)

//--- 建値移動設定
input bool   MoveToBreakevenOnPartial1 = true;   // 第1利確でSLを建値へ
input bool   MoveToTP1OnPartial2 = false;        // 第2利確でSLを第1利確価格へ
input double BreakevenOffset_Pips = 0.0;         // 建値オフセット(pips)

//--- トレーリングストップ設定
input bool   EnableTrailingAfterTP2 = false;     // 第2利確後トレーリング
input TrailingMode Trailing_Mode = TRAILING_ATR; // トレーリングモード
input double TrailingStop_Fixed_Pips = 10.0;     // 固定pips幅
input double TrailingStop_ATR_Multi = 1.0;       // ATR倍率
input int    Trailing_ATR_Period = 14;           // トレーリング用ATR期間
input double TrailingUpdate_Step_Pips = 5.0;     // 更新ステップ(pips)

//--- 時間フィルター設定
input bool   Enable_Time_Filter = false;         // 時間フィルター有効化
input int    GMT_Offset = 3;                     // GMTオフセット
input bool   Use_DST = false;                    // 夏時間適用
input int    Custom_Start_Hour = 8;              // 稼働開始時(日本時間)
input int    Custom_Start_Minute = 0;            // 稼働開始分
input int    Custom_End_Hour = 21;               // 稼働終了時(日本時間)
input int    Custom_End_Minute = 0;              // 稼働終了分

//--- トレンドライン/チャネル設定
input TrendlineChannelMode TL_Channel_Mode = MODE_DISABLED;  // モード選択
input string TL_Upper_Name = "TL_Upper";         // 上限ライン名（チャネル上限/下降トレンドライン）
input string TL_Lower_Name = "TL_Lower";         // 下限ライン名（チャネル下限/上昇トレンドライン）
input double TL_Touch_Buffer_Pips = 2.0;         // タッチ判定バッファ(pips)
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

//--- ラウンドナンバー(.00/.50)ライン設定
input bool   Use_RoundNumber_Lines = false;      // .00/.50ライン使用
input bool   RN_Use_00_Line = true;              // .00ライン使用
input bool   RN_Use_50_Line = true;              // .50ライン使用
input double RN_Touch_Buffer_Pips = 2.0;         // タッチ判定バッファ(pips)
input bool   RN_Use_Touch = true;                // タッチパターン
input bool   RN_Use_Cross = true;                // クロスパターン
input bool   RN_Use_Break = false;               // ブレイクパターン
input int    RN_Lookback_Bars = 3;               // 検出期間(バー数)
input bool   RN_Counter_Trend = false;           // 逆張りモード（反転狙い）
input int    RN_Digit_Level = 2;                 // 桁数レベル（2=100.00, 3=100.000）

//--- ラウンドナンバー付近エントリー回避設定
input bool   RN_Avoid_Entry_Near = false;        // .00/.50付近でのエントリー回避
input double RN_Avoid_Buffer_Pips = 5.0;         // 回避範囲(pips) ※プルバックタッチ時は除外

//--- マルチレイヤー設定
input bool   ML_Require_EMA = true;              // EMAレイヤー必須
input bool   ML_Require_Trendline = false;       // トレンドライン/チャネルレイヤー必須
input bool   ML_Require_RoundNumber = false;     // ラウンドナンバーレイヤー必須
input int    ML_Min_Layers = 1;                  // 最小一致レイヤー数（1-3）
input bool   ML_Bonus_Multi_Layer = true;        // 複数レイヤー一致時ボーナス（ログ強調）

//--- AI対応設定（GPU不要、軽量アルゴリズム）
input bool   Use_Micro_Volatility_Filter = false; // マイクロボラティリティフィルター（HFTノイズ除外）
input double Min_Bar_Range_Pips = 3.0;           // 最小バーサイズ(pips) - これ未満はノイズ
input int    Noise_Detection_Period = 10;       // ノイズ検出期間(バー数)
input double Noise_Ratio_Threshold = 0.6;       // ノイズ比率閾値(0.0-1.0)

input bool   Use_Algo_Price_Levels = false;     // アルゴ価格レベル検出
input double Algo_Price_Clustering = 5.0;       // 価格集中度(pips) - アルゴ反応範囲
input bool   Use_Quarter_Levels = true;         // 0.25刻みレベル使用（AIの好む価格帯）

input bool   Use_OrderFlow_Detection = false;   // オーダーフロー検出（ティックボリューム分析）
input double OrderFlow_Volume_Multi = 2.0;      // ボリューム倍率（この倍以上で大量注文）
input int    OrderFlow_Avg_Period = 9;          // 平均ボリューム計算期間

input bool   Use_Algo_TimeFilter = false;       // アルゴ活発時間帯フィルター
input int    Algo_Active_Start_Hour = 21;       // アルゴ活発開始時刻(JST)
input int    Algo_Active_End_Hour = 24;         // アルゴ活発終了時刻(JST)

input bool   Enable_AI_Learning_Log = true;     // AI学習用ログ出力（DLL推論EA用データ収集）

//--- ログ出力設定
input bool   EnableCsvLogging = true;            // CSVログ出力を有効化
input bool   LogSkipEvents = true;               // スキップ理由も記録
input string CsvLogFolder = "OneDriveLogs";      // ログ保存ルートフォルダ（自動でサブフォルダ作成）
input int    SkipLogCooldownSeconds = 60;        // 同一スキップログの抑制秒数

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
// 戦略設定用変数（プリセットで上書き可能）
double g_StopLoss_Pips;
double g_TakeProfit_Pips;
bool g_EnablePartialClose;
int g_PartialCloseLevels;
double g_PartialClosePercent1;
double g_PartialCloseLevel1_Pips;
double g_PartialClosePercent2;
double g_PartialCloseLevel2_Pips;
double g_PartialClosePercent3;
double g_PartialCloseLevel3_Pips;
bool g_MoveToBreakevenOnPartial1;
double g_BreakevenOffset_Pips;
bool g_EnableTrailingAfterTP2;
TrailingMode g_Trailing_Mode;
double g_TrailingStop_Fixed_Pips;
double g_TrailingStop_ATR_Multi;
double g_TrailingUpdate_Step_Pips;
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
double g_TL_Touch_Buffer_Pips;
bool g_TL_Use_Touch;
bool g_TL_Use_Cross;
bool g_TL_Use_Break;
int g_TL_Lookback_Bars;
bool g_PA_Require_Reversal;
bool g_PA_Use_Pinbar;
bool g_PA_Use_Engulfing;
double g_PA_Pinbar_Shadow_Ratio;
double g_PA_Pinbar_Opposite_Shadow_Ratio;

// ラウンドナンバーライン設定用変数
bool g_Use_RoundNumber_Lines;
bool g_RN_Use_00_Line;
bool g_RN_Use_50_Line;
double g_RN_Touch_Buffer_Pips;
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
double g_Min_Channel_Width_Pips;
double g_ATR_Threshold_Pips;

// EMA値
double ema12_current, ema12_previous;
double ema25_current, ema25_previous;
double ema100_current, ema100_previous;

// ATR値
double current_atr;

// 価格情報
double prev_high = 0;
double prev_low = 0;
double pip;
double point_size;

string FormatAtrMinPriceAndMt4pt_FromPips(double atr_pips)
{
   double pip_local = (pip > 0.0) ? pip : ((Digits == 3 || Digits == 5) ? (10.0 * Point) : Point);
   double atr_price = atr_pips * pip_local;
   string atr_mt4pt_str = (Point > 0.0) ? DoubleToString(atr_price / Point, 1) : "N/A";
   return StringFormat("ATR >= %s (price units) / %s MT4pt (%s pips)",
                       DoubleToString(atr_price, Digits),
                       atr_mt4pt_str,
                       DoubleToString(atr_pips, 1));
}

// ポジション管理
int current_ticket = -1;
bool partial1_executed = false;
bool partial2_executed = false;
bool partial3_executed = false;
bool trailing_active = false;
double highest_price_trailing = 0;
double lowest_price_trailing = 0;

// ラウンドナンバー検出フラグ
bool roundnumber_entry_detected = false;  // ラウンドナンバー(.00/.50)でエントリー予定

// ラウンドナンバー回避設定用変数
bool g_RN_Avoid_Entry_Near;
double g_RN_Avoid_Buffer_Pips;

// AI対応用グローバル変数
bool g_Use_Micro_Volatility_Filter;
double g_Min_Bar_Range_Pips;
int g_Noise_Detection_Period;
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
#include "EA_AI_Functions.mqh"

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Market Sentinel初期化
   // MS_Init();  // サービス削除済み - 不要
   
   // EA パラメータローダー初期化（TradeOptimizer連携）
   // EAP_Init();  // サービス削除済み - 不要
   
   // マジックナンバー初期化
   if (AutoMagicNumber) {
      // プリセットからコードを取得
      int preset_code = PRESET_STANDARD;  // デフォルト
      switch(Selected_Strategy) {
         case STRATEGY_STANDARD:      preset_code = PRESET_STANDARD; break;
         case STRATEGY_CONSERVATIVE:  preset_code = PRESET_CONSERVATIVE; break;
         case STRATEGY_AGGRESSIVE:    preset_code = PRESET_AGGRESSIVE; break;
         case STRATEGY_AI_ADAPTIVE:   preset_code = PRESET_AI_ADAPTIVE; break;
         case STRATEGY_AI_SCOUT:      preset_code = PRESET_AI_SCOUT; break;
         case STRATEGY_MULTI_LAYER:   preset_code = PRESET_MULTI_LAYER; break;
         case STRATEGY_CUSTOM:        preset_code = PRESET_CUSTOM; break;
      }
      g_ActiveMagicNumber = GenerateMagicNumber(EA_TYPE_PULLBACK_ENTRY, Symbol(), preset_code);
      Print("マジックナンバー自動生成: ", g_ActiveMagicNumber);
      PrintMagicNumberInfo(g_ActiveMagicNumber);
   } else {
      g_ActiveMagicNumber = MagicNumber;
      Print("マジックナンバー手動設定: ", g_ActiveMagicNumber);
   }
   
   // 戦略プリセット適用
   ApplyStrategyPreset();
   
   // Point size and pip value
   if (Digits == 3 || Digits == 5) {
      point_size = Point * 10;
      pip = point_size;
   } else {
      point_size = Point;
      pip = Point;
   }
   
   // CSVログ初期化
   if (EnableCsvLogging) {
      InitializeCsvLog();
   }
   
   // 初期ATR確認
   double init_atr = iATR(Symbol(), 0, ATR_Period, 1);
   double init_atr_pips = init_atr / pip;
   double init_atr_mt4pt = (Point > 0.0) ? (init_atr / Point) : 0.0;

   double atr_thr_price = g_ATR_Threshold_Pips * pip;
   double atr_thr_mt4pt = (Point > 0.0) ? (atr_thr_price / Point) : 0.0;
   
   Print("===== EA_PullbackEntry 初期化完了 =====");
   Print("シンボル: ", Symbol());
   Print("時間足: ", Period());
   Print("Digits: ", Digits);
   Print("Point: ", DoubleToString(Point, Digits));
   Print("Pip: ", DoubleToString(pip, Digits));
   Print("マジックナンバー: ", g_ActiveMagicNumber, AutoMagicNumber ? " (自動生成)" : " (手動設定)");
   Print("プルバック基準EMA: ", GetEMAName(Pullback_EMA));
   Print("EMAタッチ: ", Use_Touch_Pullback);
   Print("EMAクロス: ", Use_Cross_Pullback);
   Print("EMA完全ブレイク: ", g_Use_Break_Pullback);
   Print("ATR期間: ", ATR_Period);
   Print(StringFormat("ATR閾値設定: %s (price units) / %s MT4pt (%s pips)",
                      DoubleToString(atr_thr_price, Digits),
                      DoubleToString(atr_thr_mt4pt, 0),
                      DoubleToString(g_ATR_Threshold_Pips, 1)));
   Print(StringFormat("現在のATR: %s (price units) / %s MT4pt (%s pips)",
                      DoubleToString(init_atr, Digits),
                      DoubleToString(init_atr_mt4pt, 0),
                      DoubleToString(init_atr_pips, 2)));
   
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

   ExportAccountStatusWithTerminalId(InpTerminalId);
   
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
   static datetime last_export = 0;
   datetime now = TimeCurrent();
   if(now - last_export >= 60)
   {
      ExportAccountStatusWithTerminalId(InpTerminalId);
      last_export = now;
   }

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
   
   // 2. スプレッドチェック
   double current_spread = (Ask - Bid) / pip;
   if (current_spread > Max_Spread_Pips) {
      LogSkipReason("スプレッド過大: " + DoubleToString(current_spread, 1) + " pips");
      return;
   }
   
   // 3. スプレッド異常検出
   double normal_spread = 2.0; // FXの通常スプレッド（pips）
   if (current_spread > normal_spread * Max_Spread_Multiplier) {
      LogSkipReason("スプレッド異常: " + DoubleToString(current_spread, 1) + " pips > " + DoubleToString(normal_spread * Max_Spread_Multiplier, 1) + " pips");
      return;
   }
   
   // 4. ATRチェック
   double atr_pips = current_atr / pip;
   double atr_mt4pt = (Point > 0.0) ? (current_atr / Point) : 0.0;
   double thr_price = g_ATR_Threshold_Pips * pip;
   double thr_mt4pt = (Point > 0.0) ? (thr_price / Point) : 0.0;
   if (EnableDebugLog) {
      Print(StringFormat("ATRチェック: 現在=%s (price units) / %s MT4pt (%s pips), 閾値=%s (price units) / %s MT4pt (%s pips)",
                         DoubleToString(current_atr, Digits),
                         DoubleToString(atr_mt4pt, 0),
                         DoubleToString(atr_pips, 2),
                         DoubleToString(thr_price, Digits),
                         DoubleToString(thr_mt4pt, 0),
                         DoubleToString(g_ATR_Threshold_Pips, 1)));
   }
   if (atr_pips < g_ATR_Threshold_Pips) {
      LogSkipReason("ATR不足: "
                    + DoubleToString(current_atr, Digits) + " (price) / " + DoubleToString(atr_mt4pt, 0) + " MT4pt (" + DoubleToString(atr_pips, 2) + " pips) < "
                    + DoubleToString(thr_price, Digits) + " (price) / " + DoubleToString(thr_mt4pt, 0) + " MT4pt (" + DoubleToString(g_ATR_Threshold_Pips, 1) + " pips)");
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
      double channel_width = (highest - lowest) / pip;
      
      if (EnableDebugLog) {
         Print("チャネル幅チェック: 現在=", DoubleToString(channel_width, 2), " pips, 最低値=", g_Min_Channel_Width_Pips, " pips (過去", Channel_Width_Period, "本)");
      }
      
      if (channel_width < g_Min_Channel_Width_Pips) {
         LogSkipReason("チャネル幅不足（狭いチャネル）: " + DoubleToString(channel_width, 1) + " pips < " + DoubleToString(g_Min_Channel_Width_Pips, 1) + " pips");
         return;
      }
      
      if (EnableDebugLog) {
         Print("チャネル幅合格: ", DoubleToString(channel_width, 2), " pips >= ", g_Min_Channel_Width_Pips, " pips → 十分な値幅");
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
   int layer_count = 0;
   string detected_layers = "";
   int signal_type = 0;
   bool pullback_found = false;
   
   // レイヤー1: EMAプルバック
   bool ema_layer_detected = false;
   if (g_ML_Require_EMA || (!g_ML_Require_Trendline && !g_ML_Require_RoundNumber)) {
      ema_layer_detected = DetectPullback(is_long);
      if (ema_layer_detected) {
         layer_count++;
         detected_layers += "[EMA]";
         if (EnableDebugLog) Print("  レイヤー1: EMAプルバック検出");
      }
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
   double bar_size_pips = (bar_high - bar_low) / pip;
   
   if (EnableDebugLog) {
      Print("確認足チェック: サイズ=", DoubleToString(bar_size_pips, 1), " pips, 最小=", g_Confirmation_Bar_Min_Size, " pips, 最大=", g_Confirmation_Bar_Max_Size, " pips");
   }
   
   if (bar_size_pips < g_Confirmation_Bar_Min_Size) {
      if (EnableDebugLog) {
         Print("確認足サイズ不足: ", DoubleToString(bar_size_pips, 1), " pips < ", g_Confirmation_Bar_Min_Size, " pips");
      }
      pullback_detected = false;
      confirmation_bar_validated = false;
      return;
   }
   
   if (g_Confirmation_Bar_Max_Size > 0 && bar_size_pips > g_Confirmation_Bar_Max_Size) {
      if (EnableDebugLog) {
         Print("確認足サイズ過大: ", DoubleToString(bar_size_pips, 1), " pips > ", g_Confirmation_Bar_Max_Size, " pips");
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
      Print(">>> 確認足OK: サイズ=", DoubleToString(bar_size_pips, 1), " pips, エントリーレベル=", DoubleToString(pullback_entry_level, Digits));
   }
}

//+------------------------------------------------------------------+
//| 価格ブレイクエントリーチェック（毎Tick）                          |
//+------------------------------------------------------------------+
void CheckPriceBreakEntry()
{
   if (!pullback_detected) return;
   
   double buffer = Entry_Buffer_Pips * pip;
   
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
//| ラウンドナンバー付近チェック                                       |
//| 戻り値: true=付近にいる（エントリー回避すべき）                    |
//|        false=付近にいない（エントリーOK）                         |
//+------------------------------------------------------------------+
bool IsNearRoundNumber(double price)
{
   if (!g_RN_Avoid_Entry_Near) return false;  // 機能無効時はOK
   
   double buffer = g_RN_Avoid_Buffer_Pips * pip;
   
   // .00ラインチェック
   if (g_RN_Use_00_Line) {
      double rn_00 = GetNearestRoundNumber(price, true);
      if (MathAbs(price - rn_00) <= buffer) {
         if (EnableDebugLog) {
            Print(">>> .00付近検出: 価格=", DoubleToString(price, Digits), 
                  " RN=", DoubleToString(rn_00, Digits),
                  " 距離=", DoubleToString(MathAbs(price - rn_00) / pip, 1), "pips");
         }
         return true;  // 付近にいる
      }
   }
   
   // .50ラインチェック
   if (g_RN_Use_50_Line) {
      double rn_50 = GetNearestRoundNumber(price, false);
      if (MathAbs(price - rn_50) <= buffer) {
         if (EnableDebugLog) {
            Print(">>> .50付近検出: 価格=", DoubleToString(price, Digits), 
                  " RN=", DoubleToString(rn_50, Digits),
                  " 距離=", DoubleToString(MathAbs(price - rn_50) / pip, 1), "pips");
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
         Print(">>> エントリースキップ: .00/.50付近（プルバックタッチなし）");
      }
      LogSkipReason("RN_NEAR_AVOID: ラウンドナンバー付近でエントリー回避");
      return;  // エントリーせずに終了
   }
   
   if (roundnumber_entry_detected && EnableDebugLog) {
      Print(">>> ラウンドナンバー付近だがプルバックタッチ検出済み → エントリー続行");
   }
   
   // Market Sentinelによるロットサイズ調整（EnableLotAdjustmentがtrueの場合のみ）
   // サービス削除済み - 調整なし
   double adjusted_lot = LotSize;
   
   // TradeOptimizerによるロットサイズ調整（オプトイン時のみ、EnableLotAdjustmentがtrueの場合のみ）
   // サービス削除済み - 調整なし
   
   if (is_long) {
      // entry_price = Ask; // 既に上で設定済み
      direction = "ロング";
      
      // SL/TP計算
      if (SLTP_Mode == SLTP_FIXED) {
         sl_price = entry_price - (g_StopLoss_Pips * pip);
         tp_price = entry_price + (g_TakeProfit_Pips * pip);
      } else {
         sl_price = entry_price - (current_atr * StopLoss_ATR_Multi);
         tp_price = entry_price + (current_atr * TakeProfit_ATR_Multi);
      }
   } else {
      // entry_price = Bid; // 既に上で設定済み
      direction = "ショート";
      
      // SL/TP計算
      if (SLTP_Mode == SLTP_FIXED) {
         sl_price = entry_price + (g_StopLoss_Pips * pip);
         tp_price = entry_price - (g_TakeProfit_Pips * pip);
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
      Print("ロットサイズ: ", adjusted_lot, (adjusted_lot != LotSize ? " (リスク調整済)" : ""));
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
      if (OrderSelect(current_ticket, SELECT_BY_TICKET, MODE_HISTORY)) {
         string direction = (OrderType() == OP_BUY) ? "BUY" : "SELL";
         double profit = OrderProfit() + OrderSwap() + OrderCommission();
         string close_time = TimeToString(OrderCloseTime(), TIME_DATE | TIME_MINUTES);
         LogTrade("EXIT", direction, "", current_ticket, OrderClosePrice(), OrderStopLoss(), OrderTakeProfit(), "closed", profit, close_time);
      }
      current_ticket = -1;
      return;
   }
   
   if (OrderCloseTime() != 0) {
      // クローズ済み
      string direction = (OrderType() == OP_BUY) ? "BUY" : "SELL";
      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      string close_time = TimeToString(OrderCloseTime(), TIME_DATE | TIME_MINUTES);
      LogTrade("EXIT", direction, "", current_ticket, OrderClosePrice(), OrderStopLoss(), OrderTakeProfit(), "closed", profit, close_time);
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
   double profit_pips = 0;
   
   if (OrderType() == OP_BUY) {
      profit_pips = (current_price - entry_price) / pip;
   } else {
      profit_pips = (entry_price - current_price) / pip;
   }
   
   // 第1利確
   if (!partial1_executed && profit_pips >= g_PartialCloseLevel1_Pips) {
      ExecutePartialClose(1, g_PartialClosePercent1);
   }
   
   // 第2利確
   if (g_PartialCloseLevels >= 2 && !partial2_executed && profit_pips >= g_PartialCloseLevel2_Pips) {
      ExecutePartialClose(2, g_PartialClosePercent2);
   }
   
   // 第3利確
   if (g_PartialCloseLevels >= 3 && !partial3_executed && profit_pips >= g_PartialCloseLevel3_Pips) {
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
void MoveStopLossToBreakeven()
{
   if (!OrderSelect(current_ticket, SELECT_BY_TICKET)) return;
   
   double entry_price = OrderOpenPrice();
   int order_type = OrderType();
   
   double new_sl = entry_price + (g_BreakevenOffset_Pips * pip);
   if (order_type == OP_SELL) {
      new_sl = entry_price - (g_BreakevenOffset_Pips * pip);
   }
   new_sl = NormalizeDouble(new_sl, Digits);
   
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
         Print(">>> SLを建値へ移動: ", DoubleToString(new_sl, Digits));
      } else {
         Print("!!! SL移動失敗: Error=", GetLastError());
      }
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
   double tp1_price = entry_price + (g_PartialCloseLevel1_Pips * pip);
   if (order_type == OP_SELL) {
      tp1_price = entry_price - (g_PartialCloseLevel1_Pips * pip);
   }
   tp1_price = NormalizeDouble(tp1_price, Digits);

   double current_sl = OrderStopLoss();
   bool should_modify = false;
   if (order_type == OP_BUY) {
      // ロング: SL未設定 or TP1より低い場合のみ引き上げ
      if (current_sl == 0 || current_sl < tp1_price) {
         should_modify = true;
      }
   } else if (order_type == OP_SELL) {
      // ショート: SL未設定 or TP1より高い場合のみ引き下げ
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
      } else {
         Print("!!! SL移動失敗: Error=", GetLastError());
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
   if (g_Trailing_Mode == TRAILING_FIXED_PIPS) {
      trailing_distance = g_TrailingStop_Fixed_Pips * pip;
   } else {
      double trailing_atr = iATR(Symbol(), 0, Trailing_ATR_Period, 1);
      trailing_distance = trailing_atr * g_TrailingStop_ATR_Multi;
   }
   
   double step = g_TrailingUpdate_Step_Pips * pip;
   
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
   // MQL4には直接フォルダ作成機能がないため、ダミーファイルで作成
   string dummy_file = folder_path + "\\.dummy";
   int handle = FileOpen(dummy_file, FILE_WRITE | FILE_TXT);
   if (handle != INVALID_HANDLE) {
      FileWrite(handle, "Folder created by EA");
      FileClose(handle);
      FileDelete(dummy_file);  // ダミーファイル削除
      Print("📁 フォルダ作成: ", folder_path);
   }
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
   
   // トレードログファイル名（MT4_ID + 通貨ペア + 時間軸）
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
                "Ticket", "Price", "SL", "TP", "Details", "Profit", "CloseDateTime");
   }
   
   FileClose(file_handle);
   Print("✅ トレードログ初期化完了: ", csv_file_path);
}

//+------------------------------------------------------------------+
//| 強トレンドモード自動判定（ボラティリティ急増検知）                      |
//+------------------------------------------------------------------+
bool ShouldActivateStrongTrendMode()
{
   if (!g_Auto_Strong_Trend_Mode) return g_Use_Strong_Trend_Mode;  // 手動設定を返す
   
   // 1. ATRスパイク検知
   double current_atr_value = iATR(Symbol(), 0, 14, 1) / pip;
   double baseline_atr = 0;
   for (int i = 2; i <= g_Auto_Detection_Period + 1; i++) {
      baseline_atr += iATR(Symbol(), 0, 14, i) / pip;
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
//| トレードログ記録                                                  |
//+------------------------------------------------------------------+
void LogTrade(string event, string direction, string pullback, int ticket,
              double price, double sl, double tp, string details = "",
              double profit = 0.0, string close_time = "")
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
             details,
             DoubleToString(profit, 2),
             close_time);
   
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
//| ヘルパー関数: スリッページ(points)換算                           |
//+------------------------------------------------------------------+
int EffectiveSlippagePoints()
{
   if (Point <= 0.0) return 0;
   if (Max_Slippage_Points > 0) return Max_Slippage_Points;
   // 互換性維持: 既定では「入力値をそのままpoints扱い」（従来挙動）
   if (!Use_Slippage_Pips_Conversion) {
      int legacy_points = Max_Slippage_Pips;
      if (legacy_points < 0) legacy_points = 0;
      return legacy_points;
   }

   // 推奨: pips入力をMT4 API用pointsへ換算
   if (pip <= 0.0) {
      int fallback = Max_Slippage_Pips;
      if (fallback < 0) fallback = 0;
      return fallback;
   }
   int points = (int)MathRound(Max_Slippage_Pips * pip / Point);
   if (points < 0) points = 0;
   return points;
}

//+------------------------------------------------------------------+
//| 戦略プリセット適用                                                |
//+------------------------------------------------------------------+
void ApplyStrategyPreset()
{
   // デフォルト値をinputパラメータから読み込み
   g_StopLoss_Pips = StopLoss_Fixed_Pips;
   g_TakeProfit_Pips = TakeProfit_Fixed_Pips;
   g_EnablePartialClose = EnablePartialClose;
   g_PartialCloseLevels = PartialCloseLevels;
   g_PartialClosePercent1 = PartialClosePercent1;
   g_PartialCloseLevel1_Pips = PartialCloseLevel1_Pips;
   g_PartialClosePercent2 = PartialClosePercent2;
   g_PartialCloseLevel2_Pips = PartialCloseLevel2_Pips;
   g_PartialClosePercent3 = PartialClosePercent3;
   g_PartialCloseLevel3_Pips = PartialCloseLevel3_Pips;
   g_MoveToBreakevenOnPartial1 = MoveToBreakevenOnPartial1;
   g_BreakevenOffset_Pips = BreakevenOffset_Pips;
   g_EnableTrailingAfterTP2 = EnableTrailingAfterTP2;
   g_Trailing_Mode = Trailing_Mode;
   g_TrailingStop_Fixed_Pips = TrailingStop_Fixed_Pips;
   g_TrailingStop_ATR_Multi = TrailingStop_ATR_Multi;
   g_TrailingUpdate_Step_Pips = TrailingUpdate_Step_Pips;
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
   
   // トレンドライン/チャネル設定
   g_TL_Channel_Mode = TL_Channel_Mode;
   g_TL_Upper_Name = TL_Upper_Name;
   g_TL_Lower_Name = TL_Lower_Name;
   g_TL_Touch_Buffer_Pips = TL_Touch_Buffer_Pips;
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
   g_RN_Touch_Buffer_Pips = RN_Touch_Buffer_Pips;
   g_RN_Use_Touch = RN_Use_Touch;
   g_RN_Use_Cross = RN_Use_Cross;
   g_RN_Use_Break = RN_Use_Break;
   g_RN_Lookback_Bars = RN_Lookback_Bars;
   g_RN_Counter_Trend = RN_Counter_Trend;
   g_RN_Digit_Level = RN_Digit_Level;
   
   // ラウンドナンバー付近回避設定
   g_RN_Avoid_Entry_Near = RN_Avoid_Entry_Near;
   g_RN_Avoid_Buffer_Pips = RN_Avoid_Buffer_Pips;
   
   // マルチレイヤー設定
   g_ML_Require_EMA = ML_Require_EMA;
   g_ML_Require_Trendline = ML_Require_Trendline;
   g_ML_Require_RoundNumber = ML_Require_RoundNumber;
   g_ML_Min_Layers = ML_Min_Layers;
   g_ML_Bonus_Multi_Layer = ML_Bonus_Multi_Layer;

   // 環境フィルター設定（プリセットで上書き可能）
   g_Use_ADX_Filter = Use_ADX_Filter;
   g_ADX_Min_Level = ADX_Min_Level;
   g_Use_Channel_Width_Filter = Use_Channel_Width_Filter;
   g_Min_Channel_Width_Pips = Min_Channel_Width_Pips;
   g_ATR_Threshold_Pips = ATR_Threshold_Pips;
   
   // AI対応設定（デフォルト値）
   g_Use_Micro_Volatility_Filter = Use_Micro_Volatility_Filter;
   g_Min_Bar_Range_Pips = Min_Bar_Range_Pips;
   g_Noise_Detection_Period = Noise_Detection_Period;
   g_Noise_Ratio_Threshold = Noise_Ratio_Threshold;
   g_Use_Algo_Price_Levels = Use_Algo_Price_Levels;
   g_Algo_Price_Clustering = Algo_Price_Clustering;
   g_Use_Quarter_Levels = Use_Quarter_Levels;
   g_Use_OrderFlow_Detection = Use_OrderFlow_Detection;
   g_OrderFlow_Volume_Multi = OrderFlow_Volume_Multi;
   g_OrderFlow_Avg_Period = OrderFlow_Avg_Period;
   g_Use_Algo_TimeFilter = Use_Algo_TimeFilter;
   g_Algo_Active_Start_Hour = Algo_Active_Start_Hour;
   g_Algo_Active_End_Hour = Algo_Active_End_Hour;
   g_Enable_AI_Learning_Log = Enable_AI_Learning_Log;
   
   // AI学習ログファイル名の構築（MT4_ID + 通貨ペア + 時間軸）
      string mt4_id_eff = MT4_ID;
      string mt4_id_eff_l = StringToLower(mt4_id_eff);
      if(StringFind(mt4_id_eff_l, "demo") < 0 && StringFind(mt4_id_eff_l, "live") < 0)
      {
         mt4_id_eff = mt4_id_eff + "-" + (IsDemo() ? "DEMO" : "LIVE");
      }

   string symbol_name = Symbol();
   string timeframe = GetTimeframeString(Period());
      g_AI_Learning_LogFile = "AI_Learning_Data_" + mt4_id_eff + "_" + symbol_name + "_" + timeframe + ".csv";
   g_AI_Learning_Folder = CsvLogFolder + "\\AI_Learning";
   g_Trade_History_Folder = CsvLogFolder + "\\Trade_History";
   
   switch (Selected_Strategy) {
      case STRATEGY_STANDARD:
         // 標準型（RELAXEDベース、バランス重視、M15推奨）
         g_StopLoss_Pips = 18.0;
         g_TakeProfit_Pips = 45.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 20.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 45.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.5;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_PIPS;
         g_TrailingStop_Fixed_Pips = 12.0;
         g_TrailingUpdate_Step_Pips = 3.0;
         // 環境フィルター（バランス型）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 20.0;  // 最低限のトレンド
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 20.0;  // 最低限の値幅
         g_ATR_Threshold_Pips = 7.0;  // 最低限のボラティリティ（実運用最適値）
         // EMA設定（標準）
         g_Entry_Confirmations = 1;  // 補助条件1個
         g_Min_Candle_Body_Percent = 55.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;  // パーフェクトオーダー不要
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: 標準型（M15推奨）");
         Print("SL: 18 pips / TP: 45 pips");
         Print("ADX >= 20.0、チャネル >= 20 pips、" + FormatAtrMinPriceAndMt4pt_FromPips(7.0));
         Print("→ バランス重視、初心者推奨");
         Print("★ AI機能: inputパラメータでON/OFF可能");
         if (g_Use_Micro_Volatility_Filter) Print("  - HFTノイズ除外: ON");
         if (g_Use_Algo_Price_Levels) Print("  - アルゴ価格レベル: ON");
         if (g_Use_OrderFlow_Detection) Print("  - オーダーフロー検出: ON");
         Print("========================================");
         break;
         
      case STRATEGY_CONSERVATIVE:
         // 保守型（厳格フィルター、質重視、M30推奨）
         g_StopLoss_Pips = 22.0;
         g_TakeProfit_Pips = 55.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 25.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 55.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 3.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_PIPS;
         g_TrailingStop_Fixed_Pips = 15.0;
         g_TrailingUpdate_Step_Pips = 4.0;
         // 環境フィルター（厳格）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 25.0;  // 強めのトレンド
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 30.0;  // 広めの値幅
         g_ATR_Threshold_Pips = 15.0;  // 十分なボラティリティ
         // EMA設定（厳格）
         g_Entry_Confirmations = 2;  // 補助条件2個必須
         g_Min_Candle_Body_Percent = 60.0;
         g_Use_MTF_Filter1 = true;
         g_MTF_Timeframe1 = PERIOD_H1;  // 上位足確認
         g_MTF_Require_Perfect_Order1 = true;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;  // パーフェクトオーダー必須
         g_Use_Immediate_Entry = false;
         g_Use_Confirmation_Bar = true;
         g_Confirmation_Bar_Min_Size = 8.0;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = false;
         g_Use_Break_Pullback = false;
         Print("========================================");
         Print("戦略: 保守型（M30推奨）");
         Print("SL: 22 pips / TP: 55 pips");
         Print("ADX >= 25.0、チャネル >= 30 pips、" + FormatAtrMinPriceAndMt4pt_FromPips(15.0));
         Print("→ 質重視、勝率優先");
         Print("★ AI機能: inputパラメータでON/OFF可能");
         if (g_Use_Micro_Volatility_Filter) Print("  - HFTノイズ除外: ON");
         if (g_Use_Algo_Price_Levels) Print("  - アルゴ価格レベル: ON");
         if (g_Use_OrderFlow_Detection) Print("  - オーダーフロー検出: ON");
         Print("========================================");
         break;
         
      case STRATEGY_AGGRESSIVE:
         // 積極型（フィルター最小、量重視、M5推奨）
         g_StopLoss_Pips = 15.0;
         g_TakeProfit_Pips = 35.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 15.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 35.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_PIPS;
         g_TrailingStop_Fixed_Pips = 10.0;
         g_TrailingUpdate_Step_Pips = 2.5;
         // 環境フィルター（最小）
         g_Use_ADX_Filter = false;  // ADXフィルターなし
         g_ADX_Min_Level = 0.0;
         g_Use_Channel_Width_Filter = false;  // チャネル幅フィルターなし
         g_Min_Channel_Width_Pips = 0.0;
         g_ATR_Threshold_Pips = 5.0;  // 最小限のATRのみ
         // EMA設定（緩和）
         g_Entry_Confirmations = 0;  // 補助条件不要
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;  // パーフェクトオーダー不要
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Use_Touch_Pullback = true;
         g_Use_Cross_Pullback = true;
         g_Use_Break_Pullback = true;  // ブレイクも許可
         Print("========================================");
         Print("戦略: 積極型（M5推奨）");
         Print("SL: 15 pips / TP: 35 pips");
         Print("環境フィルター最小（" + FormatAtrMinPriceAndMt4pt_FromPips(5.0) + " のみ）");
         Print("→ 取引回数最大化、量重視");
         Print("★ AI機能: inputパラメータでON/OFF可能");
         if (g_Use_Micro_Volatility_Filter) Print("  - HFTノイズ除外: ON");
         if (g_Use_Algo_Price_Levels) Print("  - アルゴ価格レベル: ON");
         if (g_Use_OrderFlow_Detection) Print("  - オーダーフロー検出: ON");
         Print("========================================");
         break;
         
      case STRATEGY_AI_ADAPTIVE:
         // AI適応型（HFTノイズ除外+アルゴレベル検出、M5推奨）
         g_StopLoss_Pips = 12.0;
         g_TakeProfit_Pips = 30.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 60.0;  // 早めに60%確保
         g_PartialCloseLevel1_Pips = 12.0;
         g_PartialClosePercent2 = 40.0;
         g_PartialCloseLevel2_Pips = 30.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 1.5;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_PIPS;
         g_TrailingStop_Fixed_Pips = 8.0;
         g_TrailingUpdate_Step_Pips = 2.0;
         // AI対応フィルター
         g_Use_Micro_Volatility_Filter = true;
         g_Min_Bar_Range_Pips = 3.0;
         g_Noise_Detection_Period = 10;
         g_Noise_Ratio_Threshold = 0.6;
         g_Use_Algo_Price_Levels = true;
         g_Algo_Price_Clustering = 5.0;
         g_Use_Quarter_Levels = true;
         g_Use_OrderFlow_Detection = true;
         g_OrderFlow_Volume_Multi = 2.0;
         g_OrderFlow_Avg_Period = 9;
         g_Use_Algo_TimeFilter = false;  // 全時間帯対応
         // 環境フィルター（中程度）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 22.0;
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 25.0;
         g_ATR_Threshold_Pips = 10.0;
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
         Print("SL: 12 pips / TP: 30 pips");
         Print("★ HFTノイズ除外 + アルゴ価格レベル検出");
         Print("★ オーダーフロー分析 + 0.25刻みレベル");
         Print("→ AI時代対応、GPU不要の軽量アルゴリズム");
         Print("========================================");
         break;
         
      case STRATEGY_AI_SCOUT:
         // AIスカウト型（データ収集+パターン学習）
         g_StopLoss_Pips = 15.0;
         g_TakeProfit_Pips = 35.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 15.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 35.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_PIPS;
         g_TrailingStop_Fixed_Pips = 10.0;
         g_TrailingUpdate_Step_Pips = 2.5;
         // AI学習モード（全フィルター有効）
         g_Use_Micro_Volatility_Filter = true;
         g_Min_Bar_Range_Pips = 2.5;
         g_Noise_Detection_Period = 15;
         g_Noise_Ratio_Threshold = 0.5;
         g_Use_Algo_Price_Levels = true;
         g_Algo_Price_Clustering = 7.0;
         g_Use_Quarter_Levels = true;
         g_Use_OrderFlow_Detection = true;
         g_OrderFlow_Volume_Multi = 1.8;
         g_OrderFlow_Avg_Period = 12;
         g_Use_Algo_TimeFilter = false;
         g_Enable_AI_Learning_Log = true;  // 学習データ収集ON
         // 環境フィルター（緩和）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 18.0;
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 15.0;
         g_ATR_Threshold_Pips = 8.0;
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
         Print("SL: 15 pips / TP: 35 pips");
         Print("★ DLL推論EA用データ収集モード");
         Print("★ 全パターン記録 + 統計分析");
         Print("→ 学習データをCSV出力（" + g_AI_Learning_LogFile + "）");
         Print("========================================");
         break;
         
      /*
      case STRATEGY_BALANCED:
         // 提案2: バランス型（段階利確）
         g_StopLoss_Pips = 15.0;
         g_TakeProfit_Pips = 50.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 15.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 50.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.0;
         g_EnableTrailingAfterTP2 = true;
         g_TrailingStop_Fixed_Pips = 12.0;
         g_Entry_Confirmations = 2;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         Print("========================================");
         Print("戦略: バランス型（段階利確）");
         Print("SL: 15 pips / TP: 50 pips");
         Print("段階利確: 15pips@50% → 50pips@50%");
         Print("トレーリング有効");
         Print("========================================");
         break;
         
      case STRATEGY_HIGH_ACCURACY:
         // 提案4: 高精度型（厳格化）
         g_StopLoss_Pips = 20.0;
         g_TakeProfit_Pips = 60.0;
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
         Print("SL: 20 pips / TP: 60 pips (1:3)");
         Print("補助条件: 3つ必須");
         Print("MTFフィルター: H1 + H4");
         Print("実体比率: 60%以上");
         Print("========================================");
         break;
         
      case STRATEGY_SCALPING:
         // 提案5: スキャルピング型
         g_StopLoss_Pips = 8.0;
         g_TakeProfit_Pips = 12.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 70.0;
         g_PartialCloseLevel1_Pips = 8.0;
         g_PartialClosePercent2 = 30.0;
         g_PartialCloseLevel2_Pips = 20.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.0;
         g_Entry_Confirmations = 1;
         g_Use_Immediate_Entry = true;
         g_Use_Confirmation_Bar = false;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_EnableTrailingAfterTP2 = false;
         Print("========================================");
         Print("戦略: スキャルピング型");
         Print("SL: 8 pips / TP: 12 pips (1:1.5)");
         Print("段階利確: 8pips@70% → 20pips@30%");
         Print("補助条件: 1つのみ");
         Print("即座エントリー");
         Print("========================================");
         break;
         
      case STRATEGY_TREND_RIDER:
         // 提案6: トレンド継続型
         g_StopLoss_Pips = 15.0;
         g_TakeProfit_Pips = 45.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 30.0;
         g_PartialCloseLevel1_Pips = 20.0;
         g_PartialClosePercent2 = 40.0;
         g_PartialCloseLevel2_Pips = 40.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 1.5;
         g_TrailingUpdate_Step_Pips = 3.0;
         g_Use_Immediate_Entry = false;
         g_Use_Confirmation_Bar = true;
         g_Confirmation_Bar_Min_Size = 8.0;
         g_Min_Candle_Body_Percent = 65.0;
         g_Entry_Confirmations = 2;
         g_Use_Break_Pullback = true;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = true;
         Print("========================================");
         Print("戦略: トレンド継続型");
         Print("SL: 15 pips / TP: 45 pips (1:3)");
         Print("段階利確: 20pips@30% → 40pips@40% → 残り30%トレーリング");
         Print("トレーリング: ATR 1.5倍");
         Print("確認足必須、実体比率65%");
         Print("========================================");
         break;
         
      case STRATEGY_TREND_RIDER_V2:
         // トレンド継続型V2（改良版）- 取引機会を増やしつつ品質維持
         g_StopLoss_Pips = 18.0;
         g_TakeProfit_Pips = 54.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 25.0;
         g_PartialCloseLevel1_Pips = 25.0;
         g_PartialClosePercent2 = 35.0;
         g_PartialCloseLevel2_Pips = 45.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 3.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         g_TrailingUpdate_Step_Pips = 5.0;
         g_Use_Immediate_Entry = false;
         g_Use_Confirmation_Bar = true;
         g_Confirmation_Bar_Min_Size = 6.0;
         g_Confirmation_Bar_Max_Size = 30.0;
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
         Print("SL: 18 pips / TP: 54 pips (1:3)");
         Print("段階利確: 25pips@25% → 45pips@35% → 残り40%ATRトレーリング");
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
         g_StopLoss_Pips = 15.0;
         g_TakeProfit_Pips = 50.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 15.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 50.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;              // ATRトレーリングに変更
         g_TrailingStop_ATR_Multi = 2.0;              // ATR 2.0倍（バランス型は固定12pips）
         g_TrailingUpdate_Step_Pips = 5.0;            // 更新ステップ5pips
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
         Print("SL: 15 pips / TP: 50 pips");
         Print("段階利確: 15pips@50% → 50pips@50%");
         Print("トレーリング: ATR 2.0倍（大トレンドで利益最大化）");
         Print("補助条件: 2つ（バランス型と同じ）");
         Print("※ M30での運用を推奨");
         Print("========================================");
         break;
         
      case STRATEGY_HYBRID:
         // 提案7: ハイブリッド型（レンジ対応）
         g_StopLoss_Pips = 12.0;
         g_TakeProfit_Pips = 24.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 1;
         g_PartialClosePercent1 = 60.0;
         g_PartialCloseLevel1_Pips = 12.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 1.5;
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
         Print("SL: 12 pips / TP: 24 pips (1:2)");
         Print("段階利確: 12pips@60%");
         Print("パーフェクトオーダー不要");
         Print("失敗ブレイク重視");
         Print("========================================");
         break;
         
      case STRATEGY_TRENDLINE:
         // トレンドライン順張り戦略
         g_StopLoss_Pips = 18.0;
         g_TakeProfit_Pips = 45.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 18.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 45.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         g_TrailingUpdate_Step_Pips = 5.0;
         g_Entry_Confirmations = 1;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;  // トレンドラインが代替
         g_TL_Channel_Mode = MODE_TRENDLINE_TREND;
         g_TL_Use_Touch = true;
         g_TL_Use_Cross = true;
         g_TL_Use_Break = false;
         g_TL_Lookback_Bars = 3;
         g_PA_Require_Reversal = false;  // 順張りなので不要
         Print("========================================");
         Print("戦略: トレンドライン順張り");
         Print("手動トレンドラインに対するプルバックエントリー");
         Print("SL: 18 pips / TP: 45 pips");
         Print("段階利確: 18pips@50% → 45pips@50%");
         Print("ATRトレーリング有効");
         Print("※ チャートに手動でトレンドラインを引いてください");
         Print("  上昇トレンド: TL_Lower (サポート)");
         Print("  下降トレンド: TL_Upper (レジスタンス)");
         Print("========================================");
         break;
         
      case STRATEGY_CHANNEL_RANGE:
         // チャネルレンジ逆張り戦略
         g_StopLoss_Pips = 15.0;
         g_TakeProfit_Pips = 30.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 1;
         g_PartialClosePercent1 = 60.0;
         g_PartialCloseLevel1_Pips = 15.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_EnableTrailingAfterTP2 = false;
         g_Entry_Confirmations = 1;
         g_Min_Candle_Body_Percent = 40.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         g_Require_Perfect_Order = false;  // 逆張りなので不要
         g_TL_Channel_Mode = MODE_CHANNEL_RANGE;
         g_TL_Use_Touch = true;
         g_TL_Use_Cross = false;
         g_TL_Use_Break = false;
         g_TL_Lookback_Bars = 3;
         g_PA_Require_Reversal = true;   // 逆張りなので必須
         g_PA_Use_Pinbar = true;
         g_PA_Use_Engulfing = true;
         Print("========================================");
         Print("戦略: チャネルレンジ逆張り");
         Print("チャネル上限/下限での反転狙い");
         Print("SL: 15 pips / TP: 30 pips");
         Print("段階利確: 15pips@60%（早期利確）");
         Print("プライスアクション反転パターン必須");
         Print("※ チャートに手動でチャネルラインを引いてください");
         Print("  TL_Upper: チャネル上限");
         Print("  TL_Lower: チャネル下限");
         Print("========================================");
         break;
         
      case STRATEGY_MULTI_LAYER:
         // マルチレイヤー戦略（EMA + ラウンドナンバー）
         g_StopLoss_Pips = 15.0;
         g_TakeProfit_Pips = 40.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 15.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 40.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         // 環境フィルター（M15のボトルネック対策: ATR不足が多いため少し緩和）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 18.0;
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 20.0;
         g_ATR_Threshold_Pips = 5.0;
         // M15・多銘柄運用では固くし過ぎると機会損失が増えるため、補助条件は1つに緩和
         g_Entry_Confirmations = 1;
         g_Min_Candle_Body_Percent = 50.0;
         g_Use_MTF_Filter1 = false;
         g_Use_MTF_Filter2 = false;
         // 代わりに「EMA必須 + 2レイヤー一致」で質を担保し、PO必須は外して回数を確保
         g_Require_Perfect_Order = false;
         // ラウンドナンバー有効化
         g_Use_RoundNumber_Lines = true;
         g_RN_Use_00_Line = true;
         g_RN_Use_50_Line = true;
         // RNタッチ判定をやや緩めて、EMAプルバックと重なりやすくする
         g_RN_Touch_Buffer_Pips = 3.0;
         g_RN_Use_Touch = true;
         g_RN_Use_Cross = true;
         g_RN_Use_Break = false;
         g_RN_Lookback_Bars = 4;
         g_RN_Counter_Trend = false;  // 順張り
         g_RN_Digit_Level = 2;  // FX用（USDJPY: 150.00）
         // マルチレイヤー設定
         // 勝率を落とさず回数を増やすため、EMAレイヤーは必須に
         g_ML_Require_EMA = true;
         g_ML_Require_Trendline = false;
         g_ML_Require_RoundNumber = false;
         g_ML_Min_Layers = 2;  // EMAとRN両方必須
         g_ML_Bonus_Multi_Layer = true;
         Print("========================================");
         Print("戦略: マルチレイヤー（EMA + ラウンドナンバー）");
         Print("EMAプルバック + .00/.50ライン 重複狙い");
         Print("SL: 15 pips / TP: 40 pips");
         Print("段階利確: 15pips@50% → 40pips@50%");
         Print("最小レイヤー数: 2（EMA + RN）");
         Print("FX: .00/.50ライン、日経225: 1000/500ライン");
         Print("========================================");
         break;
         
      case STRATEGY_ENV_FILTER_STRICT:
         // 環境フィルター厳格型（強いトレンド+広いチャネルのみ）
         g_StopLoss_Pips = 12.0;
         g_TakeProfit_Pips = 36.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 18.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 36.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 1.5;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         // 環境フィルター（厳格）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 30.0;  // 強いトレンドのみ
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 40.0;  // 広いチャネルのみ
         g_ATR_Threshold_Pips = 15.0;  // 高ボラティリティ必須
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
         Print("SL: 12 pips / TP: 36 pips (1:3)");
         Print("ADX >= 30.0（強トレンド）");
         Print("チャネル幅 >= 40 pips（広い値幅）");
         Print(FormatAtrMinPriceAndMt4pt_FromPips(15.0) + "（高ボラティリティ）");
         Print("→ HFTノイズ・狭小レンジを完全除外");
         Print("========================================");
         break;
         
      case STRATEGY_ENV_FILTER_MODERATE:
         // 環境フィルター標準型（今回のデフォルト設定）
         g_StopLoss_Pips = 15.0;
         g_TakeProfit_Pips = 40.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 15.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 40.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         // 環境フィルター（標準）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 25.0;  // 中程度のトレンド
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 30.0;  // デフォルト値
         g_ATR_Threshold_Pips = 12.0;  // 標準ボラティリティ
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
         Print("SL: 15 pips / TP: 40 pips");
         Print("ADX >= 25.0（標準トレンド）");
         Print("チャネル幅 >= 30 pips（標準値幅）");
         Print(FormatAtrMinPriceAndMt4pt_FromPips(12.0) + "（標準ボラティリティ）");
         Print("→ バランスの取れたフィルタリング");
         Print("========================================");
         break;
         
      case STRATEGY_ENV_FILTER_RELAXED:
         // 環境フィルター緩和型（エントリー機会確保）
         g_StopLoss_Pips = 18.0;
         g_TakeProfit_Pips = 45.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 20.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 45.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.5;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_PIPS;
         g_TrailingStop_Fixed_Pips = 12.0;
         g_TrailingUpdate_Step_Pips = 3.0;
         // 環境フィルター（緩和）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 20.0;  // 弱いトレンドでもOK
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 20.0;  // 狭めでもOK
         g_ATR_Threshold_Pips = 10.0;  // 低ボラティリティでもOK
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
         Print("SL: 18 pips / TP: 45 pips");
         Print("ADX >= 20.0（緩いトレンド）");
         Print("チャネル幅 >= 20 pips（狭めでもOK）");
         Print(FormatAtrMinPriceAndMt4pt_FromPips(10.0) + "（低ボラでもOK）");
         Print("→ エントリー機会を確保しつつフィルタリング");
         Print("========================================");
         break;
         
      case STRATEGY_ENV_FILTER_OPTIMIZED:
         // 環境フィルター最適化型（RELAXED改良版）
         g_StopLoss_Pips = 18.0;
         g_TakeProfit_Pips = 45.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 20.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 45.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.5;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_FIXED_PIPS;
         g_TrailingStop_Fixed_Pips = 12.0;
         g_TrailingUpdate_Step_Pips = 3.0;
         // 環境フィルター（最適化）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 18.0;  // RELAXEDより緩め
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 15.0;  // RELAXEDより緩め
         g_ATR_Threshold_Pips = 8.0;  // RELAXEDより緩め
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
         Print("SL: 18 pips / TP: 45 pips");
         Print("ADX >= 18.0（RELAXEDより緩め）");
         Print("チャネル幅 >= 15 pips（RELAXEDより緩め）");
         Print(FormatAtrMinPriceAndMt4pt_FromPips(8.0) + "（RELAXEDより緩め）");
         Print("→ 取引回数300~400回を目指しPF維持");
         Print("========================================");
         break;
         
      case STRATEGY_V3_FILTERED:
         // V3+環境フィルター（最強版）
         // V3の設定をベースにRELAXEDフィルターを追加
         g_StopLoss_Pips = 20.0;
         g_TakeProfit_Pips = 50.0;
         g_EnablePartialClose = true;
         g_PartialCloseLevels = 2;
         g_PartialClosePercent1 = 50.0;
         g_PartialCloseLevel1_Pips = 25.0;
         g_PartialClosePercent2 = 50.0;
         g_PartialCloseLevel2_Pips = 50.0;
         g_MoveToBreakevenOnPartial1 = true;
         g_BreakevenOffset_Pips = 2.0;
         g_EnableTrailingAfterTP2 = true;
         g_Trailing_Mode = TRAILING_ATR;
         g_TrailingStop_ATR_Multi = 2.0;
         // 環境フィルター（RELAXEDレベル）
         g_Use_ADX_Filter = true;
         g_ADX_Min_Level = 20.0;  // 最低限のトレンド
         g_Use_Channel_Width_Filter = true;
         g_Min_Channel_Width_Pips = 20.0;  // 最低限の値幅
         g_ATR_Threshold_Pips = 10.0;  // 最低限のボラ
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
         Print("SL: 20 pips / TP: 50 pips (1:2.5)");
         Print("V3設定: パーフェクトオーダー+補助条件2個");
         Print("環境フィルター: ADX>=20, チャネル>=20pips, " + FormatAtrMinPriceAndMt4pt_FromPips(10.0));
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
   
   double buffer = g_TL_Touch_Buffer_Pips * pip;
   
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
   
   double buffer = g_TL_Touch_Buffer_Pips * pip;
   
   // 過去N本で逆張りシグナル検出
   for (int i = 1; i <= g_TL_Lookback_Bars; i++) {
      double bar_high = iHigh(Symbol(), 0, i);
      double bar_low = iLow(Symbol(), 0, i);
      
      double upper_price = GetTrendlinePrice(g_TL_Upper_Name, i);
      double lower_price = GetTrendlinePrice(g_TL_Lower_Name, i);
      
      if (upper_price == 0.0 || lower_price == 0.0) continue;
      
      // チャネル幅検証
      double channel_width = upper_price - lower_price;
      if (channel_width < 10 * pip) continue;
      
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
//| 最も近いラウンドナンバーライン取得                                 |
//+------------------------------------------------------------------+
double GetNearestRoundNumber(double price, bool is_00_line)
{
   double increment = is_00_line ? 1.0 : 0.5;
   
   // 桁数レベルに応じた調整（例: USDJPY 150.00 or 日経 39000.00）
   if (g_RN_Digit_Level == 3) {
      increment = is_00_line ? 1.0 : 0.5;  // FX: 150.000, 150.500
   } else if (g_RN_Digit_Level == 2) {
      increment = is_00_line ? 1.0 : 0.5;  // FX: 150.00, 150.50
   } else if (g_RN_Digit_Level == 0) {
      // 日経225など整数価格（39000, 39500）
      increment = is_00_line ? 1000.0 : 500.0;
   }
   
   // 現在価格を基準に最も近いラウンドナンバー計算
   double rounded = MathFloor(price / increment) * increment;
   double upper = rounded + increment;
   
   // 近い方を返す
   if (MathAbs(price - rounded) < MathAbs(price - upper)) {
      return rounded;
   } else {
      return upper;
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
   
   double buffer = g_RN_Touch_Buffer_Pips * pip;
   
   // 過去N本でラウンドナンバープルバック検出
   for (int i = 1; i <= g_RN_Lookback_Bars; i++) {
      double bar_high = iHigh(Symbol(), 0, i);
      double bar_low = iLow(Symbol(), 0, i);
      double bar_close = iClose(Symbol(), 0, i);
      
      // .00ラインチェック
      if (g_RN_Use_00_Line) {
         double rn_00 = GetNearestRoundNumber(bar_low, true);
         
         // 順張りモード: トレンド方向のプルバック＋反発確認必須
         if (!g_RN_Counter_Trend) {
            // ロング: .00ラインタッチ後の反発（反発確認必須）
            if (is_long && g_RN_Use_Touch && 
                bar_low <= (rn_00 + buffer) && bar_low >= (rn_00 - buffer)) {
               // ★反発確認: 陽線で終わっているか、または現在価格がタッチポイントより上
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
               // ★反落確認: 陰線で終わっているか、または現在価格がタッチポイントより下
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
      
      // .50ラインチェック（同様のロジック）
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


