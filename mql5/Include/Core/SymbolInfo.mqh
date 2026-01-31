//+------------------------------------------------------------------+
//|                                                 SymbolInfo.mqh   |
//|                           MT5 Symbol Information & Unit Converter |
//|                                                                  |
//| 銘柄情報クラス - FX/CFDの単位差を隠蔽し統一的なAPIを提供          |
//| MT4 CommonEAからの移植版                                          |
//+------------------------------------------------------------------+
#ifndef __SYMBOL_INFO_MQH__
#define __SYMBOL_INFO_MQH__

#property copyright "2025"
#property strict

//+------------------------------------------------------------------+
//| 銘柄タイプ                                                        |
//+------------------------------------------------------------------+
enum ENUM_SYMBOL_TYPE
{
   SYMBOL_TYPE_UNKNOWN = 0,
   SYMBOL_TYPE_FX_JPY,           // FX JPYペア (USDJPY等)
   SYMBOL_TYPE_FX_USD,           // FX ドルストレート (EURUSD等)
   SYMBOL_TYPE_FX_OTHER,         // FX その他 (EURGBP等)
   SYMBOL_TYPE_CFD_INDEX_JPY,    // CFD 日本株価指数 (JP225等)
   SYMBOL_TYPE_CFD_INDEX_USD,    // CFD 米国株価指数 (US30/US500等)
   SYMBOL_TYPE_CFD_COMMODITY     // CFD コモディティ (XAUUSD等)
};

//+------------------------------------------------------------------+
//| 入力単位 - ユーザーが入力時に使う単位                             |
//+------------------------------------------------------------------+
enum ENUM_INPUT_UNIT
{
   UNIT_PIPS = 0,          // pips（FX従来単位）
   UNIT_INDEX_POINT = 1,   // 指数ポイント（円/ドル等、実際の価格単位）
   UNIT_SYSTEM_POINT = 2   // MT5 Point単位
};

//+------------------------------------------------------------------+
//| CSymbolInfo - 銘柄情報クラス                                     |
//+------------------------------------------------------------------+
class CSymbolInfo
{
private:
   string           m_symbol;
   ENUM_SYMBOL_TYPE m_type;
   
   // MT5から取得する値
   double   m_point;          // SYMBOL_POINT
   int      m_digits;         // SYMBOL_DIGITS
   double   m_minLot;
   double   m_maxLot;
   double   m_lotStep;
   double   m_tickValue;
   double   m_tickSize;
   double   m_contractSize;
   
   // 計算で導出する値
   double   m_pip;            // 慣習的な1pip（FX: Point*10, CFD: 1.0）
   double   m_pipPoint;       // 1pipあたりのPoint数（FX: 10, CFD: 100）
   
   // スプレッド関連
   long     m_spreadPoints;   // 現在のスプレッド（Points）
   long     m_spreadMax;      // セッション中の最大スプレッド
   long     m_spreadMin;      // セッション中の最小スプレッド
   double   m_spreadAvg;      // 移動平均スプレッド
   int      m_spreadSamples;  // サンプル数
   
   bool     m_initialized;

   //--- 銘柄タイプ自動判定
   void DetectSymbolType()
   {
      string sym = m_symbol;
      StringToUpper(sym);
      
      // CFD判定（日本株価指数）
      if(StringFind(sym, "JP225") >= 0 || StringFind(sym, "NIKKEI") >= 0 ||
         StringFind(sym, "JPN225") >= 0 || StringFind(sym, "NK225") >= 0)
      {
         m_type = SYMBOL_TYPE_CFD_INDEX_JPY;
         return;
      }
      
      // CFD判定（米国株価指数）
      if(StringFind(sym, "US30") >= 0 || StringFind(sym, "DOW") >= 0 ||
         StringFind(sym, "US500") >= 0 || StringFind(sym, "SPX") >= 0 ||
         StringFind(sym, "NQ100") >= 0 || StringFind(sym, "NASDAQ") >= 0 ||
         StringFind(sym, "NDX") >= 0 || StringFind(sym, "USTEC") >= 0)
      {
         m_type = SYMBOL_TYPE_CFD_INDEX_USD;
         return;
      }
      
      // CFD判定（コモディティ）
      if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0 ||
         StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0 ||
         StringFind(sym, "WTI") >= 0 || StringFind(sym, "BRENT") >= 0 ||
         StringFind(sym, "OIL") >= 0)
      {
         m_type = SYMBOL_TYPE_CFD_COMMODITY;
         return;
      }
      
      // FX判定（JPY含むペア）
      if(StringFind(sym, "JPY") >= 0)
      {
         m_type = SYMBOL_TYPE_FX_JPY;
         return;
      }
      
