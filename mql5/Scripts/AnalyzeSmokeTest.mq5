//+------------------------------------------------------------------+
//| AnalyzeSmokeTest.mq5                                              |
//| MT5 -> HTTP /analyze endpoint smoke test (no trading)             |
//| 問題切り分け用スクリプト                                           |
//+------------------------------------------------------------------+
#property strict
#property version "1.0"
#property script_show_inputs

input string InpServerUrl = "http://127.0.0.1:5001";  // サーバーURL
input int    InpTimeoutMs = 30000;                    // タイムアウト(ms)

int OnStart()
{
   Print("=== /analyze Smoke Test Start ===");
   Print("Server URL: ", InpServerUrl);
   Print("Symbol: ", _Symbol, " TimeFrame: ", EnumToString((ENUM_TIMEFRAMES)_Period));
   
   // Step 1: Health Check
   Print("");
   Print("--- Step 1: Health Check ---");
   if(!TestHealth())
   {
      Print("[FAIL] Health check failed. WebRequest許可設定を確認:");
      Print("  ツール > オプション > EA > WebRequestを許可するURL");
      Print("  に ", InpServerUrl, " を追加してください");
      return 1;
   }
   Print("[OK] Health check passed");
   
   // Step 2: Analyze Request
   Print("");
   Print("--- Step 2: /analyze Request ---");
   if(!TestAnalyze())
   {
      Print("[FAIL] Analyze request failed");
      return 2;
   }
   Print("[OK] Analyze request passed");
   
   Print("");
   Print("=== All Tests Passed ===");
   return 0;
}

bool TestHealth()
{
   uchar post[];
   uchar result[];
   string headers = "";
   string result_headers;
   
   ArrayResize(post, 0);
   string url = InpServerUrl + "/health";
   
   Print("GET ", url);
   int res = WebRequest("GET", url, headers, 5000, post, result, result_headers);
   
   if(res == -1)
   {
      int err = GetLastError();
      Print("WebRequest Error: ", err);
      if(err == 4014)
         Print("Error 4014 = WebRequestがこのURLに許可されていません");
      return false;
   }
   
   string response = CharArrayToString(result, 0, ArraySize(result));
   Print("Response (HTTP ", res, "): ", StringSubstr(response, 0, 200));
   return (res == 200 && StringFind(response, "status") >= 0);
}

bool TestAnalyze()
{
   // OHLCVデータ準備 (20本)
   int bars = 20;
   string json = "{";
   json += "\"symbol\":\"" + _Symbol + "\",";
   json += "\"timeframe\":\"M15\",";
   json += "\"preset\":\"antigravity_pullback\",";
   json += "\"ohlcv\":{";
   
   // Open
   json += "\"open\":[";
   for(int i = 0; i < bars; i++)
   {
      double val = iOpen(_Symbol, PERIOD_M15, i);
      json += DoubleToString(val, _Digits);
      if(i < bars - 1) json += ",";
   }
   json += "],";
   
   // High
   json += "\"high\":[";
   for(int i = 0; i < bars; i++)
   {
      double val = iHigh(_Symbol, PERIOD_M15, i);
      json += DoubleToString(val, _Digits);
      if(i < bars - 1) json += ",";
   }
   json += "],";
   
   // Low
   json += "\"low\":[";
   for(int i = 0; i < bars; i++)
   {
      double val = iLow(_Symbol, PERIOD_M15, i);
      json += DoubleToString(val, _Digits);
      if(i < bars - 1) json += ",";
   }
   json += "],";
   
   // Close
   json += "\"close\":[";
   for(int i = 0; i < bars; i++)
   {
      double val = iClose(_Symbol, PERIOD_M15, i);
      json += DoubleToString(val, _Digits);
      if(i < bars - 1) json += ",";
   }
   json += "],";
   
   // Volume
   json += "\"volume\":[";
   for(int i = 0; i < bars; i++)
   {
      long val = iVolume(_Symbol, PERIOD_M15, i);
      json += IntegerToString(val);
      if(i < bars - 1) json += ",";
   }
   json += "]";
   
   json += "},";
   json += "\"current_price\":" + DoubleToString(iClose(_Symbol, PERIOD_M15, 0), _Digits);
   json += "}";
   
   Print("Request JSON size: ", StringLen(json), " chars");
   
   // Send request
   uchar post[];
   uchar result[];
   string headers = "Content-Type: application/json\r\n";
   string result_headers;
   
   StringToCharArray(json, post, 0, StringLen(json));
   ArrayResize(post, StringLen(json));
   
   string url = InpServerUrl + "/analyze";
   Print("POST ", url);
   
   int res = WebRequest("POST", url, headers, InpTimeoutMs, post, result, result_headers);
   
   if(res == -1)
   {
      int err = GetLastError();
      Print("WebRequest Error: ", err);
      return false;
   }
   
   string response = CharArrayToString(result, 0, ArraySize(result));
   Print("Response (HTTP ", res, "): ", response);
   
   // Parse response
   int signalPos = StringFind(response, "\"signal\":");
   int confPos = StringFind(response, "\"confidence\":");
   int entryPos = StringFind(response, "\"entry_allowed\":");
   
   Print("Parse check: signal_pos=", signalPos, " conf_pos=", confPos, " entry_pos=", entryPos);
   
   if(signalPos < 0 || confPos < 0 || entryPos < 0)
   {
      Print("[ERROR] レスポンス内に必要なフィールドが見つかりません");
      return false;
   }
   
   // Extract values
   string signalStr = StringSubstr(response, signalPos + 9, 3);
   int signal = (int)StringToInteger(signalStr);
   
   string confStr = StringSubstr(response, confPos + 14, 10);
   int commaPos = StringFind(confStr, ",");
   if(commaPos > 0)
      confStr = StringSubstr(confStr, 0, commaPos);
   double confidence = StringToDouble(confStr);
   
   string entryStr = StringSubstr(response, entryPos + 17, 5);
   bool entryAllowed = (StringFind(entryStr, "true") >= 0);
   
   Print("Parsed: signal=", signal, " confidence=", DoubleToString(confidence, 4), " entry_allowed=", entryAllowed);
   
   return true;
}
