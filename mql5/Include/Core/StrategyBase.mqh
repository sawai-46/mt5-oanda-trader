#ifndef __STRATEGY_BASE_MQH__
#define __STRATEGY_BASE_MQH__

#include <Object.mqh>
#include <Trade/Trade.mqh>

#include <Utils/Common.mqh>
#include <Core/TradeManager.mqh>
#include <Core/IndicatorManager.mqh>

class CStrategyBase : public CObject
{
protected:
   string          m_symbol;
   ENUM_TIMEFRAMES m_timeframe;
   CTradeManager   *m_trade;
   CIndicatorManager *m_indicators;

public:
   CStrategyBase(string symbol, ENUM_TIMEFRAMES timeframe)
   : m_symbol(symbol),
     m_timeframe(timeframe),
     m_trade(NULL),
     m_indicators(NULL)
   {
      m_trade = new CTradeManager();
      m_indicators = new CIndicatorManager();
   }

   virtual ~CStrategyBase()
   {
      if(CheckPointer(m_trade) == POINTER_DYNAMIC) delete m_trade;
      if(CheckPointer(m_indicators) == POINTER_DYNAMIC) delete m_indicators;
   }

   virtual void OnTick() = 0;
   virtual bool CheckEntry() { return false; }
   virtual bool CheckExit() { return false; }
};

#endif
