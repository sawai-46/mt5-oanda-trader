//+------------------------------------------------------------------+
//|                                        MT5_AI_Trader_HTTP.mq5    |
//|              Phase 6 HTTP API版 (MQL5 OANDA対応)                 |
//|   推論サーバーとHTTP経由で通信 + 16モジュールAI統合               |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property version   "1.00"
#property strict

//--- HTTP設定
input string InpMT5_ID = "OANDA-MT5";                 // MT5識別ID
input string InpInferenceServerURL = "http://localhost:5001";  // 推論サーバーURL
input int    InpServerTimeout = 30000;                          // タイムアウト(ms)

//--- 基本トレード設定
input double InpRiskPercent = 1.0;         // リスク率(%)
input double InpBaseLotSize = 0.10;        // 基本ロット
input int    InpMaxSlippagePoints = 50;    // 最大スリッページ(points)
input int    InpMaxSpreadPoints = 200;     // 最大スプレッド(points)
input double InpStopLossPoints = 150.0;    // SL(points)
input double InpTakeProfitPoints = 300.0;  // TP(points)
input ulong  InpMagicNumber = 20251224;    // マジックナンバー

//--- 時間フィルター設定
input bool   InpEnable_Time_Filter = true;         // 時間フィルター有効化
input int    InpGMT_Offset = 3;                    // GMTオフセット
input int    InpCustom_Start_Hour = 8;             // 稼働開始時(JST)
input int    InpCustom_End_Hour = 21;              // 稼働終了時(JST)
input bool   InpTradeOnFriday = true;              // 金曜取引許可

//--- フィルター設定
input int    InpMaxPositions = 2;          // 最大ポジション数
input int    InpMinBarsSinceLastTrade = 10; // 最小バー間隔
input double InpMinConfidence = 0.65;      // 最小信頼度

//--- ATR設定
input int    InpATRPeriod = 14;            // ATR期間
input double InpATRThresholdPoints = 30.0; // ATR最低閾値(points)

//--- Partial Close設定
input bool   InpEnablePartialClose = true;     // 部分決済有効化
input double InpPartialClose1Points = 150.0;   // 1段階目(points)
input double InpPartialClose1Percent = 50.0;   // 1段階目決済率(%)
input double InpPartialClose2Points = 300.0;   // 2段階目(points)
input bool   InpMoveToBreakEvenAfterLevel1 = true; // Level1後にSL移動(建値へ)

//--- グローバル変数
datetime g_lastBarTime = 0;
int g_lastTradeBar = 0;
CTrade m_trade;

// Partial Close状態管理
int g_partialCloseLevel[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Trade設定
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   m_trade.SetDeviationInPoints(InpMaxSlippagePoints);
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   Print("=== MT5 AI Trader v1.0 HTTP (OANDA) ===");
   Print("シグナル生成: Python推論サーバー (16モジュール)");
   Print("Inference Server: ", InpInferenceServerURL);
   Print("Symbol: ", _Symbol);
   
   // Partial Close配列初期化
   if(InpEnablePartialClose)
   {
      ArrayResize(g_partialCloseLevel, 100);
      ArrayInitialize(g_partialCloseLevel, 0);
   }
   
   // HTTP接続テスト
   if(!TestServerConnection())
   {
      Alert("推論サーバーへの接続に失敗しました: ", InpInferenceServerURL);
      Print("URLを'ツール > オプション > エキスパートアドバイザ > WebRequestを許可するURLリスト'に追加してください");
      return(INIT_FAILED);
   }
   
   Print("初期化完了");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("EA終了 - 理由: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 新しいバーでのみ実行
   datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentBarTime == g_lastBarTime)
      return;
   
   g_lastBarTime = currentBarTime;
   g_lastTradeBar++;
   
   // Partial Close チェック
   if(InpEnablePartialClose)
   {
      CheckPartialClose();
   }
   
   // メインロジック
   AnalyzeAndTrade();
}

//+------------------------------------------------------------------+
//| メイン分析・トレードロジック                                      |
//+------------------------------------------------------------------+
void AnalyzeAndTrade()
{
   // フィルターチェック
   if(!PassesTimeFilter())
      return;
   
   if(CountOpenPositions() >= InpMaxPositions)
      return;
   
   if(g_lastTradeBar < InpMinBarsSinceLastTrade)
      return;
   
   // スプレッドチェック
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
   {
      Print("スプレッドが広すぎます: ", spread, " points");
      return;
   }
   
   // OHLCV データ準備 (100本)
   string jsonData = PrepareOHLCVJson(100);
   
   // HTTP POSTリクエスト送信
   string responseStr = "";
   if(!SendHttpRequest(InpInferenceServerURL + "/analyze", jsonData, responseStr))
   {
      Print("推論サーバーとの通信に失敗しました");
      return;
   }
   
   // レスポンス解析
   int signal = 0;
   double confidence = 0.0;
   bool entryAllowed = false;
   
   if(!ParseAnalyzeResponse(responseStr, signal, confidence, entryAllowed))
   {
      Print("レスポンスの解析に失敗しました");
      return;
   }
   
   // エントリー判定
   if(!entryAllowed || signal == 0)
      return;
   
   if(confidence < InpMinConfidence)
      return;
   
   // ATR閾値チェック
   double atr = GetATR(InpATRPeriod);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double atr_points = atr / point;
   
   if(atr_points < InpATRThresholdPoints)
   {
      Print("ATR不足: ", DoubleToString(atr_points, 1), " points < ", InpATRThresholdPoints);
      return;
   }
   
   // エントリー実行
   ExecuteTrade(signal, confidence);
}

