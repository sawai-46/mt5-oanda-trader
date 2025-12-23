#ifndef __JSON_LITE_MQH__
#define __JSON_LITE_MQH__

class CJsonLite
{
private:
   static int SkipWs(const string s, int i)
   {
      int n = StringLen(s);
      while(i < n)
      {
         ushort c = StringGetCharacter(s, i);
         if(c!=' ' && c!='\t' && c!='\r' && c!='\n') break;
         i++;
      }
      return i;
   }

   static bool FindKey(const string json, const string key, int &outPos)
   {
      string needle = "\"" + key + "\"";
      int p = StringFind(json, needle, 0);
      if(p < 0) return false;
      p += StringLen(needle);
      p = SkipWs(json, p);
      if(p >= StringLen(json) || StringGetCharacter(json, p) != ':') return false;
      p++;
      outPos = SkipWs(json, p);
      return true;
   }

   static string UnescapeJsonString(const string s)
   {
      string out = "";
      int n = StringLen(s);
      for(int i=0; i<n; i++)
      {
         ushort c = StringGetCharacter(s, i);
         if(c == '\\' && i+1 < n)
         {
            ushort n1 = StringGetCharacter(s, i+1);
            if(n1=='\\') { out += "\\"; i++; continue; }
            if(n1=='\"') { out += "\""; i++; continue; }
            if(n1=='n') { out += "\n"; i++; continue; }
            if(n1=='r') { out += "\r"; i++; continue; }
            if(n1=='t') { out += "\t"; i++; continue; }
         }
         out += ShortToString((short)c);
      }
      return out;
   }

public:
   static bool TryGetInt(const string json, const string key, int &outValue)
   {
      int p = 0;
      if(!FindKey(json, key, p)) return false;
      int end = p;
      int n = StringLen(json);
      while(end < n)
      {
         ushort c = StringGetCharacter(json, end);
         if((c>='0' && c<='9') || c=='-' || c=='+') { end++; continue; }
         break;
      }
      if(end == p) return false;
      outValue = (int)StringToInteger(StringSubstr(json, p, end-p));
      return true;
   }

   static bool TryGetDouble(const string json, const string key, double &outValue)
   {
      int p = 0;
      if(!FindKey(json, key, p)) return false;
      int end = p;
      int n = StringLen(json);
      while(end < n)
      {
         ushort c = StringGetCharacter(json, end);
         if((c>='0' && c<='9') || c=='-' || c=='+' || c=='.' || c=='e' || c=='E') { end++; continue; }
         break;
      }
      if(end == p) return false;
      outValue = StringToDouble(StringSubstr(json, p, end-p));
      return true;
   }

   static bool TryGetString(const string json, const string key, string &outValue)
   {
      int p = 0;
      if(!FindKey(json, key, p)) return false;
      int n = StringLen(json);
      if(p >= n || StringGetCharacter(json, p) != '"') return false;
      p++;

      string buf = "";
      bool escaped = false;
      for(int i=p; i<n; i++)
      {
         ushort c = StringGetCharacter(json, i);
         if(!escaped)
         {
            if(c == '\\') { escaped = true; buf += "\\"; continue; }
            if(c == '"')
            {
               outValue = UnescapeJsonString(buf);
               return true;
            }
            buf += ShortToString((short)c);
         }
         else
         {
            escaped = false;
            buf += ShortToString((short)c);
         }
      }
      return false;
   }
};

#endif
