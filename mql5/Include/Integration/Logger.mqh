#ifndef __LOGGER_MQH__
#define __LOGGER_MQH__

#include <Utils/Common.mqh>

class CLogger
{
public:
   static void Log(ENUM_LOG_LEVEL level, string message)
   {
      string prefix = "";
      switch(level)
      {
         case LOG_INFO:  prefix = "[INFO] ";  break;
         case LOG_WARN:  prefix = "[WARN] ";  break;
         case LOG_ERROR: prefix = "[ERROR] "; break;
         case LOG_DEBUG: prefix = "[DEBUG] "; break;
      }
      Print(prefix + message);
   }
};

#endif
