//+------------------------------------------------------------------+
//|                                               TimeFilter.mqh     |
//|                           MT5 Time Filter                        |
//|                                                                  |
//| 時間フィルター - 取引可能時間帯をチェック                         |
//| MT4 CommonEAからの移植版                                          |
//+------------------------------------------------------------------+
#ifndef __TIME_FILTER_MQH__
#define __TIME_FILTER_MQH__

#property copyright "2025"
#property strict

#include <Filters/IFilter.mqh>

//+------------------------------------------------------------------+
//| CTimeFilter - 時間フィルター                                     |
//+------------------------------------------------------------------+
class CTimeFilter : public IFilter
{
private:
   int      m_startHour;       // 開始時（JST）
   int      m_startMinute;     // 開始分（JST）
   int      m_endHour;         // 終了時（JST）
   int      m_endMinute;       // 終了分（JST）
   int      m_gmtOffset;       // サーバーGMTオフセット
   bool     m_useDST;          // 夏時間対応
   bool     m_tradeOnFriday;   // 金曜取引許可
   
public:
   //--- コンストラクタ
   CTimeFilter()
   {
      m_name = "TimeFilter";
      m_startHour = 8;
      m_startMinute = 0;
      m_endHour = 21;
      m_endMinute = 0;
      m_gmtOffset = 3;
      m_useDST = false;
      m_tradeOnFriday = true;
   }
   
   //--- デストラクタ
   ~CTimeFilter() {}
   
   //--- 初期化
   bool Init(int startHour, int startMinute, int endHour, int endMinute,
             int gmtOffset = 3, bool useDST = false, bool tradeOnFriday = true)
   {
      m_startHour = startHour;
      m_startMinute = startMinute;
      m_endHour = endHour;
      m_endMinute = endMinute;
      m_gmtOffset = gmtOffset;
      m_useDST = useDST;
      m_tradeOnFriday = tradeOnFriday;
      return true;
   }
   
   //--- 取引時間設定
   void SetTradingHours(int startHour, int startMinute, int endHour, int endMinute)
   {
      m_startHour = startHour;
      m_startMinute = startMinute;
      m_endHour = endHour;
      m_endMinute = endMinute;
   }
   
   //--- GMTオフセット設定
   void SetGMTOffset(int offset) { m_gmtOffset = offset; }
   
   //--- 夏時間設定
   void SetUseDST(bool use) { m_useDST = use; }
   
   //--- 金曜取引設定
   void SetTradeOnFriday(bool trade) { m_tradeOnFriday = trade; }
   
   //--- フィルターチェック
   virtual bool Check(ENUM_TREND_DIRECTION trend) override
   {
      m_lastResult.Clear();
      
      // 無効時は即パス
      if(!m_enabled)
      {
         m_lastResult.SetPass();
         return true;
      }
      
      // 現在のサーバー時間からJST時間を計算
      datetime serverTime = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(serverTime, dt);
      
      // サーバー時間からJST(+9)に変換
      // GMTOffset: サーバーのGMTオフセット
      // 例: GMTOffset=3 (GMT+3) → JST = serverTime + (9 - 3) = serverTime + 6時間
      int dstAdjust = 0;
      if(m_useDST && IsDST(serverTime))
         dstAdjust = 1;
      
      int jstOffset = 9 - (m_gmtOffset + dstAdjust);
      datetime jstTime = serverTime + jstOffset * 3600;
      
      MqlDateTime jstDt;
      TimeToStruct(jstTime, jstDt);
      
      int jstHour = jstDt.hour;
      int jstMinute = jstDt.min;
      int dayOfWeek = jstDt.day_of_week;  // 0=日, 5=金, 6=土
      
      // 金曜チェック
      if(!m_tradeOnFriday && dayOfWeek == 5)
      {
         m_lastResult.SetReject(FILTER_REJECT_TIME, "Friday trading disabled");
         return false;
      }
      
      // 週末チェック
      if(dayOfWeek == 0 || dayOfWeek == 6)
      {
         m_lastResult.SetReject(FILTER_REJECT_TIME, "Weekend");
         return false;
      }
      
      // 時間帯チェック
      int currentMinutes = jstHour * 60 + jstMinute;
      int startMinutes = m_startHour * 60 + m_startMinute;
      int endMinutes = m_endHour * 60 + m_endMinute;
      
      bool inRange = false;
      if(startMinutes <= endMinutes)
      {
         // 通常範囲（例: 8:00-21:00）
         inRange = (currentMinutes >= startMinutes && currentMinutes < endMinutes);
      }
      else
      {
         // 日跨ぎ範囲（例: 21:00-8:00）
         inRange = (currentMinutes >= startMinutes || currentMinutes < endMinutes);
      }
      
      if(!inRange)
      {
         m_lastResult.SetReject(FILTER_REJECT_TIME,
            StringFormat("Outside trading hours: %02d:%02d (JST range: %02d:%02d-%02d:%02d)",
               jstHour, jstMinute, m_startHour, m_startMinute, m_endHour, m_endMinute));
         return false;
      }
      
      m_lastResult.SetPass();
      return true;
   }
   
private:
   //--- 夏時間判定（簡易版：米国夏時間 3月第2日曜～11月第1日曜）
   bool IsDST(datetime t)
   {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      
      // 3月第2日曜～11月第1日曜
      if(dt.mon < 3 || dt.mon > 11) return false;
      if(dt.mon > 3 && dt.mon < 11) return true;
      
      // 3月: 第2日曜以降
      if(dt.mon == 3)
      {
         int secondSunday = 14 - ((int)(1 + (5 * dt.year / 4)) % 7);
         return dt.day >= secondSunday;
      }
      
      // 11月: 第1日曜より前
      if(dt.mon == 11)
      {
         int firstSunday = 7 - ((int)(1 + (5 * dt.year / 4)) % 7);
         return dt.day < firstSunday;
      }
      
      return false;
   }
};

#endif // __TIME_FILTER_MQH__
