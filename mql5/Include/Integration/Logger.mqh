#ifndef __LOGGER_MQH__
#define __LOGGER_MQH__

#include <Utils/Common.mqh>

class CLogger
{
private:
   static string         s_instanceId;
   static bool           s_enabled;
   static ENUM_LOG_LEVEL s_minLevel;
   static bool           s_fileEnabled;
   static bool           s_useCommonFolder;
   static string         s_fileName;

   static string LevelToString(ENUM_LOG_LEVEL level)
   {
      switch(level)
      {
         case LOG_INFO:  return "INFO";
         case LOG_WARN:  return "WARN";
         case LOG_ERROR: return "ERROR";
         case LOG_DEBUG: return "DEBUG";
      }
      return "INFO";
   }

   static bool IsAllowed(ENUM_LOG_LEVEL level)
   {
      if(!s_enabled) return false;

      // Treat s_minLevel as a verbosity threshold:
      // LOG_ERROR -> only ERROR
      // LOG_WARN  -> WARN + ERROR
      // LOG_INFO  -> INFO + WARN + ERROR
      // LOG_DEBUG -> DEBUG + INFO + WARN + ERROR
      if(s_minLevel == LOG_DEBUG) return true;
      if(s_minLevel == LOG_INFO)  return (level == LOG_INFO || level == LOG_WARN || level == LOG_ERROR);
      if(s_minLevel == LOG_WARN)  return (level == LOG_WARN || level == LOG_ERROR);
      if(s_minLevel == LOG_ERROR) return (level == LOG_ERROR);

      return true;
   }

   static string FormatLine(ENUM_LOG_LEVEL level, string message)
   {
      string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
      string id = (StringLen(s_instanceId) > 0) ? ("[" + s_instanceId + "] ") : "";
      return ts + " [" + LevelToString(level) + "] " + id + message;
   }

   static void WriteToFile(string line)
   {
      if(!s_fileEnabled) return;
      if(StringLen(s_fileName) <= 0) return;

      int flags = FILE_TXT | FILE_WRITE | FILE_READ | FILE_SHARE_WRITE;
      if(s_useCommonFolder)
         flags |= FILE_COMMON;

      int handle = FileOpen(s_fileName, flags);
      if(handle == INVALID_HANDLE)
         return;

      FileSeek(handle, 0, SEEK_END);
      FileWrite(handle, line);
      FileClose(handle);
   }

public:
   static void Configure(string instanceId,
                         bool enabled=true,
                         ENUM_LOG_LEVEL minLevel=LOG_INFO,
                         bool fileEnabled=false,
                         string fileName="",
                         bool useCommonFolder=true)
   {
      s_instanceId = instanceId;
      s_enabled = enabled;
      s_minLevel = minLevel;
      s_fileEnabled = fileEnabled;
      s_fileName = fileName;
      s_useCommonFolder = useCommonFolder;
   }

   static void Log(ENUM_LOG_LEVEL level, string message)
   {
      if(!IsAllowed(level))
         return;

      string line = FormatLine(level, message);
      Print(line);
      WriteToFile(line);
   }
};

// Static member definitions
string         CLogger::s_instanceId       = "";
bool           CLogger::s_enabled          = true;
ENUM_LOG_LEVEL CLogger::s_minLevel         = LOG_INFO;
bool           CLogger::s_fileEnabled      = false;
bool           CLogger::s_useCommonFolder  = true;
string         CLogger::s_fileName         = "";

#endif
