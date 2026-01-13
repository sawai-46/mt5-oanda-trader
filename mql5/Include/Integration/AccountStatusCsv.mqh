// AccountStatusCsv.mqh
// Export current account status to MQL5/Files/account_status.csv (overwrite)

#ifndef __ACCOUNT_STATUS_CSV_MQH__
#define __ACCOUNT_STATUS_CSV_MQH__

string AS_SanitizeFilePart(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) <= 0)
      return "unknown";

   // Replace characters that are inconvenient in filenames.
   string bad = "\\/:*?\"<>| ";
   for(int i = 0; i < StringLen(bad); i++)
   {
      ushort ch = (ushort)StringGetCharacter(bad, i);
      StringReplace(s, (string)ch, "_");
   }
   return s;
}

bool AS_EnsureFolderPath(string folderPath)
{
   if(StringLen(folderPath) <= 0)
      return false;

   // Safety: keep paths relative (MQL5/Files or FILE_COMMON).
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

void AS_WriteSnapshotCsv(const string filename, const string terminal_id)
{
   // Ensure overwrite behavior
   FileDelete(filename);
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV);
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(handle, "TerminalId", "Timestamp", "Balance", "Equity", "Margin", "FreeMargin", "Positions");

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin     = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   int positions     = (int)PositionsTotal();

   FileWrite(
      handle,
      terminal_id,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      balance,
      equity,
      margin,
      freeMargin,
      positions
   );

   FileClose(handle);
}

void ExportAccountStatus()
{
   ExportAccountStatusWithTerminalId("");
}

void ExportAccountStatusWithTerminalId(const string terminal_id)
{
   // Legacy location (backward compatible)
   AS_WriteSnapshotCsv("account_status.csv", terminal_id);

   // OneDriveLogs location (for OneDrive-aggregated ops)
   string tid = AS_SanitizeFilePart(terminal_id);
   string outDir = "OneDriveLogs\\data\\account_status";
   AS_EnsureFolderPath(outDir);
   AS_WriteSnapshotCsv(outDir + "\\account_status_" + tid + ".csv", terminal_id);
}

#endif
