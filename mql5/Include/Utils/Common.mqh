//+------------------------------------------------------------------+
//|                                                       Common.mqh |
//|                                                    MT5_AI_Trader |
//|                                                      Antigravity |
//+------------------------------------------------------------------+
#property copyright "Antigravity"
#property version   "1.00"

#ifndef __COMMON_MQH__
#define __COMMON_MQH__

// Signal Types
enum ENUM_SIGNAL_TYPE {
   SIGNAL_NONE        = 0,
   SIGNAL_ENTRY_BUY   = 1,
   SIGNAL_ENTRY_SELL  = 2,
   SIGNAL_EXIT_BUY    = 3,
   SIGNAL_EXIT_SELL   = 4,
   SIGNAL_EXIT_ALL    = 5
};

// Log Levels
enum ENUM_LOG_LEVEL {
   LOG_INFO    = 0,
   LOG_WARN    = 1,
   LOG_ERROR   = 2,
   LOG_DEBUG   = 3
};

#endif
