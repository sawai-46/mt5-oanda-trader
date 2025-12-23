//+------------------------------------------------------------------+
//|                                           EAParamsLoader.mqh     |
//|                      TradeOptimizer連携 - パラメータ自動読み込み  |
//|                                                                  |
//| 使い方:                                                          |
//| 1. このファイルを MQL4/Include/ にコピー                         |
//| 2. EA に #include <EAParamsLoader.mqh> を追加                    |
//| 3. OnInit() で EAP_Init() を呼び出す                             |
//| 4. OnTick() で EAP_CheckUpdate() を呼び出し（定期更新）           |
//| 5. EAP_GetBestHours() などで推奨設定を取得                       |
//+------------------------------------------------------------------+
#property copyright "Trade Optimizer"
#property link      ""
#property strict

//--- 設定
input string EAP_ParamsFolder = "OneDriveLogs\\data\\";            // パラメータフォルダ
input int    EAP_CheckInterval = 300;                // チェック間隔（秒）
input bool   EAP_EnableLogging = true;               // ログ出力
input bool   EAP_UseSymbolSpecific = true;           // シンボル別ファイル使用
input bool   EAP_UseOptimizedParams = false;         // 最適化パラメータを使用（★オプトイン）

//--- 読み込みパラメータ構造体
struct EAOptimizedParams {
    // 基本情報
    string updated_at;
    string symbol;
    string timeframe;
    
    // 推奨時間帯
    int    best_hours[24];
    int    best_hours_count;
    int    avoid_hours[24];
    int    avoid_hours_count;
    
    // 相場環境フィルター
    double adx_min_level;
    double atr_threshold;  // FX: pips, JP225: points
    
    // SL/TP設定
    double stoploss;       // FX: pips, JP225: points
    double takeprofit;     // FX: pips, JP225: points
    
    // ロット調整
    double lot_multiplier;
    int    base_lot;       // JP225用: FX 1.0 lot = JP225 100 lot
    
    // 分析サマリー
    int    total_trades;
    double win_rate;
    double profit_factor;
    
    // 信頼度
    string confidence;  // "low", "medium", "high"
    
    // シンボルタイプ
    bool   is_jp225;
    bool   is_us_index;  // US30/US500/NQ100
};

//--- グローバル変数
EAOptimizedParams g_eap_params;
datetime g_eap_last_check = 0;
bool g_eap_loaded = false;

// 環境によってはMarketInfo/SYMBOL_VOLUME_MINが無い場合のフォールバック
#ifndef __MQL4__
    #ifndef __MQL5__
        double MarketInfo(string symbol, int type) { return 0.0; }
        double SymbolInfoDouble(string symbol, int prop) { return 0.0; }
        #define MODE_MINLOT 0
        #define SYMBOL_VOLUME_MIN 0
    #endif
#endif

double EAP_GetMinLotForSymbol(string sym)
{
#ifdef __MQL5__
    double v = 0.0;
    if(SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN, v))
        return v;
    return 0.0;
#else
    return MarketInfo(sym, MODE_MINLOT);
#endif
}

//+------------------------------------------------------------------+
//| 初期化                                                            |
//+------------------------------------------------------------------+
void EAP_Init()
{
    // シンボルタイプ判定
    string sym = Symbol();
    bool is_jp225 = (StringFind(sym, "JP225") >= 0 || StringFind(sym, "JPN225") >= 0 || 
                     StringFind(sym, "NIKKEI") >= 0 || StringFind(sym, "NI225") >= 0 ||
                     StringFind(sym, "NK225") >= 0);
    bool is_us_index = (StringFind(sym, "US30") >= 0 || StringFind(sym, "DOW") >= 0 ||
                        StringFind(sym, "US500") >= 0 || StringFind(sym, "SPX") >= 0 ||
                        StringFind(sym, "NQ100") >= 0 || StringFind(sym, "NAS100") >= 0 ||
                        StringFind(sym, "NASDAQ") >= 0);
    
    // 構造体初期化
    g_eap_params.updated_at = "";
    g_eap_params.symbol = sym;
    g_eap_params.timeframe = "";
    g_eap_params.best_hours_count = 0;
    g_eap_params.avoid_hours_count = 0;
    g_eap_params.adx_min_level = 20.0;
    g_eap_params.is_jp225 = is_jp225;
    g_eap_params.is_us_index = is_us_index;
    
    if(is_jp225) {
        // JP225デフォルト値（points）
        g_eap_params.atr_threshold = 70.0;
        g_eap_params.stoploss = 150.0;
        g_eap_params.takeprofit = 300.0;
        g_eap_params.base_lot = 100;  // FX 1.0 lot = JP225 100 lot
    } else if(is_us_index) {
        // US Indexデフォルト値（points）
        g_eap_params.atr_threshold = 30.0;
        g_eap_params.stoploss = 100.0;
        g_eap_params.takeprofit = 200.0;
        g_eap_params.base_lot = 1;  // US30: 0.01, US500/NQ100: 0.1
    } else {
        // FXデフォルト値（pips）
        g_eap_params.atr_threshold = 7.0;
        g_eap_params.stoploss = 15.0;
        g_eap_params.takeprofit = 30.0;
        g_eap_params.base_lot = 1;
    }
    
    g_eap_params.lot_multiplier = 1.0;
    g_eap_params.total_trades = 0;
    g_eap_params.win_rate = 0.0;
    g_eap_params.profit_factor = 0.0;
    g_eap_params.confidence = "low";
    
    g_eap_loaded = false;
    g_eap_last_check = 0;
    
    // 初回読み込み
    EAP_LoadParams();
    
    string sym_type = is_jp225 ? "JP225" : (is_us_index ? "US_INDEX" : "FX");
    if(EAP_EnableLogging)
        Print("[EAParamsLoader] 初期化完了 (", sym_type, ")");
}