      // FX判定（USD含むペア = ドルストレート）
      if(StringFind(sym, "USD") >= 0)
      {
         m_type = SYMBOL_TYPE_FX_USD;
         return;
      }
      
      // その他FX（EURGBP, AUDNZD等）
      if(m_digits == 5 || m_digits == 4)
      {
         m_type = SYMBOL_TYPE_FX_OTHER;
         return;
      }
      
      m_type = SYMBOL_TYPE_UNKNOWN;
   }
   
   //--- pip値計算
   void CalculatePipValue()
   {
      switch(m_type)
      {
         case SYMBOL_TYPE_FX_JPY:
         case SYMBOL_TYPE_FX_USD:
         case SYMBOL_TYPE_FX_OTHER:
            // FX: 1 pip = 10 points（5桁ブローカー）
            m_pip = m_point * 10.0;
            m_pipPoint = 10.0;
            break;
            
         case SYMBOL_TYPE_CFD_INDEX_JPY:
         case SYMBOL_TYPE_CFD_INDEX_USD:
            // CFD指数: 1整数 = 100 points（2桁配信）
            // トレーダーが「1円」「1ドル」と呼ぶ単位
            m_pip = 1.0;
            m_pipPoint = 100.0;
            break;
            
         case SYMBOL_TYPE_CFD_COMMODITY:
            // コモディティ: 銘柄により異なる
            if(m_digits == 2)
            {
               m_pip = 0.1;
               m_pipPoint = 10.0;
            }
            else
            {
               m_pip = m_point * 10.0;
               m_pipPoint = 10.0;
            }
            break;
            
         default:
            m_pip = m_point;
            m_pipPoint = 1.0;
      }
   }
   
