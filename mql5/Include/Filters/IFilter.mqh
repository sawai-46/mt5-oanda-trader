//+------------------------------------------------------------------+
//|                                                    IFilter.mqh   |
//|                           MT5 Filter Interface                   |
//|                                                                  |
//| フィルターインターフェース - 全フィルターの基底クラス             |
//| MT4 CommonEAからの移植版                                          |
//+------------------------------------------------------------------+
#ifndef __IFILTER_MQH__
#define __IFILTER_MQH__

#property copyright "2025"
#property strict

//+------------------------------------------------------------------+
//| トレンド方向                                                      |
//+------------------------------------------------------------------+
enum ENUM_TREND_DIRECTION
{
   TREND_NONE = 0,
   TREND_UP   = 1,
   TREND_DOWN = 2
};

//+------------------------------------------------------------------+
//| フィルター結果                                                    |
//+------------------------------------------------------------------+
enum ENUM_FILTER_RESULT
{
   FILTER_PASS = 0,
   FILTER_REJECT_SPREAD,
   FILTER_REJECT_ADX,
   FILTER_REJECT_ATR,
   FILTER_REJECT_TIME,
   FILTER_REJECT_MTF,
   FILTER_REJECT_PATTERN,
   FILTER_REJECT_OTHER
};

//+------------------------------------------------------------------+
//| フィルター結果構造体                                              |
//+------------------------------------------------------------------+
struct SFilterResult
{
   bool              passed;        // 通過したか
   ENUM_FILTER_RESULT reason;       // 拒否理由（通過時はFILTER_PASS）
   string            message;       // 詳細メッセージ
   double            value;         // 判定に使用した値
   double            threshold;     // 閾値
   
   void Clear()
   {
      passed = false;
      reason = FILTER_PASS;
      message = "";
      value = 0;
      threshold = 0;
   }
   
   void SetPass()
   {
      passed = true;
      reason = FILTER_PASS;
   }
   
   void SetReject(ENUM_FILTER_RESULT rejectReason, string msg, double val = 0, double thresh = 0)
   {
      passed = false;
      reason = rejectReason;
      message = msg;
      value = val;
      threshold = thresh;
   }
};

//+------------------------------------------------------------------+
//| IFilter - フィルターインターフェース（抽象基底クラス）           |
//+------------------------------------------------------------------+
class IFilter
{
protected:
   string        m_name;           // フィルター名
   bool          m_enabled;        // 有効フラグ
   SFilterResult m_lastResult;     // 最後の判定結果
   
public:
   //--- コンストラクタ
   IFilter()
   {
      m_name = "BaseFilter";
      m_enabled = true;
      m_lastResult.Clear();
   }
   
   //--- デストラクタ
   virtual ~IFilter() {}
   
   //--- 純粋仮想関数：フィルター判定（派生クラスで実装必須）
   virtual bool Check(ENUM_TREND_DIRECTION trend) = 0;
   
   //--- 有効/無効設定
   void Enable()  { m_enabled = true; }
   void Disable() { m_enabled = false; }
   void SetEnabled(bool enabled) { m_enabled = enabled; }
   bool IsEnabled() const { return m_enabled; }
   
   //--- フィルター名
   string GetName() const { return m_name; }
   void SetName(string name) { m_name = name; }
   
   //--- 最後の結果取得
   SFilterResult GetLastResult() const { return m_lastResult; }
   bool LastPassed() const { return m_lastResult.passed; }
   string GetLastMessage() const { return m_lastResult.message; }
   
   //--- 無効時は常にパス
   bool CheckWithEnabled(ENUM_TREND_DIRECTION trend)
   {
      if(!m_enabled)
      {
         m_lastResult.SetPass();
         return true;
      }
      return Check(trend);
   }
};

#endif // __IFILTER_MQH__
