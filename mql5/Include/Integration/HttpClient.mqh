#ifndef __HTTP_CLIENT_MQH__
#define __HTTP_CLIENT_MQH__

#include <Object.mqh>

class CHttpClient : public CObject
{
private:
   string m_serverUrl;
   int    m_timeout;

public:
   CHttpClient(string url, int timeout=2000)
   : m_serverUrl(url), m_timeout(timeout)
   {
   }

   void SetServerUrl(string url) { m_serverUrl = url; }

   bool PostJson(string endpoint, string jsonBody, string &responseResult, int &httpStatus)
   {
      char data[];
      char result[];

      StringToCharArray(jsonBody, data, 0, StringLen(jsonBody), CP_UTF8);

      string headers = "Content-Type: application/json\r\n";
      string resultHeaders;
      httpStatus = WebRequest("POST", m_serverUrl + endpoint, headers, m_timeout, data, result, resultHeaders);

      if(httpStatus == 200)
      {
         responseResult = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
         return true;
      }

      responseResult = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      return false;
   }
};

#endif
