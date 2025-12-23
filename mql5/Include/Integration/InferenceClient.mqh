#ifndef __INFERENCE_CLIENT_MQH__
#define __INFERENCE_CLIENT_MQH__

#include <Integration/HttpClient.mqh>
#include <Utils/JsonLite.mqh>

class CInferenceClient
{
private:
   CHttpClient m_http;
   string      m_predictEndpoint;

   static string EscapeJson(const string s)
   {
      string out = "";
      int n = StringLen(s);
      for(int i=0; i<n; i++)
      {
         ushort c = StringGetCharacter(s, i);
         if(c=='\\') { out += "\\\\"; continue; }
         if(c=='\"') { out += "\\\""; continue; }
         if(c=='\n') { out += "\\n"; continue; }
         if(c=='\r') { out += "\\r"; continue; }
         if(c=='\t') { out += "\\t"; continue; }
         out += ShortToString((short)c);
      }
      return out;
   }

   static string TfToString(ENUM_TIMEFRAMES tf)
   {
      switch(tf)
      {
         case PERIOD_M1:  return "M1";
         case PERIOD_M2:  return "M2";
         case PERIOD_M3:  return "M3";
         case PERIOD_M4:  return "M4";
         case PERIOD_M5:  return "M5";
         case PERIOD_M6:  return "M6";
         case PERIOD_M10: return "M10";
         case PERIOD_M12: return "M12";
         case PERIOD_M15: return "M15";
         case PERIOD_M20: return "M20";
         case PERIOD_M30: return "M30";
         case PERIOD_H1:  return "H1";
         case PERIOD_H2:  return "H2";
         case PERIOD_H3:  return "H3";
         case PERIOD_H4:  return "H4";
         case PERIOD_H6:  return "H6";
         case PERIOD_H8:  return "H8";
         case PERIOD_H12: return "H12";
         case PERIOD_D1:  return "D1";
         case PERIOD_W1:  return "W1";
         case PERIOD_MN1: return "MN1";
      }
      return IntegerToString((int)tf);
   }

public:
   CInferenceClient(string baseUrl, string predictEndpoint="/predict", int timeoutMs=2000)
   : m_http(baseUrl, timeoutMs),
     m_predictEndpoint(predictEndpoint)
   {
   }

   void SetBaseUrl(string baseUrl) { m_http.SetServerUrl(baseUrl); }
   void SetPredictEndpoint(string endpoint) { m_predictEndpoint = endpoint; }

   bool Predict(string symbol, ENUM_TIMEFRAMES tf,
               string preset,
               double ema12, double ema25, double ema100,
               double atr, double close,
               string pricesCsv,
               int &outSignal, double &outConfidence, string &outReason,
               int &outHttpStatus, string &outRawResponse)
   {
      string tfStr = TfToString(tf);

      // 7moduleサーバー互換のフラット形式（pricesは "最新→過去" のCSV文字列）
      string body = "{";
      body += "\"symbol\":\"" + EscapeJson(symbol) + "\",";
      body += "\"timeframe\":\"" + EscapeJson(tfStr) + "\",";
      if(StringLen(preset) > 0)
         body += "\"preset\":\"" + EscapeJson(preset) + "\",";
      body += "\"ema12\":" + DoubleToString(ema12, _Digits) + ",";
      body += "\"ema25\":" + DoubleToString(ema25, _Digits) + ",";
      body += "\"ema100\":" + DoubleToString(ema100, _Digits) + ",";
      body += "\"atr\":" + DoubleToString(atr, _Digits) + ",";
      body += "\"close\":" + DoubleToString(close, _Digits) + ",";
      body += "\"prices\":\"" + EscapeJson(pricesCsv) + "\"";
      body += "}";

      string resp = "";
      int status = 0;
      bool ok = m_http.PostJson(m_predictEndpoint, body, resp, status);
      outHttpStatus = status;
      outRawResponse = resp;

      // HTTPが200以外でもボディが返る場合があるので、パースは試す
      int sig = 0;
      double conf = 0.0;
      string reason = "";

      bool hasSig = CJsonLite::TryGetInt(resp, "signal", sig);
      bool hasConf = CJsonLite::TryGetDouble(resp, "confidence", conf);
      CJsonLite::TryGetString(resp, "reason", reason);

      if(hasSig && hasConf)
      {
         outSignal = sig;
         outConfidence = conf;
         outReason = reason;
         return ok;
      }

      // 失敗時のフォールバック
      outSignal = 0;
      outConfidence = 0.0;
      outReason = reason;
      return false;
   }
};

#endif
