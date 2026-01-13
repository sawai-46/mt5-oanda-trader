// AccountStatusCsv.mqh
// Export current account status to MQL4/Files/account_status.csv (overwrite)

#ifndef __ACCOUNT_STATUS_CSV_MQH__
#define __ACCOUNT_STATUS_CSV_MQH__

static string AS_SanitizeFilePart(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) <= 0)
      return "unknown";

   string bad = "\\/:*?\"<>| ";
   for(int i = 0; i < StringLen(bad); i++)
   {
      int ch = StringGetChar(bad, i);
      string one = StringSubstr(bad, i, 1);
      // Replace occurrences of this character
      StringReplace(s, one, "_");
   }
   return s;
}

static bool AS_EnsureFolderPath(string folderPath)
{
   if(StringLen(folderPath) <= 0)
      return false;

   if(StringLen(folderPath) >= 2 && StringGetChar(folderPath, 1) == ':')
      return false;
   if(StringGetChar(folderPath, 0) == '\\' || StringGetChar(folderPath, 0) == '/')
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

static void AS_WriteSnapshotCsv(const string filename, const string terminal_id)
{
   FileDelete(filename);
   int handle = FileOpen(filename, FILE_CSV | FILE_WRITE, ',');
   if(handle < 0)
      return;

   FileWrite(handle, "TerminalId", "Timestamp", "Balance", "Equity", "Margin", "FreeMargin", "Orders");

   double balance    = AccountBalance();
   double equity     = AccountEquity();
   double margin     = AccountMargin();
   double freeMargin = AccountFreeMargin();
   int orders        = OrdersTotal();

   FileWrite(handle, terminal_id, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), balance, equity, margin, freeMargin, orders);
   FileClose(handle);
}

int CountOpenPositionsMT4()
{
   int cnt = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      int t = OrderType();
      if(t == OP_BUY || t == OP_SELL)
         cnt++;
   }
   return cnt;
}

void ExportAccountStatus()
{
   ExportAccountStatusWithTerminalId("");
}

void ExportAccountStatusWithTerminalId(const string terminal_id)
{
   // Legacy location
   AS_WriteSnapshotCsv("account_status.csv", terminal_id);

   // OneDriveLogs location
   string tid = AS_SanitizeFilePart(terminal_id);
   string outDir = "OneDriveLogs\\data\\account_status";
   AS_EnsureFolderPath(outDir);
   AS_WriteSnapshotCsv(outDir + "\\account_status_" + tid + ".csv", terminal_id);
      CountOpenPositionsMT4()
   );

   FileClose(handle);
}

#endif
