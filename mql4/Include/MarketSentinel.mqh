//+------------------------------------------------------------------+
//|                                          MarketSentinel.mqh      |
//|                                   Market Sentinel 統合モジュール  |
//|                                                                  |
//| 使い方:                                                          |
//| 1. このファイルを MQL4/Include/ にコピー                         |
//| 2. EA に #include <MarketSentinel.mqh> を追加                    |
//| 3. OnTick() で CheckTradePermission() を呼び出す                 |
//+------------------------------------------------------------------+
#property copyright "Market Sentinel"
#property link      ""
#property strict

//+------------------------------------------------------------------+
//| MQL4/MQL5 互換ヘルパー（ビルトイン関数は上書きしない）            |
//+------------------------------------------------------------------+
string MS_GetCurrentSymbol()
{
#ifdef __MQL5__
    return _Symbol;
#else
    return Symbol();
#endif
}

double MS_GetMinLot(const string symbol)
{
#ifdef __MQL5__
    double minLot = 0.0;
    if(SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN, minLot))
        return minLot;
    return 0.0;
#else
    return MarketInfo(symbol, MODE_MINLOT);
#endif
}

//--- 設定
input string MS_PermissionFile = "OneDriveLogs\\data\\trade_permission.json";  // 許可ファイルパス
input int    MS_CheckInterval  = 60;                              // チェック間隔（秒）
input bool   MS_EnableLogging  = true;                            // ログ出力

//--- 取引ステータス定義
enum TRADE_STATUS {
    STATUS_ALLOWED   = 0,   // 取引許可
    STATUS_CAUTION   = 1,   // 注意（ロット縮小）
    STATUS_SUSPENDED = 2    // 取引停止
};

//--- 取引許可構造体
struct TradePermission {
    TRADE_STATUS status;        // ステータス
    int          risk_level;    // リスクレベル (1-5)
    string       reason;        // 理由
    double       lot_multiplier;// ロット倍率
    datetime     resume_time;   // 再開時刻
};

//--- グローバル変数
TradePermission g_permission;
datetime g_last_check_time = 0;
bool g_permission_loaded = false;

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
void MS_Init()
{
    g_permission.status = STATUS_ALLOWED;
    g_permission.risk_level = 1;
    g_permission.reason = "";
    g_permission.lot_multiplier = 1.0;
    g_permission.resume_time = 0;
    g_permission_loaded = false;
    
    if(MS_EnableLogging)
        Print("[MarketSentinel] 初期化完了");
}

