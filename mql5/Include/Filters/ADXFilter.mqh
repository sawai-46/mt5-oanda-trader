//+------------------------------------------------------------------+
//|                                                ADXFilter.mqh     |
//|                           MT5 ADX Filter                         |
//|                                                                  |
//| ADXフィルター - トレンド強度をチェック                            |
//| MT4 PullbackOOPからの移植版                                       |
//+------------------------------------------------------------------+
#ifndef __ADX_FILTER_MQH__
#define __ADX_FILTER_MQH__

#property copyright "2025"
#property strict

#include <Filters/IFilter.mqh>

//+------------------------------------------------------------------+
//| CADXFilter - ADXフィルター                                       |
//+------------------------------------------------------------------+
class CADXFilter : public IFilter
{
private:
   string   m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   int      m_period;
   int      m_handleADX;
   double   m_minADX;         // 最小ADX値
   double   m_maxADX;         // 最大ADX値（0=無制限）
   bool     m_requireRising;  // ADX上昇中のみエントリー
   double   m_diSpreadMin;    // +DIと-DIの最小差
   
public:
   //--- コンストラクタ
   CADXFilter()
   {
      m_name = "ADXFilter";
      m_symbol = "";
      m_timeframe = PERIOD_CURRENT;
      m_period = 14;
      m_handleADX = INVALID_HANDLE;
      m_minADX = 15.0;
      m_maxADX = 0;
      m_requireRising = false;
      m_diSpreadMin = 0;
   }
   
   //--- デストラクタ
   ~CADXFilter()
   {
      if(m_handleADX != INVALID_HANDLE)
      {
         IndicatorRelease(m_handleADX);
         m_handleADX = INVALID_HANDLE;
      }
   }
   
   //--- 初期化（遅延初期化対応）
   bool Init(string symbol, ENUM_TIMEFRAMES tf, int period = 14, double minADX = 15.0)
   {
      m_symbol = symbol;
      m_timeframe = tf;
      m_period = period;
      m_minADX = minADX;
      // ハンドルは最初のCheck()まで作成しない（遅延初期化）
      return true;
   }
   
   //--- ハンドル作成（遅延初期化）
   bool EnsureHandle()
   {
      if(m_handleADX != INVALID_HANDLE) return true;
      if(StringLen(m_symbol) == 0) return false;
      
      m_handleADX = iADX(m_symbol, m_timeframe, m_period);
      return (m_handleADX != INVALID_HANDLE);
   }
   
   //--- ADX閾値設定
   void SetThresholds(double minADX, double maxADX = 0)
   {
      m_minADX = minADX;
      m_maxADX = maxADX;
   }
   
   //--- ADX上昇チェック設定
   void SetRequireRising(bool require) { m_requireRising = require; }
   
   //--- DIスプレッド閾値設定
   void SetDISpreadMin(double spread) { m_diSpreadMin = spread; }
   
   //--- フィルターチェック
   virtual bool Check(ENUM_TREND_DIRECTION trend) override
   {
      m_lastResult.Clear();
      
      // 無効時は即パス（インジケータ呼び出しを回避）
      if(!m_enabled)
      {
         m_lastResult.SetPass();
         return true;
      }
      
      // 遅延初期化
      if(!EnsureHandle())
      {
         m_lastResult.SetReject(FILTER_REJECT_ADX, "ADX handle creation failed");
         return false;
      }
      
      // ADX値取得
      double adx[], plusDI[], minusDI[];
      ArraySetAsSeries(adx, true);
      ArraySetAsSeries(plusDI, true);
      ArraySetAsSeries(minusDI, true);
      
      if(CopyBuffer(m_handleADX, 0, 1, 2, adx) != 2)
      {
         m_lastResult.SetReject(FILTER_REJECT_ADX, "Failed to copy ADX buffer");
         return false;
      }
      if(CopyBuffer(m_handleADX, 1, 1, 1, plusDI) != 1)
      {
         m_lastResult.SetReject(FILTER_REJECT_ADX, "Failed to copy +DI buffer");
         return false;
      }
      if(CopyBuffer(m_handleADX, 2, 1, 1, minusDI) != 1)
      {
         m_lastResult.SetReject(FILTER_REJECT_ADX, "Failed to copy -DI buffer");
         return false;
      }
      
      double adxCurrent = adx[0];
      double adxPrev = adx[1];
      
      m_lastResult.value = adxCurrent;
      m_lastResult.threshold = m_minADX;
      
      // 1. 最小ADXチェック（トレンドが弱すぎる）
      if(adxCurrent < m_minADX)
      {
         m_lastResult.SetReject(FILTER_REJECT_ADX,
            StringFormat("ADX %.1f < %.1f (weak trend)", adxCurrent, m_minADX),
            adxCurrent, m_minADX);
         return false;
      }
      
      // 2. 最大ADXチェック（過熱状態）
      if(m_maxADX > 0 && adxCurrent > m_maxADX)
      {
         m_lastResult.SetReject(FILTER_REJECT_ADX,
            StringFormat("ADX %.1f > %.1f (overheated)", adxCurrent, m_maxADX),
            adxCurrent, m_maxADX);
         return false;
      }
      
      // 3. ADX上昇中チェック
      if(m_requireRising && adxCurrent <= adxPrev)
      {
         m_lastResult.SetReject(FILTER_REJECT_ADX,
            StringFormat("ADX not rising (%.1f <= %.1f)", adxCurrent, adxPrev),
            adxCurrent, adxPrev);
         return false;
      }
      
      // 4. DI差チェック
      if(m_diSpreadMin > 0)
      {
         double diSpread = 0;
         if(trend == TREND_UP)
            diSpread = plusDI[0] - minusDI[0];
         else if(trend == TREND_DOWN)
            diSpread = minusDI[0] - plusDI[0];
         
         if(diSpread < m_diSpreadMin)
         {
            m_lastResult.SetReject(FILTER_REJECT_ADX,
               StringFormat("DI spread %.1f < %.1f", diSpread, m_diSpreadMin),
               diSpread, m_diSpreadMin);
            return false;
         }
      }
      
      m_lastResult.SetPass();
      return true;
   }
   
   //--- 現在のADX取得
   double GetCurrentADX()
   {
      if(!EnsureHandle()) return 0;
      
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_handleADX, 0, 1, 1, buf) != 1) return 0;
      return buf[0];
   }
   
   //--- +DI取得
   double GetPlusDI()
   {
      if(!EnsureHandle()) return 0;
      
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_handleADX, 1, 1, 1, buf) != 1) return 0;
      return buf[0];
   }
   
   //--- -DI取得
   double GetMinusDI()
   {
      if(!EnsureHandle()) return 0;
      
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_handleADX, 2, 1, 1, buf) != 1) return 0;
      return buf[0];
   }
};

#endif // __ADX_FILTER_MQH__