public:
   //--- コンストラクタ
   CSymbolInfo()
   {
      m_symbol = "";
      m_type = SYMBOL_TYPE_UNKNOWN;
      m_point = 0;
      m_digits = 0;
      m_minLot = 0;
      m_maxLot = 0;
      m_lotStep = 0;
      m_tickValue = 0;
      m_tickSize = 0;
      m_contractSize = 0;
      m_pip = 0;
      m_pipPoint = 1;
      m_spreadPoints = 0;
      m_spreadMax = 0;
      m_spreadMin = LONG_MAX;
      m_spreadAvg = 0;
      m_spreadSamples = 0;
      m_initialized = false;
   }
   
   //--- 初期化
   bool Init(const string symbol)
   {
      m_symbol = symbol;
      
      // SymbolInfoから基本情報取得
      m_point        = SymbolInfoDouble(symbol, SYMBOL_POINT);
      m_digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      m_minLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_maxLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      m_lotStep      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      m_tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      m_tickSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      m_contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      
      if(m_point <= 0)
      {
         Print("[SymbolInfo] Init failed - invalid point for ", symbol);
         return false;
      }
      
      // 銘柄タイプ判定
      DetectSymbolType();
      
      // pip値計算
      CalculatePipValue();
      
      // 初回スプレッド取得
      Refresh();
      
      m_initialized = true;
      
      Print(StringFormat(
         "[SymbolInfo] Initialized: %s Type=%s Digits=%d Point=%.5f Pip=%.5f PipPoint=%.0f",
         m_symbol, SymbolTypeToString(), m_digits, m_point, m_pip, m_pipPoint));
      
      return true;
   }
   
   //--- スプレッド等の動的値を更新
   void Refresh()
   {
      m_spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      
      // スプレッド統計更新
      if(m_spreadPoints > m_spreadMax) m_spreadMax = m_spreadPoints;
      if(m_spreadPoints < m_spreadMin) m_spreadMin = m_spreadPoints;
      
      // 指数移動平均（EMA）
      if(m_spreadSamples == 0)
         m_spreadAvg = (double)m_spreadPoints;
      else
         m_spreadAvg = m_spreadAvg * 0.99 + (double)m_spreadPoints * 0.01;
      
      m_spreadSamples++;
   }
   
   //=== 変換ユーティリティ ===
   
   //--- pips → 価格差
   double PipsToPrice(double pips) const
   {
      return pips * m_pip;
   }
   
   //--- 価格差 → pips
   double PriceToPips(double priceDistance) const
   {
      if(m_pip <= 0) return 0;
      return priceDistance / m_pip;
   }
   
   //--- pips → MT5 Points
   int PipsToPoints(double pips) const
   {
      return (int)MathRound(pips * m_pipPoint);
   }
   
   //--- MT5 Points → pips
   double PointsToPips(long points) const
   {
      if(m_pipPoint <= 0) return 0;
      return (double)points / m_pipPoint;
   }

   //--- 入力単位 → pips
   double UnitsToPips(double value, ENUM_INPUT_UNIT unit) const
   {
      if(m_pip <= 0) return 0;
      switch(unit)
      {
         case UNIT_PIPS:
            return value;
         case UNIT_INDEX_POINT:
            // 1.0 円/ドルなどの価格単位をpipsへ
            return value / m_pip;
         case UNIT_SYSTEM_POINT:
            // MT5 Point単位をpipsへ
            return (value * m_point) / m_pip;
         default:
            return value;
      }
   }

   //--- 入力単位 → MT5 Points
   int UnitsToPoints(double value, ENUM_INPUT_UNIT unit) const
   {
      if(m_point <= 0) return 0;
      switch(unit)
      {
         case UNIT_PIPS:
            return PipsToPoints(value);
         case UNIT_INDEX_POINT:
         {
            double price = value;
            return (int)MathRound(price / m_point);
         }
         case UNIT_SYSTEM_POINT:
            return (int)MathRound(value);
         default:
            return PipsToPoints(value);
      }
   }
   
   //--- スプレッド（pips単位）
   double SpreadPips() const
   {
      return PointsToPips(m_spreadPoints);
   }
   
   //--- スプレッド（価格単位）
   double SpreadPrice() const
   {
      return (double)m_spreadPoints * m_point;
   }
   
   //=== ロット関連 ===
   
   //--- ロット正規化
   double NormalizeLot(double lot) const
   {
      if(lot < m_minLot) lot = m_minLot;
      if(lot > m_maxLot) lot = m_maxLot;
      
      if(m_lotStep > 0)
         lot = MathFloor(lot / m_lotStep) * m_lotStep;
      
      return NormalizeDouble(lot, 2);
   }
   
   //--- ロット有効性チェック
   bool IsValidLot(double lot) const
   {
      if(lot < m_minLot) return false;
      if(lot > m_maxLot) return false;
      return true;
   }
   
   //--- 価格正規化
   double NormalizePrice(double price) const
   {
      return NormalizeDouble(price, m_digits);
   }
   
   //=== ゲッター ===
   string Symbol() const { return m_symbol; }
   ENUM_SYMBOL_TYPE GetType() const { return m_type; }
   double Point() const { return m_point; }
   int Digits() const { return m_digits; }
   double Pip() const { return m_pip; }
   double PipPoint() const { return m_pipPoint; }
   double MinLot() const { return m_minLot; }
   double MaxLot() const { return m_maxLot; }
   double LotStep() const { return m_lotStep; }
   double TickValue() const { return m_tickValue; }
   double ContractSize() const { return m_contractSize; }
   long SpreadPoints() const { return m_spreadPoints; }
   long SpreadMax() const { return m_spreadMax; }
   long SpreadMin() const { return m_spreadMin; }
   double SpreadAvg() const { return m_spreadAvg; }
   bool IsInitialized() const { return m_initialized; }
   
   //--- 銘柄タイプ文字列
   string SymbolTypeToString() const
   {
      switch(m_type)
      {
         case SYMBOL_TYPE_FX_JPY:         return "FX_JPY";
         case SYMBOL_TYPE_FX_USD:         return "FX_USD";
         case SYMBOL_TYPE_FX_OTHER:       return "FX_OTHER";
         case SYMBOL_TYPE_CFD_INDEX_JPY:  return "CFD_INDEX_JPY";
         case SYMBOL_TYPE_CFD_INDEX_USD:  return "CFD_INDEX_USD";
         case SYMBOL_TYPE_CFD_COMMODITY:  return "CFD_COMMODITY";
         default:                         return "UNKNOWN";
      }
   }
   
   //--- CFD判定
   bool IsCFD() const
   {
      return m_type == SYMBOL_TYPE_CFD_INDEX_JPY || 
             m_type == SYMBOL_TYPE_CFD_INDEX_USD ||
             m_type == SYMBOL_TYPE_CFD_COMMODITY;
   }
   
   //--- FX判定
   bool IsFX() const
   {
      return m_type == SYMBOL_TYPE_FX_JPY || 
             m_type == SYMBOL_TYPE_FX_USD ||
             m_type == SYMBOL_TYPE_FX_OTHER;
   }
   
   //--- デフォルト入力単位取得
   ENUM_INPUT_UNIT GetDefaultInputUnit() const
   {
      if(IsCFD())
         return UNIT_INDEX_POINT;
      return UNIT_PIPS;
   }
};

#endif // __SYMBOL_INFO_MQH__
