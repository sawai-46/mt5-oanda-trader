#ifndef __PULLBACK_CONFIG_MQH__
#define __PULLBACK_CONFIG_MQH__

// Pullback設定（最小構成）

enum ENUM_PULLBACK_EMA_REF
{
   PULLBACK_EMA_12  = 0,
   PULLBACK_EMA_25  = 1,
   PULLBACK_EMA_100 = 2
};

enum ENUM_SLTP_MODE
{
   SLTP_FIXED = 0,
   SLTP_ATR   = 1
};

class CPullbackConfig
{
public:
   // 基本
   long            MagicNumber;
   double          LotSize;
   int             DeviationPoints;

   // Logging / Data collection (MT4 log sync compatible)
   bool            EnableAiLearningLog;
   string          TerminalId;
   string          AiLearningFolder;

   // EMA
   int             EmaShortPeriod;
   int             EmaMidPeriod;
   int             EmaLongPeriod;
   int             EmaLongPeriod;
   bool            UseEmaShort;
   bool            UseEmaMid;
   bool            UseEmaLong;
   bool            LegacyPerfectOrder; // Renamed to avoid confusion, or reused. 
   // Actually, lets replace RequirePerfectOrder with granular flags logic.
   // But to avoid breaking existing code in one go, I will keep the field but ignore it in new logic?
   // No, I should clean it up.
   // I will simply add the new bools.

   // Pullback
   bool            UseTouchPullback;
   bool            UseCrossPullback;
   bool            UseBreakPullback;
   ENUM_PULLBACK_EMA_REF PullbackEmaRef;

   // Filters
   int             MaxSpreadPoints;
   int             ATRPeriod;
   double          ATRThresholdPoints;
   bool            UseADXFilter;
   int             ADXPeriod;
   double          ADXMinLevel;

   // SL/TP
   bool            UseStopLoss;
   bool            UseTakeProfit;
   ENUM_SLTP_MODE  SLTPMode;
   double          StopLossFixedPoints;
   double          TakeProfitFixedPoints;
   double          StopLossAtrMulti;
   double          TakeProfitAtrMulti;

   // 実運用の初期値（OANDA MT5: Points単位）
   CPullbackConfig()
   : MagicNumber(0),
     LotSize(0.10),
     DeviationPoints(10),
       EnableAiLearningLog(false),
       TerminalId(""),
       AiLearningFolder("OneDriveLogs\\data\\AI_Learning"),
     EmaShortPeriod(12),
     EmaMidPeriod(25),
     EmaLongPeriod(100),
     EmaLongPeriod(100),
     UseEmaShort(true),
     UseEmaMid(true),
     UseEmaLong(true),
     UseTouchPullback(true),
     UseCrossPullback(true),
     UseBreakPullback(false),
     PullbackEmaRef(PULLBACK_EMA_25),
     MaxSpreadPoints(200),
     ATRPeriod(14),
     ATRThresholdPoints(30.0),
     UseADXFilter(true),
     ADXPeriod(14),
     ADXMinLevel(20.0),
     UseStopLoss(true),
     UseTakeProfit(true),
     SLTPMode(SLTP_FIXED),
     StopLossFixedPoints(150.0),
     TakeProfitFixedPoints(300.0),
     StopLossAtrMulti(1.5),
     TakeProfitAtrMulti(2.0)
   {
   }
};

#endif
