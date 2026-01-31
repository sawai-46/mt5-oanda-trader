//+------------------------------------------------------------------+
//|                                          IndicatorManager.mqh    |
//|                           MT5 Indicator Management               |
//|                                                                  |
//| インジケーター管理クラス - 遅延初期化対応                         |
//| 使用時のみハンドルを作成し、不要なリソース消費を回避              |
//+------------------------------------------------------------------+
#ifndef __INDICATOR_MANAGER_MQH__
#define __INDICATOR_MANAGER_MQH__

#property copyright "2025"
#property strict

#include <Core/SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| CIndicatorManager - インジケーター管理クラス                     |
//+------------------------------------------------------------------+
class CIndicatorManager
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   CSymbolInfo*    m_symbolInfo;
   
   // EMA設定
   int    m_emaShortPeriod;
   int    m_emaMidPeriod;
   int    m_emaLongPeriod;
   
   // ATR/ADX設定
   int    m_atrPeriod;
   int    m_adxPeriod;
   
   // 遅延初期化ハンドル
   int    m_handleEmaShort;
   int    m_handleEmaMid;
   int    m_handleEmaLong;
   int    m_handleATR;
   int    m_handleADX;
   
   bool   m_initialized;

   //--- 遅延初期化: EMA短期
   int GetEmaShortHandle()
   {
      if(m_handleEmaShort == INVALID_HANDLE)
         m_handleEmaShort = iMA(m_symbol, m_timeframe, m_emaShortPeriod, 0, MODE_EMA, PRICE_CLOSE);
      return m_handleEmaShort;
   }
   
   //--- 遅延初期化: EMA中期
   int GetEmaMidHandle()
   {
      if(m_handleEmaMid == INVALID_HANDLE)
         m_handleEmaMid = iMA(m_symbol, m_timeframe, m_emaMidPeriod, 0, MODE_EMA, PRICE_CLOSE);
      return m_handleEmaMid;
   }
   
   //--- 遅延初期化: EMA長期
   int GetEmaLongHandle()
   {
      if(m_handleEmaLong == INVALID_HANDLE)
         m_handleEmaLong = iMA(m_symbol, m_timeframe, m_emaLongPeriod, 0, MODE_EMA, PRICE_CLOSE);
      return m_handleEmaLong;
   }
   
   //--- 遅延初期化: ATR
   int GetATRHandle()
   {
      if(m_handleATR == INVALID_HANDLE)
         m_handleATR = iATR(m_symbol, m_timeframe, m_atrPeriod);
      return m_handleATR;
   }
   
   //--- 遅延初期化: ADX
   int GetADXHandle()
   {
      if(m_handleADX == INVALID_HANDLE)
         m_handleADX = iADX(m_symbol, m_timeframe, m_adxPeriod);
      return m_handleADX;
   }
   
   //--- バッファ取得ヘルパー
   double CopyBuffer1(int handle, int bufferIndex, int shift)
   {
      if(handle == INVALID_HANDLE) return 0;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, bufferIndex, shift, 1, buf) != 1) return 0;
      return buf[0];
   }

