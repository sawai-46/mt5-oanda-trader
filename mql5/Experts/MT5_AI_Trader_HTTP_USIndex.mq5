//+------------------------------------------------------------------+
//|                                MT5_AI_Trader_HTTP_USIndex.mq5    |
//|            US Index用パラメータプリセット (US30/SPX500/NAS100)   |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "1.00"
#property strict

//--- HTTP設定
input string InpMT5_ID = "OANDA-USIndex";             // MT5識別ID
input string InpInferenceServerURL = "http://localhost:5001";  // 推論サーバーURL
input int    InpServerTimeout = 30000;                          // タイムアウト(ms)

//--- 基本トレード設定 (USIndex用調整)
input double InpRiskPercent = 1.0;         // リスク率(%)
input double InpBaseLotSize = 0.10;        // 基本ロット
input int    InpMaxSlippagePoints = 100;   // 最大スリッページ(points) ★USIndex用
input int    InpMaxSpreadPoints = 500;     // 最大スプレッド(points) ★USIndex用
input double InpStopLossPoints = 500.0;    // SL(points) ★USIndex用
input double InpTakeProfitPoints = 1000.0; // TP(points) ★USIndex用
input ulong  InpMagicNumber = 30001;       // マジックナンバー ★USIndex用

//--- 時間フィルター設定 (米国市場メイン + 欧州オーバーラップ)
input bool   InpEnable_Time_Filter = true;         // 時間フィルター有効化
input int    InpGMT_Offset = 3;                    // GMTオフセット
input int    InpCustom_Start_Hour = 16;            // 稼働開始時(JST) ★16:00 (欧州開場)
input int    InpCustom_End_Hour = 6;               // 稼働終了時(JST) ★6:00 (米国閉場)
input bool   InpTradeOnFriday = true;              // 金曜取引許可

//--- フィルター設定
input int    InpMaxPositions = 2;          // 最大ポジション数
input int    InpMinBarsSinceLastTrade = 10; // 最小バー間隔
input double InpMinConfidence = 0.65;      // 最小信頼度

//--- ATR設定 (USIndex用)
input int    InpATRPeriod = 14;            // ATR期間
input double InpATRThresholdPoints = 50.0; // ATR最低閾値(points) ★USIndex用

//--- Partial Close設定 (USIndex用)
input bool   InpEnablePartialClose = true;     // 部分決済有効化
input double InpPartialClose1Points = 500.0;   // 1段階目(points) ★USIndex用
input double InpPartialClose1Percent = 50.0;   // 1段階目決済率(%)
input double InpPartialClose2Points = 1000.0;  // 2段階目(points) ★USIndex用
input bool   InpMoveToBreakEvenAfterLevel1 = true; // Level1後にSL移動(建値へ)

// ベースロジックをインクルード
#include "MT5_AI_Trader_HTTP.mq5"
