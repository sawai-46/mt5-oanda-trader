// AccountStatusCsv.mqh
// Export current account status to MQL5/Files/account_status.csv (overwrite)

#ifndef __ACCOUNT_STATUS_CSV_MQH__
#define __ACCOUNT_STATUS_CSV_MQH__

void ExportAccountStatus()
{
   ExportAccountStatusWithTerminalId("");
}

void ExportAccountStatusWithTerminalId(const string terminal_id)
{
   string filename = "account_status.csv";

   // Ensure overwrite behavior
   FileDelete(filename);
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV);
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(handle, "TerminalId", "Timestamp", "Balance", "Equity", "Margin", "FreeMargin", "Positions");

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin     = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
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

#endif
