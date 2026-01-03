#ifndef __AI_LEARNING_LOGGER_MQH__
#define __AI_LEARNING_LOGGER_MQH__

#include <Object.mqh>

class CAiLearningLogger : public CObject
{
private:
   bool   m_enabled;
   string m_terminalId;
   string m_folder;

private:
   static string AccountEnvTag()
   {
      const long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
      if(mode == ACCOUNT_TRADE_MODE_REAL)
         return "LIVE";
      if(mode == ACCOUNT_TRADE_MODE_DEMO)
         return "DEMO";
      if(mode == ACCOUNT_TRADE_MODE_CONTEST)
         return "CONTEST";
      return "UNKNOWN";
   }

   static string AccountLoginStr()
   {
      return (string)AccountInfoInteger(ACCOUNT_LOGIN);
   }

   static string AccountServerStr()
   {
      return AccountInfoString(ACCOUNT_SERVER);
   }

private:
   static string TimeframeToString(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return "M1";
         case PERIOD_M5:  return "M5";
         case PERIOD_M15: return "M15";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         case PERIOD_H4:  return "H4";
         case PERIOD_D1:  return "D1";
         default:         return "TF" + IntegerToString((int)tf);
      }
   }

   static bool EnsureFolderPath(string folderPath)
   {
      if(StringLen(folderPath) <= 0)
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

   string BuildFilePath(const string symbol, const ENUM_TIMEFRAMES tf) const
   {
      string tfStr = TimeframeToString(tf);
      string fname = "AI_Learning_Data_" + m_terminalId + "_" + symbol + "_" + tfStr + ".csv";
      return m_folder + "\\" + fname;
   }

   static void WriteHeaderIfEmpty(const int handle)
   {
      if(handle == INVALID_HANDLE)
         return;
      if(FileSize(handle) > 0)
         return;

      FileWrite(
         handle,
         "Timestamp", "Symbol", "Timeframe", "Direction",
         "Entry_Price", "Pattern_Type",
         "EMA12", "EMA25", "EMA100",
         "ATR", "ADX", "Channel_Width",
         "Tick_Volume", "Bar_Range",
         "Hour", "Day_Of_Week",
         "Algo_Level", "Noise_Ratio",
         "Spread", "Spread_Max",
         "Tick_Vol_Surge", "ATR_Spike_Ratio",
         "Spoofing_Suspect", "Price_Change_Pct",
         "Env", "Account_Login", "Account_Server"
      );
   }

public:
   CAiLearningLogger()
   : m_enabled(false),
     m_terminalId(""),
     m_folder("OneDriveLogs\\data\\AI_Learning")
   {
   }

   void Configure(const bool enabled, const string terminalId, const string folder)
   {
      m_enabled = enabled;
      m_terminalId = terminalId;
      m_folder = folder;
      EnsureFolderPath(m_folder);
   }

   void LogPullbackEntry(
      const string symbol,
      const ENUM_TIMEFRAMES tf,
      const string direction,
      const double entryPrice,
      const string patternType,
      const double ema12,
      const double ema25,
      const double ema100,
      const double atr,
      const double adx,
      const double channelWidth,
      const long tickVolume,
      const double barRange,
      const int hour,
      const int dayOfWeek,
      const double algoLevel,
      const double noiseRatio,
      const long spread,
      const long spreadMax,
      const double tickVolSurge,
      const double atrSpikeRatio,
      const string spoofingSuspect,
      const double priceChangePct
   )
   {
      if(!m_enabled)
         return;
      if(StringLen(m_terminalId) <= 0)
         return;

      string path = BuildFilePath(symbol, tf);
      int handle = FileOpen(path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
         handle = FileOpen(path, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
         return;

      WriteHeaderIfEmpty(handle);
      FileSeek(handle, 0, SEEK_END);

      string ts = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
      string tfStr = TimeframeToString(tf);
      string env = AccountEnvTag();
      string login = AccountLoginStr();
      string server = AccountServerStr();

      FileWrite(
         handle,
         ts,
         symbol,
         tfStr,
         direction,
         DoubleToString(entryPrice, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         patternType,
         DoubleToString(ema12, 10),
         DoubleToString(ema25, 10),
         DoubleToString(ema100, 10),
         DoubleToString(atr, 10),
         DoubleToString(adx, 4),
         DoubleToString(channelWidth, 4),
         (string)tickVolume,
         DoubleToString(barRange, 10),
         (string)hour,
         (string)dayOfWeek,
         DoubleToString(algoLevel, 4),
         DoubleToString(noiseRatio, 4),
         (string)spread,
         (string)spreadMax,
         DoubleToString(tickVolSurge, 4),
         DoubleToString(atrSpikeRatio, 4),
         spoofingSuspect,
         DoubleToString(priceChangePct, 6),
         env,
         login,
         server
      );

      FileClose(handle);
   }
};

#endif
