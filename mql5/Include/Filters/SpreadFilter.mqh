//+------------------------------------------------------------------+
//|                                             SpreadFilter.mqh     |
//|                           MT5 Spread Filter                      |
//|                                                                  |
//| スプレッドフィルター - スプレッド上限をチェック                   |
//| MT4 PullbackOOPからの移植版                                       |
//+------------------------------------------------------------------+
#ifndef __SPREAD_FILTER_MQH__
#define __SPREAD_FILTER_MQH__

#property copyright "2025"
#property strict

#include <Filters/IFilter.mqh>

//+------------------------------------------------------------------+
//| CSpreadFilter - スプレッドフィルター                             |
//+------------------------------------------------------------------+
class CSpreadFilter : public IFilter
{
private:
   string   m_symbol;
   int      m_maxSpreadPoints;   // 最大許容スプレッド（Points）
   double   m_pipMultiplier;     // pips→points変換係数
   
public:
   //--- コンストラクタ
   CSpreadFilter()
   {
      m_name = "SpreadFilter";
      m_symbol = "";
      m_maxSpreadPoints = 200;
      m_pipMultiplier = 10.0;
   }
   
   //--- デストラクタ
   ~CSpreadFilter() {}
   
   //--- 初期化
   bool Init(string symbol, int maxSpreadPoints = 200, double pipMulti = 10.0)
   {
      m_symbol = symbol;
      m_maxSpreadPoints = maxSpreadPoints;
      m_pipMultiplier = pipMulti;
      return true;
   }
   
   //--- 最大スプレッド設定（Points）
   void SetMaxSpreadPoints(int points) { m_maxSpreadPoints = points; }
   
   //--- 最大スプレッド設定（Pips）
   void SetMaxSpreadPips(double pips)
   {
      m_maxSpreadPoints = (int)(pips * m_pipMultiplier);
   }
   
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
      
      if(StringLen(m_symbol) == 0)
      {
         m_lastResult.SetReject(FILTER_REJECT_SPREAD, "Symbol not set");
         return false;
      }
      
      // 現在のスプレッド取得
      long spreadPoints = 0;
      if(!SymbolInfoInteger(m_symbol, SYMBOL_SPREAD, spreadPoints))
      {
         m_lastResult.SetReject(FILTER_REJECT_SPREAD, "Failed to get spread");
         return false;
      }
      
      m_lastResult.value = (double)spreadPoints;
      m_lastResult.threshold = (double)m_maxSpreadPoints;
      
      // スプレッドチェック
      if(spreadPoints > (long)m_maxSpreadPoints)
      {
         m_lastResult.SetReject(FILTER_REJECT_SPREAD,
            StringFormat("Spread %d > %d pts", (int)spreadPoints, m_maxSpreadPoints),
            (double)spreadPoints, (double)m_maxSpreadPoints);
         return false;
      }
      
      m_lastResult.SetPass();
      return true;
   }
   
   //--- 現在のスプレッド取得（Points）
   int GetCurrentSpreadPoints()
   {
      if(StringLen(m_symbol) == 0) return 0;
      
      long spread = 0;
      if(!SymbolInfoInteger(m_symbol, SYMBOL_SPREAD, spread)) return 0;
      return (int)spread;
   }
   
   //--- 現在のスプレッド取得（Pips）
   double GetCurrentSpreadPips()
   {
      return GetCurrentSpreadPoints() / m_pipMultiplier;
   }
};

#endif // __SPREAD_FILTER_MQH__