//+------------------------------------------------------------------+
//| 取引許可をチェック                                                |
//| Returns: true = 取引可能, false = 取引停止                       |
//+------------------------------------------------------------------+
bool CheckTradePermission()
{
    // チェック間隔の確認
    if(TimeCurrent() - g_last_check_time < MS_CheckInterval && g_permission_loaded)
    {
        return (g_permission.status != STATUS_SUSPENDED);
    }
    
    g_last_check_time = TimeCurrent();
    
    // ファイル読み込み
    if(!MS_ReadPermissionFile())
    {
        // ファイルがなければ許可（フェイルセーフ）
        if(MS_EnableLogging && !g_permission_loaded)
            Print("[MarketSentinel] 許可ファイルが見つかりません。取引を許可します。");
        return true;
    }
    
    g_permission_loaded = true;
    
    // ステータスに応じた処理
    if(g_permission.status == STATUS_SUSPENDED)
    {
        if(MS_EnableLogging)
            Print("[MarketSentinel] 取引停止中: ", g_permission.reason);
        return false;
    }
    
    if(g_permission.status == STATUS_CAUTION && MS_EnableLogging)
    {
        Print("[MarketSentinel] 注意: ", g_permission.reason, 
              " (ロット倍率: ", g_permission.lot_multiplier, ")");
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| リスクに応じたロット調整                                          |
//+------------------------------------------------------------------+
double AdjustLotByRisk(double base_lot)
{
    if(!g_permission_loaded)
        return base_lot;
    
    double adjusted = base_lot * g_permission.lot_multiplier;
    
    // 最小ロットを下回らないように
    double min_lot = MS_GetMinLot(MS_GetCurrentSymbol());
    if(adjusted < min_lot && adjusted > 0)
        adjusted = min_lot;
    
    return NormalizeDouble(adjusted, 2);
}

//+------------------------------------------------------------------+
//| 現在のリスクレベルを取得                                          |
//+------------------------------------------------------------------+
int GetRiskLevel()
{
    return g_permission.risk_level;
}

//+------------------------------------------------------------------+
//| 現在のステータスを取得                                            |
//+------------------------------------------------------------------+
TRADE_STATUS GetTradeStatus()
{
    return g_permission.status;
}

//+------------------------------------------------------------------+
//| 許可ファイル読み込み                                              |
//+------------------------------------------------------------------+
bool MS_ReadPermissionFile()
{
    string symbol = MS_GetCurrentSymbol();
    
    // ファイルを開く
    int handle = FileOpen(MS_PermissionFile, FILE_READ | FILE_TXT | FILE_ANSI);
    
    if(handle == INVALID_HANDLE)
    {
        return false;
    }
    
    // ファイル内容を読み込み
    string content = "";
    while(!FileIsEnding(handle))
    {
        content += FileReadString(handle);
    }
    FileClose(handle);
    
    // JSONパース
    return MS_ParseJSON(content, symbol);
}

//+------------------------------------------------------------------+
//| シンボルキー正規化（JSONキー用）                                 |
//| 例: "US30.cash" -> "US30"                                    |
//+------------------------------------------------------------------+
string MS_NormalizeSymbolKey(string symbol)
{
    // US Index: ブローカー接尾辞を吸収
    if(StringFind(symbol, "US30") >= 0)  return "US30";
    if(StringFind(symbol, "US500") >= 0) return "US500";
    return symbol;
}

//+------------------------------------------------------------------+
//| JSON パース（簡易版）                                             |
//+------------------------------------------------------------------+
bool MS_ParseJSON(string json, string symbol)
{
    // ペアセクションを探す（完全一致→正規化キーの順でフォールバック）
    string pair_key = "\"" + symbol + "\":";
    int pair_pos = StringFind(json, pair_key);

    if(pair_pos < 0)
    {
        string normalized = MS_NormalizeSymbolKey(symbol);
        if(normalized != symbol)
        {
            pair_key = "\"" + normalized + "\":";
            pair_pos = StringFind(json, pair_key);
        }
    }
    
    if(pair_pos < 0)
    {
        // シンボルが見つからない場合はデフォルト
        g_permission.status = STATUS_ALLOWED;
        g_permission.risk_level = 1;
        g_permission.lot_multiplier = 1.0;
        return true;
    }
    
    // ステータスを取得
    g_permission.status = MS_ParseStatus(json, pair_pos);
    
    // リスクレベルを取得
    g_permission.risk_level = MS_ParseInt(json, pair_pos, "risk_level");
    
    // ロット倍率を取得
    g_permission.lot_multiplier = MS_ParseDouble(json, pair_pos, "lot_multiplier");
    
    // 理由を取得
    g_permission.reason = MS_ParseString(json, pair_pos, "reason");
    
    return true;
}

//+------------------------------------------------------------------+
//| ステータスをパース                                                |
//+------------------------------------------------------------------+
TRADE_STATUS MS_ParseStatus(string json, int start_pos)
{
    string status_str = MS_ParseString(json, start_pos, "status");
    
    if(status_str == "SUSPENDED")
        return STATUS_SUSPENDED;
    else if(status_str == "CAUTION")
        return STATUS_CAUTION;
    else
        return STATUS_ALLOWED;
}

//+------------------------------------------------------------------+
//| 文字列値をパース                                                  |
//+------------------------------------------------------------------+
string MS_ParseString(string json, int start_pos, string key)
{
    string search = "\"" + key + "\":";
    int key_pos = StringFind(json, search, start_pos);
    
    if(key_pos < 0 || key_pos > start_pos + 500)
        return "";
    
    int value_start = key_pos + StringLen(search);
    
    // 空白をスキップ
    while(value_start < StringLen(json) && 
          (StringGetCharacter(json, value_start) == ' ' || 
           StringGetCharacter(json, value_start) == '\n' ||
           StringGetCharacter(json, value_start) == '\r'))
    {
        value_start++;
    }
    
    // null チェック
    if(StringSubstr(json, value_start, 4) == "null")
        return "";
    
    // 引用符を探す
    if(StringGetCharacter(json, value_start) != '"')
        return "";
    
    value_start++;
    int value_end = StringFind(json, "\"", value_start);
    
    if(value_end < 0)
        return "";
    
    return StringSubstr(json, value_start, value_end - value_start);
}

//+------------------------------------------------------------------+
//| 整数値をパース                                                    |
//+------------------------------------------------------------------+
int MS_ParseInt(string json, int start_pos, string key)
{
    string search = "\"" + key + "\":";
    int key_pos = StringFind(json, search, start_pos);
    
    if(key_pos < 0 || key_pos > start_pos + 500)
        return 1;
    
    int value_start = key_pos + StringLen(search);
    
    // 空白をスキップ
    while(value_start < StringLen(json) && 
          (StringGetCharacter(json, value_start) == ' ' ||
           StringGetCharacter(json, value_start) == '\n' ||
           StringGetCharacter(json, value_start) == '\r'))
    {
        value_start++;
    }
    
    // 数値の終わりを探す
    int value_end = value_start;
    while(value_end < StringLen(json))
    {
        int ch = StringGetCharacter(json, value_end);
        if(ch < '0' || ch > '9')
            break;
        value_end++;
    }
    
    string value_str = StringSubstr(json, value_start, value_end - value_start);
    return (int)StringToInteger(value_str);
}

//+------------------------------------------------------------------+
//| 小数値をパース                                                    |
//+------------------------------------------------------------------+
double MS_ParseDouble(string json, int start_pos, string key)
{
    string search = "\"" + key + "\":";
    int key_pos = StringFind(json, search, start_pos);
    
    if(key_pos < 0 || key_pos > start_pos + 500)
        return 1.0;
    
    int value_start = key_pos + StringLen(search);
    
    // 空白をスキップ
    while(value_start < StringLen(json) && 
          (StringGetCharacter(json, value_start) == ' ' ||
           StringGetCharacter(json, value_start) == '\n' ||
           StringGetCharacter(json, value_start) == '\r'))
    {
        value_start++;
    }
    
    // 数値の終わりを探す
    int value_end = value_start;
    while(value_end < StringLen(json))
    {
        int ch = StringGetCharacter(json, value_end);
        if((ch < '0' || ch > '9') && ch != '.')
            break;
        value_end++;
    }
    
    string value_str = StringSubstr(json, value_start, value_end - value_start);
    return StringToDouble(value_str);
}

//+------------------------------------------------------------------+
//| ステータス情報を表示                                              |
//+------------------------------------------------------------------+
void MS_PrintStatus()
{
    string status_str;
    switch(g_permission.status)
    {
        case STATUS_ALLOWED:   status_str = "ALLOWED";   break;
        case STATUS_CAUTION:   status_str = "CAUTION";   break;
        case STATUS_SUSPENDED: status_str = "SUSPENDED"; break;
        default:               status_str = "UNKNOWN";   break;
    }
    
    Print("[MarketSentinel] Status: ", status_str,
          ", Risk: ", g_permission.risk_level,
          ", Lot Multiplier: ", g_permission.lot_multiplier);
    
    if(g_permission.reason != "")
        Print("[MarketSentinel] Reason: ", g_permission.reason);
}
//+------------------------------------------------------------------+
