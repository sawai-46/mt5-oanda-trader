// AccountStatusCsv.mqh
// Export current account status to MQL4/Files/account_status.csv (overwrite)

#ifndef __ACCOUNT_STATUS_CSV_MQH__
#define __ACCOUNT_STATUS_CSV_MQH__

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
   string filename = "account_status.csv";

   // Ensure overwrite behavior
   FileDelete(filename);
   int handle = FileOpen(filename, FILE_WRITE | FILE_CSV);
   if(handle == INVALID_HANDLE)
      return;

   FileWrite(handle, "TerminalId", "Timestamp", "Balance", "Equity", "Margin", "FreeMargin", "Positions");
   FileWrite(
      handle,
      terminal_id,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      AccountBalance(),
      AccountEquity(),
      AccountMargin(),
      AccountFreeMargin(),
      CountOpenPositionsMT4()
   );

   FileClose(handle);
}

#endif
