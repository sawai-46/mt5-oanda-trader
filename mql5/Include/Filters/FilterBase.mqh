//+------------------------------------------------------------------+
//|                                              FilterBase.mqh      |
//|                     MT5 Minimal Filter Interface                 |
//|                     MT4 CommonEAからの移植版                      |
//+------------------------------------------------------------------+
#ifndef __FILTER_BASE_MQH__
#define __FILTER_BASE_MQH__

#property copyright "2025"
#property strict

#include <Object.mqh>

//+------------------------------------------------------------------+
//| CFilterBase - 最小限のフィルター基底クラス                       |
//+------------------------------------------------------------------+
class CFilterBase : public CObject
{
public:
   virtual ~CFilterBase() {}
   virtual bool Check() = 0;
   virtual string LastRejectReason() { return ""; }
};

#endif // __FILTER_BASE_MQH__
