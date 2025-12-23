//+------------------------------------------------------------------+
//|                                         MagicNumberGenerator.mqh |
//|                              マジックナンバー自動生成ライブラリ   |
//|                                                                  |
//|  形式: EEPPSS (6桁)                                              |
//|    EE = EA種別 (10-39)                                           |
//|    PP = 通貨ペア (01-99)                                         |
//|    SS = プリセット (00-07)                                       |
//+------------------------------------------------------------------+
#property copyright "2025"
#property link      ""
#property strict

//+------------------------------------------------------------------+
//| EA種別コード                                                      |
//+------------------------------------------------------------------+
#define EA_TYPE_PULLBACK_ENTRY      10  // EA_PullbackEntry (FX)
#define EA_TYPE_PULLBACK_ENTRY_NK   11  // EA_PullbackEntry_Nikkei225
#define EA_TYPE_AI_TRADER_FILE      30  // MT4_AI_Trader (File版)
#define EA_TYPE_AI_TRADER_HTTP      31  // MT4_AI_Trader (HTTP版)
#define EA_TYPE_AI_PULLBACK         32  // EA_AI_Pullback

//+------------------------------------------------------------------+
//| 通貨ペアコード                                                    |
//+------------------------------------------------------------------+
int GetPairCode(string symbol)
{
   // 標準化（接尾辞を除去）
   string sym = symbol;
   if (StringLen(sym) > 6) {
      sym = StringSubstr(sym, 0, 6);
   }
   StringToUpper(sym);
   
   // FX通貨ペア
   if (sym == "USDJPY" || StringFind(symbol, "USDJPY") >= 0) return 1;
   if (sym == "EURUSD" || StringFind(symbol, "EURUSD") >= 0) return 2;
   if (sym == "GBPUSD" || StringFind(symbol, "GBPUSD") >= 0) return 3;
   if (sym == "AUDUSD" || StringFind(symbol, "AUDUSD") >= 0) return 4;
   if (sym == "USDCHF" || StringFind(symbol, "USDCHF") >= 0) return 5;
   if (sym == "USDCAD" || StringFind(symbol, "USDCAD") >= 0) return 6;
   if (sym == "NZDUSD" || StringFind(symbol, "NZDUSD") >= 0) return 7;
   if (sym == "EURJPY" || StringFind(symbol, "EURJPY") >= 0) return 8;
   if (sym == "GBPJPY" || StringFind(symbol, "GBPJPY") >= 0) return 9;
   if (sym == "AUDJPY" || StringFind(symbol, "AUDJPY") >= 0) return 10;
   if (sym == "EURGBP" || StringFind(symbol, "EURGBP") >= 0) return 11;
   if (sym == "EURAUD" || StringFind(symbol, "EURAUD") >= 0) return 12;
   
   // 株価指数
   if (StringFind(symbol, "JP225") >= 0 || StringFind(symbol, "NIKKEI") >= 0 || 
       StringFind(symbol, "JPN225") >= 0 || StringFind(symbol, "NK225") >= 0) return 50;
   if (StringFind(symbol, "US30") >= 0 || StringFind(symbol, "DOW") >= 0) return 51;
   if (StringFind(symbol, "US500") >= 0 || StringFind(symbol, "SPX") >= 0) return 52;
   if (StringFind(symbol, "NAS100") >= 0 || StringFind(symbol, "NASDAQ") >= 0 || StringFind(symbol, "NQ100") >= 0) return 53;
   if (StringFind(symbol, "DAX") >= 0 || StringFind(symbol, "GER") >= 0) return 54;
   
   // ゴールド・シルバー
   if (StringFind(symbol, "XAUUSD") >= 0 || StringFind(symbol, "GOLD") >= 0) return 60;
   if (StringFind(symbol, "XAGUSD") >= 0 || StringFind(symbol, "SILVER") >= 0) return 61;
   
   // その他・不明
   return 99;
}

//+------------------------------------------------------------------+
//| プリセットコード                                                  |
//+------------------------------------------------------------------+
// PullbackEntry用プリセット
#define PRESET_STANDARD      1   // 標準型
#define PRESET_CONSERVATIVE  2   // 保守型
#define PRESET_AGGRESSIVE    3   // 積極型
#define PRESET_AI_ADAPTIVE   4   // AI適応型
#define PRESET_AI_SCOUT      5   // AIスカウト型
#define PRESET_MULTI_LAYER   6   // マルチレイヤー
#define PRESET_CUSTOM        7   // カスタム

