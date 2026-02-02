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

   static string FolderPart(const string path)
   {
      int lastSep = -1;
      for(int i = 0; i < StringLen(path); i++)
      {
         const ushort ch = (ushort)StringGetCharacter(path, i);
         if(ch == '\\' || ch == '/')
            lastSep = i;
      }
      if(lastSep < 0)
         return "";
      return StringSubstr(path, 0, lastSep);
   }

   static bool EnsureFolderPath(string folderPath)
   {
      if(StringLen(folderPath) <= 0)
         return false;

      // Safety: do not attempt to create absolute/UNC paths.
      // MQL5 file APIs typically expect paths relative to MQL5/Files (and optionally FILE_COMMON).
      if(StringLen(folderPath) >= 2 && StringGetCharacter(folderPath, 1) == ':')
         return false;
      if(StringGetCharacter(folderPath, 0) == '\\' || StringGetCharacter(folderPath, 0) == '/')
         return false;

      string parts[];
      int n = StringSplit(folderPath, '\\', parts);
      if(n <= 0)
         return false;

      string current = "";
      for(int i = 0; i < n; i++)
      {
         if(StringLen(parts[i]) == 0)
            continue;
         current = (StringLen(current) == 0) ? parts[i] : (current + "\\" + parts[i]);
         FolderCreate(current);
      }
      return true;
   }

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

      // Ensure parent folders exist for relative paths (e.g., OneDriveLogs\\logs\\...).
      // This prevents silent FileOpen failures when the folder tree doesn't exist.
      EnsureFolderPath(FolderPart(s_fileName));

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

   static void LogTrade(string action, string symbol, ulong ticket, double lots,
                        double price, double sl = 0, double tp = 0, long magic = 0, string comment = "")
   {
      string msg = StringFormat("[TRADE] %s %s Ticket=%I64u Lots=%.2f Price=%.5f",
                                action, symbol, ticket, lots, price);
      if(sl > 0) msg += StringFormat(" SL=%.5f", sl);
      if(tp > 0) msg += StringFormat(" TP=%.5f", tp);
      if(magic > 0) msg += StringFormat(" Magic=%I64d", magic);
      if(comment != "") msg += StringFormat(" Comment=%s", comment);
      Log(LOG_INFO, msg);
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