//+------------------------------------------------------------------+
//| トレード実行                                                     |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal, double confidence)
{
   bool is_long = (signal == 1);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry_price = is_long ? ask : bid;
   
   double sl, tp;
   CalculateSLTP(is_long, entry_price, sl, tp);
   
   double lotSize = CalculateLotSize();
   string comment = "AI_" + (is_long ? "BUY" : "SELL") + "_" + DoubleToString(confidence, 2);
   
   bool result = false;
   if(is_long)
   {
      result = m_trade.Buy(lotSize, _Symbol, ask, sl, tp, comment);
   }
   else
   {
      result = m_trade.Sell(lotSize, _Symbol, bid, sl, tp, comment);
   }
   
   if(result)
   {
      Print("★ ", (is_long ? "BUY" : "SELL"), "注文成功: Conf=", DoubleToString(confidence, 3),
            " SL=", DoubleToString(sl, _Digits), " TP=", DoubleToString(tp, _Digits));
      g_lastTradeBar = 0;
   }
   else
   {
      Print((is_long ? "BUY" : "SELL"), "注文失敗: Error=", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| OHLCV データをJSON形式で準備                                     |
//+------------------------------------------------------------------+
string PrepareOHLCVJson(int bars)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, bars, rates);
   
   if(copied <= 0)
   {
      Print("データの取得に失敗: ", GetLastError());
      return "";
   }
   
   string json = "{";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"timeframe\":\"" + PeriodToString(PERIOD_CURRENT) + "\",";
   json += "\"ohlcv\":{";
   
   // Open
   json += "\"open\":[";
   for(int i = 0; i < copied; i++)
   {
      json += DoubleToString(rates[i].open, _Digits);
      if(i < copied - 1) json += ",";
   }
   json += "],";
   
   // High
   json += "\"high\":[";
   for(int i = 0; i < copied; i++)
   {
      json += DoubleToString(rates[i].high, _Digits);
      if(i < copied - 1) json += ",";
   }
   json += "],";
   
   // Low
   json += "\"low\":[";
   for(int i = 0; i < copied; i++)
   {
      json += DoubleToString(rates[i].low, _Digits);
      if(i < copied - 1) json += ",";
   }
   json += "],";
   
   // Close
   json += "\"close\":[";
   for(int i = 0; i < copied; i++)
   {
      json += DoubleToString(rates[i].close, _Digits);
      if(i < copied - 1) json += ",";
   }
   json += "],";
   
   // Volume
   json += "\"volume\":[";
   for(int i = 0; i < copied; i++)
   {
      json += IntegerToString(rates[i].tick_volume);
      if(i < copied - 1) json += ",";
   }
   json += "]";
   
   json += "},";
   json += "\"current_price\":" + DoubleToString(rates[copied-1].close, _Digits);
   json += "}";
   
   return json;
}

//+------------------------------------------------------------------+
//| HTTP POSTリクエスト送信                                          |
//+------------------------------------------------------------------+
bool SendHttpRequest(string url, string postData, string &response)
{
   uchar post[];
   uchar result[];
   string headers = "Content-Type: application/json\r\n";
   string result_headers;
   
   StringToCharArray(postData, post, 0, StringLen(postData));
   ArrayResize(post, StringLen(postData));
   
   int res = WebRequest(
      "POST",
      url,
      headers,
      InpServerTimeout,
      post,
      result,
      result_headers
   );
   
   if(res == -1)
   {
      Print("WebRequest Error: ", GetLastError());
      return false;
   }
   
   response = CharArrayToString(result, 0, ArraySize(result));
   return true;
}

//+------------------------------------------------------------------+
//| サーバー接続テスト                                               |
//+------------------------------------------------------------------+
bool TestServerConnection()
{
   string response = "";
   // GETリクエストでヘルスチェック
   uchar post[];
   uchar result[];
   string headers = "";
   string result_headers;
   
   ArrayResize(post, 0);
   
   int res = WebRequest(
      "GET",
      InpInferenceServerURL + "/health",
      headers,
      5000,
      post,
      result,
      result_headers
   );
   
   if(res == -1)
   {
      Print("Health check failed: ", GetLastError());
      return false;
   }
   
   response = CharArrayToString(result, 0, ArraySize(result));
   
   if(StringFind(response, "ok") >= 0 || StringFind(response, "status") >= 0)
   {
      Print("✓ 推論サーバー接続OK");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| 分析レスポンス解析                                               |
//+------------------------------------------------------------------+
bool ParseAnalyzeResponse(string response, int &signal, double &confidence, bool &entryAllowed)
{
   int signalPos = StringFind(response, "\"signal\":");
   int confPos = StringFind(response, "\"confidence\":");
   int entryPos = StringFind(response, "\"entry_allowed\":");
   
   if(signalPos < 0 || confPos < 0 || entryPos < 0)
      return false;
   
   // signal抽出
   string signalStr = StringSubstr(response, signalPos + 9, 3);
   signalStr = StringTrimLeft(signalStr);
   signalStr = StringTrimRight(signalStr);
   signal = (int)StringToInteger(signalStr);
   
   // confidence抽出
   string confStr = StringSubstr(response, confPos + 14, 10);
   int commaPos = StringFind(confStr, ",");
   if(commaPos > 0)
      confStr = StringSubstr(confStr, 0, commaPos);
   confidence = StringToDouble(confStr);
   
   // entry_allowed抽出
   string entryStr = StringSubstr(response, entryPos + 17, 5);
   entryAllowed = (StringFind(entryStr, "true") >= 0);
   
   return true;
}

//+------------------------------------------------------------------+
//| Partial Close チェック                                            |
//+------------------------------------------------------------------+
void CheckPartialClose()
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      
      int currentLevel = g_partialCloseLevel[(int)(ticket % 100)];
      if(currentLevel >= 2) continue;  // 全レベル完了
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      double profitPoints = 0;
      if(posType == POSITION_TYPE_BUY)
         profitPoints = (currentPrice - openPrice) / point;
      else
         profitPoints = (openPrice - currentPrice) / point;
      
      // レベル判定
      int newLevel = currentLevel;
      double closePercent = 0;
      
      if(currentLevel == 0 && profitPoints >= InpPartialClose1Points)
      {
         closePercent = InpPartialClose1Percent;
         newLevel = 1;
      }
      else if(currentLevel == 1 && profitPoints >= InpPartialClose2Points)
      {
         closePercent = 100.0;  // 残り全決済
         newLevel = 2;
      }
      else
      {
         continue;
      }
      
      // 部分決済実行
      double currentLots = PositionGetDouble(POSITION_VOLUME);
      double lotsToClose = NormalizeDouble(currentLots * closePercent / 100.0, 2);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(lotsToClose < minLot) lotsToClose = minLot;
      
      if(m_trade.PositionClosePartial(ticket, lotsToClose))
      {
         Print("★ Partial Close Level ", newLevel, ": Ticket=", ticket,
               " Lots=", DoubleToString(lotsToClose, 2),
               " Profit=", DoubleToString(profitPoints, 1), " points");
         
         g_partialCloseLevel[(int)(ticket % 100)] = newLevel;
         
         // Level 1後にBreakEven移動
         if(newLevel == 1 && InpMoveToBreakEvenAfterLevel1)
         {
            Sleep(100);
            // 新しいポジションを検索してSL修正
            for(int j = PositionsTotal() - 1; j >= 0; j--)
            {
               ulong newTicket = PositionGetTicket(j);
               if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
                  PositionGetString(POSITION_SYMBOL) == _Symbol)
               {
                  m_trade.PositionModify(newTicket, openPrice, PositionGetDouble(POSITION_TP));
                  Print(">>> SLを建値へ移動: ", DoubleToString(openPrice, _Digits));
                  g_partialCloseLevel[(int)(newTicket % 100)] = newLevel;
                  break;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ユーティリティ関数                                                |
//+------------------------------------------------------------------+
bool PassesTimeFilter()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day_of_week == 5 && !InpTradeOnFriday)
      return false;
   
   if(!InpEnable_Time_Filter)
      return true;
   
   // JST変換
   int gmt_offset_seconds = InpGMT_Offset * 3600;
   datetime jst_time = TimeCurrent() - gmt_offset_seconds + (9 * 3600);
   MqlDateTime jst_dt;
   TimeToStruct(jst_time, jst_dt);
   
   if(jst_dt.hour >= InpCustom_Start_Hour && jst_dt.hour < InpCustom_End_Hour)
      return true;
   
   return false;
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return count;
}

double CalculateLotSize()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   double lotSize = riskAmount / (InpStopLossPoints * tickValue);
   lotSize = NormalizeDouble(lotSize, 2);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return MathMax(lotSize, InpBaseLotSize);
}

void CalculateSLTP(bool is_long, double entry_price, double &sl, double &tp)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(is_long)
   {
      sl = entry_price - InpStopLossPoints * point;
      tp = entry_price + InpTakeProfitPoints * point;
   }
   else
   {
      sl = entry_price + InpStopLossPoints * point;
      tp = entry_price - InpTakeProfitPoints * point;
   }
   
   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);
}

double GetATR(int period)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   int handle = iATR(_Symbol, PERIOD_CURRENT, period);
   if(handle == INVALID_HANDLE) return 0;
   CopyBuffer(handle, 0, 0, 1, atr);
   IndicatorRelease(handle);
   return atr[0];
}

string PeriodToString(ENUM_TIMEFRAMES period)
{
   switch(period)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "M15";
   }
}
//+------------------------------------------------------------------+