// AI Trader用（プリセット固定なし）
#define PRESET_AI_TRADER     0   // AI Trader（推論サーバー使用）

//+------------------------------------------------------------------+
//| マジックナンバー生成                                              |
//+------------------------------------------------------------------+
int GenerateMagicNumber(int ea_type, string symbol, int preset)
{
   int pair_code = GetPairCode(symbol);
   
   // EEPPSS形式
   int magic = ea_type * 10000 + pair_code * 100 + preset;
   
   return magic;
}

//+------------------------------------------------------------------+
//| マジックナンバー解析                                              |
//+------------------------------------------------------------------+
void ParseMagicNumber(int magic, int &ea_type, int &pair_code, int &preset)
{
   ea_type = magic / 10000;
   pair_code = (magic % 10000) / 100;
   preset = magic % 100;
}

//+------------------------------------------------------------------+
//| EA種別名取得                                                      |
//+------------------------------------------------------------------+
string GetEATypeName(int ea_type)
{
   switch(ea_type) {
      case EA_TYPE_PULLBACK_ENTRY:    return "PullbackEntry";
      case EA_TYPE_PULLBACK_ENTRY_NK: return "PullbackEntry_NK";
      case EA_TYPE_AI_TRADER_FILE:    return "AI_Trader_File";
      case EA_TYPE_AI_TRADER_HTTP:    return "AI_Trader_HTTP";
      case EA_TYPE_AI_PULLBACK:       return "AI_Pullback";
      default: return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| 通貨ペア名取得                                                    |
//+------------------------------------------------------------------+
string GetPairName(int pair_code)
{
   switch(pair_code) {
      case 1:  return "USDJPY";
      case 2:  return "EURUSD";
      case 3:  return "GBPUSD";
      case 4:  return "AUDUSD";
      case 5:  return "USDCHF";
      case 6:  return "USDCAD";
      case 7:  return "NZDUSD";
      case 8:  return "EURJPY";
      case 9:  return "GBPJPY";
      case 10: return "AUDJPY";
      case 11: return "EURGBP";
      case 12: return "EURAUD";
      case 50: return "JP225";
      case 51: return "US30";
      case 52: return "US500";
      case 53: return "NAS100";
      case 54: return "DAX";
      case 60: return "XAUUSD";
      case 61: return "XAGUSD";
      default: return "OTHER";
   }
}

//+------------------------------------------------------------------+
//| プリセット名取得                                                  |
//+------------------------------------------------------------------+
string GetPresetName(int preset)
{
   switch(preset) {
      case 0: return "AI_TRADER";
      case 1: return "STANDARD";
      case 2: return "CONSERVATIVE";
      case 3: return "AGGRESSIVE";
      case 4: return "AI_ADAPTIVE";
      case 5: return "AI_SCOUT";
      case 6: return "MULTI_LAYER";
      case 7: return "CUSTOM";
      default: return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| マジックナンバー情報を表示                                        |
//+------------------------------------------------------------------+
void PrintMagicNumberInfo(int magic)
{
   int ea_type, pair_code, preset;
   ParseMagicNumber(magic, ea_type, pair_code, preset);
   
   Print("===== Magic Number Info =====");
   Print("Magic: ", magic);
   Print("EA Type: ", GetEATypeName(ea_type), " (", ea_type, ")");
   Print("Pair: ", GetPairName(pair_code), " (", pair_code, ")");
   Print("Preset: ", GetPresetName(preset), " (", preset, ")");
   Print("=============================");
}

//+------------------------------------------------------------------+
//| 自動マジックナンバー使用時のチェック                              |
//+------------------------------------------------------------------+
bool IsAutoMagicNumber(int magic)
{
   // 旧形式（5桁以下や特殊な値）は自動生成すべき
   if (magic < 100000) return false;
   if (magic == 99999) return false;  // デフォルト値
   if (magic == 88888) return false;  // デフォルト値
   if (magic == 20250124) return false;  // 旧デフォルト値
   
   return true;
}
