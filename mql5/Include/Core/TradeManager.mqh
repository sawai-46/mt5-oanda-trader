#ifndef __TRADE_MANAGER_MQH__
#define __TRADE_MANAGER_MQH__

#include <Trade/Trade.mqh>

class CTradeManager : public CTrade
{
private:
   long m_magic;

public:
   CTradeManager()
   : m_magic(0)
   {
      SetAsyncMode(false);
      SetTypeFilling(ORDER_FILLING_IOC); // OANDA向け
      SetDeviationInPoints(10);
   }

   void Configure(long magic, int deviationPoints=10, ENUM_ORDER_TYPE_FILLING filling=ORDER_FILLING_IOC)
   {
      m_magic = magic;
      SetDeviationInPoints(deviationPoints);
      SetTypeFilling(filling);
   }

   long Magic() const { return m_magic; }
};

#endif