//+------------------------------------------------------------------+
//| 定期チェック（OnTickで呼び出す）                                   |
//+------------------------------------------------------------------+
void EAP_CheckUpdate()
{
    if(TimeCurrent() - g_eap_last_check < EAP_CheckInterval)
        return;
        
    g_eap_last_check = TimeCurrent();
    EAP_LoadParams();
}

//+------------------------------------------------------------------+
//| パラメータ読み込み                                                |
//+------------------------------------------------------------------+
bool EAP_LoadParams()
{
    string filename;
    string sym = Symbol();
    StringToUpper(sym);
    // 証券会社接尾辞などを除去（例: JP225.mt4 → JP225）
    int dotPos = StringFind(sym, ".");
    if(dotPos >= 0)
        sym = StringSubstr(sym, 0, dotPos);
    // JP225系の別名を共通化
    if(StringFind(sym, "JP225") >= 0 || StringFind(sym, "JPN225") >= 0 || StringFind(sym, "NIKKEI") >= 0 || StringFind(sym, "NI225") >= 0 || StringFind(sym, "NK225") >= 0)
        sym = "JP225";
    // US Index系の別名を共通化
    if(StringFind(sym, "US30") >= 0 || StringFind(sym, "DOW") >= 0) sym = "US30";
    if(StringFind(sym, "US500") >= 0 || StringFind(sym, "SPX") >= 0) sym = "US500";
    if(StringFind(sym, "NQ100") >= 0 || StringFind(sym, "NAS100") >= 0 || StringFind(sym, "NASDAQ") >= 0) sym = "NQ100";
    
    if(EAP_UseSymbolSpecific)
    {
        // シンボル別ファイル: ea_params_USDJPY.json
        filename = EAP_ParamsFolder + "ea_params_" + sym + ".json";
    }
    else
    {
        // 汎用ファイル: ea_params_pullback.json
        filename = EAP_ParamsFolder + "ea_params_pullback.json";
    }
    
    int handle = FileOpen(filename, FILE_READ | FILE_TXT | FILE_ANSI);
    
    if(handle == INVALID_HANDLE)
    {
        if(EAP_EnableLogging && !g_eap_loaded)
            Print("[EAParamsLoader] パラメータファイルが見つかりません: ", filename);
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
    bool success = EAP_ParseJSON(content);
    
    if(success)
    {
        g_eap_loaded = true;
        if(EAP_EnableLogging)
        {
            Print("[EAParamsLoader] パラメータ読み込み成功: ", filename);
            Print("[EAParamsLoader] 信頼度: ", g_eap_params.confidence, 
                  ", 分析トレード数: ", g_eap_params.total_trades,
                  ", 勝率: ", g_eap_params.win_rate, "%");
        }
    }
    
    return success;
}

//+------------------------------------------------------------------+
//| JSONパース                                                        |
//+------------------------------------------------------------------+
bool EAP_ParseJSON(string json)
{
    // updated_at
    g_eap_params.updated_at = EAP_ParseString(json, "updated_at");
    
    // symbol, timeframe
    g_eap_params.symbol = EAP_ParseString(json, "symbol");
    g_eap_params.timeframe = EAP_ParseString(json, "timeframe");
    
    // best_hours配列
    g_eap_params.best_hours_count = EAP_ParseIntArray(json, "best_hours", g_eap_params.best_hours, 24);
    
    // avoid_hours配列
    g_eap_params.avoid_hours_count = EAP_ParseIntArray(json, "avoid_hours", g_eap_params.avoid_hours, 24);
    
    // 数値パラメータ
    double adx = EAP_ParseDouble(json, "adx_min_level");
    if(adx > 0) g_eap_params.adx_min_level = adx;
    
    // JP225/US IndexとFXで異なるキー名に対応
    if(g_eap_params.is_jp225 || g_eap_params.is_us_index) {
        // JP225/US Index: points表記
        double atr = EAP_ParseDouble(json, "atr_threshold_points");
        if(atr > 0) g_eap_params.atr_threshold = atr;
        
        double sl = EAP_ParseDouble(json, "stoploss_points");
        if(sl > 0) g_eap_params.stoploss = sl;
        
        double tp = EAP_ParseDouble(json, "takeprofit_points");
        if(tp > 0) g_eap_params.takeprofit = tp;
        
        int base = (int)EAP_ParseDouble(json, "base_lot");
        if(base > 0) g_eap_params.base_lot = base;
    } else {
        // FX: pips表記
        double atr = EAP_ParseDouble(json, "atr_threshold_pips");
        if(atr > 0) g_eap_params.atr_threshold = atr;
        
        double sl = EAP_ParseDouble(json, "stoploss_pips");
        if(sl > 0) g_eap_params.stoploss = sl;
        
        double tp = EAP_ParseDouble(json, "takeprofit_pips");
        if(tp > 0) g_eap_params.takeprofit = tp;
    }
    
    double lot_multi = EAP_ParseDouble(json, "lot_multiplier");
    if(lot_multi > 0) g_eap_params.lot_multiplier = lot_multi;
    
    // 分析結果
    g_eap_params.total_trades = (int)EAP_ParseDouble(json, "total_trades");
    g_eap_params.win_rate = EAP_ParseDouble(json, "win_rate");
    g_eap_params.profit_factor = EAP_ParseDouble(json, "profit_factor");
    
    // 信頼度
    g_eap_params.confidence = EAP_ParseString(json, "confidence");
    
    return true;
}

//+------------------------------------------------------------------+
//| 文字列パース                                                      |
//+------------------------------------------------------------------+
string EAP_ParseString(string json, string key)
{
    string search_key = "\"" + key + "\":";
    int key_pos = StringFind(json, search_key);
    
    if(key_pos < 0) return "";
    
    int start = key_pos + StringLen(search_key);
    
    // 空白スキップ
    while(start < StringLen(json) && (StringGetCharacter(json, start) == ' ' || StringGetCharacter(json, start) == '\t'))
        start++;
    
    // 引用符チェック
    if(StringGetCharacter(json, start) != '"')
        return "";
    
    start++; // 開始引用符をスキップ
    
    int end = StringFind(json, "\"", start);
    if(end < 0) return "";
    
    return StringSubstr(json, start, end - start);
}

//+------------------------------------------------------------------+
//| 数値パース                                                        |
//+------------------------------------------------------------------+
double EAP_ParseDouble(string json, string key)
{
    string search_key = "\"" + key + "\":";
    int key_pos = StringFind(json, search_key);
    
    if(key_pos < 0) return 0.0;
    
    int start = key_pos + StringLen(search_key);
    
    // 空白スキップ
    while(start < StringLen(json) && (StringGetCharacter(json, start) == ' ' || StringGetCharacter(json, start) == '\t'))
        start++;
    
    // 数値文字列を抽出
    string num_str = "";
    int i = start;
    while(i < StringLen(json))
    {
        ushort c = StringGetCharacter(json, i);
        if((c >= '0' && c <= '9') || c == '.' || c == '-')
            num_str += CharToString((uchar)c);
        else
            break;
        i++;
    }
    
    return StringToDouble(num_str);
}

//+------------------------------------------------------------------+
//| 整数配列パース                                                    |
//+------------------------------------------------------------------+
int EAP_ParseIntArray(string json, string key, int &arr[], int max_size)
{
    string search_key = "\"" + key + "\":";
    int key_pos = StringFind(json, search_key);
    
    if(key_pos < 0) return 0;
    
    // 配列の開始を探す
    int bracket_start = StringFind(json, "[", key_pos);
    if(bracket_start < 0) return 0;
    
    int bracket_end = StringFind(json, "]", bracket_start);
    if(bracket_end < 0) return 0;
    
    string arr_str = StringSubstr(json, bracket_start + 1, bracket_end - bracket_start - 1);
    
    // カンマで分割
    int count = 0;
    int pos = 0;
    
    while(pos < StringLen(arr_str) && count < max_size)
    {
        // 空白スキップ
        while(pos < StringLen(arr_str) && (StringGetCharacter(arr_str, pos) == ' ' || StringGetCharacter(arr_str, pos) == '\t'))
            pos++;
        
        if(pos >= StringLen(arr_str)) break;
        
        // 数値を抽出
        string num_str = "";
        while(pos < StringLen(arr_str))
        {
            ushort c = StringGetCharacter(arr_str, pos);
            if(c >= '0' && c <= '9')
                num_str += CharToString((uchar)c);
            else if(c == ',')
            {
                pos++;
                break;
            }
            else if(c == ' ' || c == '\t')
            {
                pos++;
                continue;
            }
            else
                break;
            pos++;
        }
        
        if(StringLen(num_str) > 0)
        {
            arr[count] = (int)StringToInteger(num_str);
            count++;
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| ベストアワーかどうかをチェック                                     |
//+------------------------------------------------------------------+
bool EAP_IsBestHour(int hour)
{
    if(!g_eap_loaded || !EAP_UseOptimizedParams) return true;  // 未ロードまたは無効時はtrue
    if(g_eap_params.best_hours_count == 0) return true;        // 設定なしはtrue
    
    for(int i = 0; i < g_eap_params.best_hours_count; i++)
    {
        if(g_eap_params.best_hours[i] == hour)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| 回避アワーかどうかをチェック                                       |
//+------------------------------------------------------------------+
bool EAP_IsAvoidHour(int hour)
{
    if(!g_eap_loaded || !EAP_UseOptimizedParams) return false; // 未ロードまたは無効時はfalse
    if(g_eap_params.avoid_hours_count == 0) return false;      // 設定なしはfalse
    
    for(int i = 0; i < g_eap_params.avoid_hours_count; i++)
    {
        if(g_eap_params.avoid_hours[i] == hour)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| 推奨ADX最小値を取得                                               |
//+------------------------------------------------------------------+
double EAP_GetADXMinLevel()
{
    if(!g_eap_loaded || !EAP_UseOptimizedParams)
        return 20.0;  // デフォルト
    return g_eap_params.adx_min_level;
}

//+------------------------------------------------------------------+
//| 推奨ロット倍率を取得                                              |
//+------------------------------------------------------------------+
double EAP_GetLotMultiplier()
{
    if(!g_eap_loaded || !EAP_UseOptimizedParams)
        return 1.0;  // デフォルト
    return g_eap_params.lot_multiplier;
}

//+------------------------------------------------------------------+
//| JP225の基準ロットを取得                                           |
//+------------------------------------------------------------------+
int EAP_GetBaseLot()
{
    if(!g_eap_loaded)
        return 100;  // FX 1.0 lot = JP225 100 lot
    return g_eap_params.base_lot;
}

//+------------------------------------------------------------------+
//| JP225かどうかを判定                                               |
//+------------------------------------------------------------------+
bool EAP_IsJP225()
{
    return g_eap_params.is_jp225;
}

//+------------------------------------------------------------------+
//| US Indexかどうかを判定                                            |
//+------------------------------------------------------------------+
bool EAP_IsUSIndex()
{
    return g_eap_params.is_us_index;
}

//+------------------------------------------------------------------+
//| ロットをリスクに応じて調整（FX用・最大ロット制限付き）             |
//+------------------------------------------------------------------+
double EAP_AdjustLot(double base_lot, double max_lot = 0)
{
    double multiplier = EAP_GetLotMultiplier();
    double adjusted = base_lot * multiplier;
    
    // 最小ロットを下回らないように
    double min_lot = EAP_GetMinLotForSymbol(Symbol());
    if(adjusted < min_lot && adjusted > 0)
        adjusted = min_lot;
    
    // 最大ロット制限
    if(max_lot > 0 && adjusted > max_lot)
        adjusted = max_lot;
    
    return NormalizeDouble(adjusted, 2);
}

//+------------------------------------------------------------------+
//| ロットをリスクに応じて調整（JP225用 - 整数のみ・最大ロット制限付き）|
//+------------------------------------------------------------------+
int EAP_AdjustLotJP225(int base_lot, int max_lot = 0)
{
    double multiplier = EAP_GetLotMultiplier();
    int adjusted = (int)MathFloor(base_lot * multiplier);
    
    // 最小1ロット
    if(adjusted < 1) adjusted = 1;
    
    // 最大ロット制限
    if(max_lot > 0 && adjusted > max_lot)
        adjusted = max_lot;
    
    return adjusted;
}

//+------------------------------------------------------------------+
//| 信頼度を取得                                                      |
//+------------------------------------------------------------------+
string EAP_GetConfidence()
{
    if(!g_eap_loaded) return "none";
    return g_eap_params.confidence;
}

//+------------------------------------------------------------------+
//| 信頼度が十分かチェック（medium以上）                               |
//+------------------------------------------------------------------+
bool EAP_IsConfidenceOK()
{
    if(!g_eap_loaded) return false;
    return (g_eap_params.confidence == "medium" || g_eap_params.confidence == "high");
}

//+------------------------------------------------------------------+
//| パラメータが読み込まれているか                                     |
//+------------------------------------------------------------------+
bool EAP_IsLoaded()
{
    return g_eap_loaded;
}

//+------------------------------------------------------------------+
//| 分析トレード数を取得                                              |
//+------------------------------------------------------------------+
int EAP_GetTotalTrades()
{
    if(!g_eap_loaded) return 0;
    return g_eap_params.total_trades;
}

//+------------------------------------------------------------------+
//| 勝率を取得                                                        |
//+------------------------------------------------------------------+
double EAP_GetWinRate()
{
    if(!g_eap_loaded) return 0.0;
    return g_eap_params.win_rate;
}

//+------------------------------------------------------------------+
//| プロフィットファクターを取得                                       |
//+------------------------------------------------------------------+
double EAP_GetProfitFactor()
{
    if(!g_eap_loaded) return 0.0;
    return g_eap_params.profit_factor;
}

//+------------------------------------------------------------------+
//| チャートにパラメータ情報を表示                                     |
//+------------------------------------------------------------------+
void EAP_DisplayInfo(int x = 10, int y = 100)
{
    string prefix = "EAP_Info_";
    
    // 既存のオブジェクトを削除
    ObjectsDeleteAll(0, prefix);
    
    if(!g_eap_loaded)
    {
        EAP_CreateLabel(prefix + "status", x, y, "EAParams: Not Loaded", clrGray);
        return;
    }
    
    color conf_color = clrGray;
    if(g_eap_params.confidence == "high") conf_color = clrLime;
    else if(g_eap_params.confidence == "medium") conf_color = clrYellow;
    else conf_color = clrOrange;
    
    int line = 0;
    int line_height = 15;
    
    EAP_CreateLabel(prefix + "title", x, y + line * line_height, 
        "=== EA Optimized Params ===", clrWhite);
    line++;
    
    EAP_CreateLabel(prefix + "conf", x, y + line * line_height,
        "Confidence: " + g_eap_params.confidence + " (Trades: " + IntegerToString(g_eap_params.total_trades) + ")",
        conf_color);
    line++;
    
    EAP_CreateLabel(prefix + "stats", x, y + line * line_height,
        "WinRate: " + DoubleToString(g_eap_params.win_rate, 1) + "% | PF: " + DoubleToString(g_eap_params.profit_factor, 2),
        clrWhite);
    line++;
    
    EAP_CreateLabel(prefix + "lot", x, y + line * line_height,
        "LotMulti: " + DoubleToString(g_eap_params.lot_multiplier, 2) + " | ADX Min: " + DoubleToString(g_eap_params.adx_min_level, 0),
        clrWhite);
    line++;
    
    // ベストアワー表示
    string best_str = "Best Hours: ";
    for(int i = 0; i < g_eap_params.best_hours_count && i < 10; i++)
    {
        if(i > 0) best_str += ",";
        best_str += IntegerToString(g_eap_params.best_hours[i]);
    }
    if(g_eap_params.best_hours_count == 0) best_str += "(none)";
    EAP_CreateLabel(prefix + "best", x, y + line * line_height, best_str, clrLime);
    line++;
    
    // 回避アワー表示
    string avoid_str = "Avoid Hours: ";
    for(int i = 0; i < g_eap_params.avoid_hours_count && i < 10; i++)
    {
        if(i > 0) avoid_str += ",";
        avoid_str += IntegerToString(g_eap_params.avoid_hours[i]);
    }
    if(g_eap_params.avoid_hours_count == 0) avoid_str += "(none)";
    EAP_CreateLabel(prefix + "avoid", x, y + line * line_height, avoid_str, clrRed);
    line++;
    
    EAP_CreateLabel(prefix + "updated", x, y + line * line_height,
        "Updated: " + g_eap_params.updated_at, clrGray);
}

//+------------------------------------------------------------------+
//| ラベル作成ヘルパー                                                |
//+------------------------------------------------------------------+
void EAP_CreateLabel(string name, int x, int y, string text, color clr)
{
    if(ObjectFind(0, name) < 0)
    {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    }
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
    ObjectSetString(0, name, OBJPROP_FONT, "Arial");
}