public:
   //--- コンストラクタ
   CIndicatorManager()
   {
      m_symbol = "";
      m_timeframe = PERIOD_CURRENT;
      m_symbolInfo = NULL;
      
      // デフォルト値
      m_emaShortPeriod = 12;
      m_emaMidPeriod = 25;
      m_emaLongPeriod = 100;
      m_atrPeriod = 14;
      m_adxPeriod = 14;
      
      // 遅延初期化: 全てINVALID
      m_handleEmaShort = INVALID_HANDLE;
      m_handleEmaMid = INVALID_HANDLE;
      m_handleEmaLong = INVALID_HANDLE;
      m_handleATR = INVALID_HANDLE;
      m_handleADX = INVALID_HANDLE;
      
      m_initialized = false;
   }
   
   //--- デストラクタ
   ~CIndicatorManager()
   {
      ReleaseAll();
   }
   
   //--- 全ハンドル解放
   void ReleaseAll()
   {
      if(m_handleEmaShort != INVALID_HANDLE) { IndicatorRelease(m_handleEmaShort); m_handleEmaShort = INVALID_HANDLE; }
      if(m_handleEmaMid != INVALID_HANDLE) { IndicatorRelease(m_handleEmaMid); m_handleEmaMid = INVALID_HANDLE; }
      if(m_handleEmaLong != INVALID_HANDLE) { IndicatorRelease(m_handleEmaLong); m_handleEmaLong = INVALID_HANDLE; }
      if(m_handleATR != INVALID_HANDLE) { IndicatorRelease(m_handleATR); m_handleATR = INVALID_HANDLE; }
      if(m_handleADX != INVALID_HANDLE) { IndicatorRelease(m_handleADX); m_handleADX = INVALID_HANDLE; }
   }
   
   //--- 初期化
   void Init(const string symbol, ENUM_TIMEFRAMES timeframe, CSymbolInfo* symbolInfo = NULL)
   {
      m_symbol = symbol;
      m_timeframe = timeframe;
      m_symbolInfo = symbolInfo;
      m_initialized = true;
      
      // 遅延初期化のためハンドルは作成しない
      Print("[IndicatorManager] Init (lazy): ", m_symbol, " TF=", EnumToString(m_timeframe));
   }
   
   //--- 期間設定
   void SetEmaPeriods(int shortPeriod, int midPeriod, int longPeriod)
   {
      // 期間変更時はハンドル解放
      if(m_emaShortPeriod != shortPeriod && m_handleEmaShort != INVALID_HANDLE)
         { IndicatorRelease(m_handleEmaShort); m_handleEmaShort = INVALID_HANDLE; }
      if(m_emaMidPeriod != midPeriod && m_handleEmaMid != INVALID_HANDLE)
         { IndicatorRelease(m_handleEmaMid); m_handleEmaMid = INVALID_HANDLE; }
      if(m_emaLongPeriod != longPeriod && m_handleEmaLong != INVALID_HANDLE)
         { IndicatorRelease(m_handleEmaLong); m_handleEmaLong = INVALID_HANDLE; }
      
      m_emaShortPeriod = shortPeriod;
      m_emaMidPeriod = midPeriod;
      m_emaLongPeriod = longPeriod;
   }
   
   void SetAtrPeriod(int period)
   {
      if(m_atrPeriod != period && m_handleATR != INVALID_HANDLE)
         { IndicatorRelease(m_handleATR); m_handleATR = INVALID_HANDLE; }
      m_atrPeriod = period;
   }
   
   void SetAdxPeriod(int period)
   {
      if(m_adxPeriod != period && m_handleADX != INVALID_HANDLE)
         { IndicatorRelease(m_handleADX); m_handleADX = INVALID_HANDLE; }
      m_adxPeriod = period;
   }
   
   //=== EMA取得（遅延初期化） ===
   
   double GetEmaShort(int shift = 1)
   {
      return CopyBuffer1(GetEmaShortHandle(), 0, shift);
   }
   
   double GetEmaMid(int shift = 1)
   {
      return CopyBuffer1(GetEmaMidHandle(), 0, shift);
   }
   
   double GetEmaLong(int shift = 1)
   {
      return CopyBuffer1(GetEmaLongHandle(), 0, shift);
   }
   
   //=== ATR取得（遅延初期化） ===
   
   double GetATR(int shift = 1)
   {
      return CopyBuffer1(GetATRHandle(), 0, shift);
   }
   
   double GetATRPips(int shift = 1)
   {
      double atr = GetATR(shift);
      if(m_symbolInfo != NULL)
         return m_symbolInfo.PriceToPips(atr);
      // フォールバック
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      if(point <= 0) return 0;
      return atr / (point * 10.0);
   }
   
   //=== ADX取得（遅延初期化） ===
   
   double GetADX(int shift = 1)
   {
      return CopyBuffer1(GetADXHandle(), 0, shift);  // Buffer 0 = MAIN
   }
   
   double GetPlusDI(int shift = 1)
   {
      return CopyBuffer1(GetADXHandle(), 1, shift);  // Buffer 1 = +DI
   }
   
   double GetMinusDI(int shift = 1)
   {
      return CopyBuffer1(GetADXHandle(), 2, shift);  // Buffer 2 = -DI
   }
   
   //--- 状態
   bool IsInitialized() const { return m_initialized; }
   string Symbol() const { return m_symbol; }
   ENUM_TIMEFRAMES Timeframe() const { return m_timeframe; }
};

#endif // __INDICATOR_MANAGER_MQH__
