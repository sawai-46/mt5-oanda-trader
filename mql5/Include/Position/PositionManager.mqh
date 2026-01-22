//+------------------------------------------------------------------+
//|                                           PositionManager.mqh    |
//|                    Position Management for Pullback Strategy     |
//|                       Partial Close / Break-Even / Trailing      |
//+------------------------------------------------------------------+
#ifndef __POSITION_MANAGER_MQH__
#define __POSITION_MANAGER_MQH__

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Integration/Logger.mqh>

//--- Trailing Mode
enum ENUM_TRAILING_MODE
{
   TRAILING_DISABLED = 0,    // 無効
   TRAILING_FIXED,           // 固定pips
   TRAILING_ATR              // ATR連動
};

//--- Position Manager Config
struct SPositionConfig
{
   long     MagicNumber;
   string   Symbol;

   // Persistent Partial Close State (Global Variables)
   bool     EnablePersistentTpState;
   bool     LogPersistentTpStateEvents;
   
   // Partial Close Settings
   bool     EnablePartialClose;
   int      PartialCloseStages;        // 2 or 3
   double   PartialClose1Points;
   double   PartialClose1Percent;
   double   PartialClose2Points;
   double   PartialClose2Percent;
   double   PartialClose3Points;
   double   PartialClose3Percent;
   
   // Break-Even Settings
   bool     MoveToBreakEvenAfterLevel1;
   bool     MoveSLAfterLevel2;
   
   // Trailing Stop Settings
   ENUM_TRAILING_MODE TrailingMode;
   double   TrailingStartPoints;
   double   TrailingStepPoints;
   double   TrailingATRMulti;
   int      ATRPeriod;

   // Friday close window (JST)
   bool     EnableFridayCloseJST;
   int      FridayCloseStartHour;
   int      FridayCloseStartMinute;
   int      FridayCloseEndHour;
   int      FridayCloseEndMinute;
   
   // Slippage
   int      MaxSlippagePoints;
   
   // Default values
   SPositionConfig()
   : MagicNumber(0),
     Symbol(""),
       EnablePersistentTpState(true),
       LogPersistentTpStateEvents(false),
     EnablePartialClose(true),
     PartialCloseStages(2),
     PartialClose1Points(150.0),
     PartialClose1Percent(50.0),
     PartialClose2Points(300.0),
     PartialClose2Percent(100.0),
     PartialClose3Points(450.0),
     PartialClose3Percent(100.0),
     MoveToBreakEvenAfterLevel1(true),
     MoveSLAfterLevel2(true),
     TrailingMode(TRAILING_DISABLED),
     TrailingStartPoints(200.0),
     TrailingStepPoints(50.0),
     TrailingATRMulti(1.0),
     ATRPeriod(14),
       MaxSlippagePoints(50),
       EnableFridayCloseJST(true),
       FridayCloseStartHour(23),
       FridayCloseStartMinute(0),
       FridayCloseEndHour(4),
       FridayCloseEndMinute(30)
   {
   }
};

//+------------------------------------------------------------------+
//| CPositionManager - OOP Position Management                       |
//+------------------------------------------------------------------+
class CPositionManager
{
private:
   SPositionConfig  m_cfg;
   CTrade           m_trade;
   CPositionInfo    m_position;
   
   // Partial close level tracking (ticket % 100 -> level)
   int              m_partialLevels[];

   // Persist cleanup throttle
   datetime         m_lastPersistCleanup;
   
   // SL sync cooldown (continuous sync)
   datetime         m_lastSLSyncAttempt;

   // ATR handle for trailing
   int              m_handleATR;

public:
   //--- Constructor
   CPositionManager()
   : m_handleATR(INVALID_HANDLE),
     m_lastPersistCleanup(0),
     m_lastSLSyncAttempt(0)
   {
      ArrayResize(m_partialLevels, 1000); // 衝突回避のため拡張
      ArrayInitialize(m_partialLevels, 0);
   }
   
   //--- Destructor
   ~CPositionManager()
   {
      if(m_handleATR != INVALID_HANDLE)
         IndicatorRelease(m_handleATR);
   }
   
   //--- Initialize with config
   void Init(const SPositionConfig &cfg)
   {
      m_cfg = cfg;
      m_trade.SetExpertMagicNumber((ulong)m_cfg.MagicNumber);
      m_trade.SetDeviationInPoints(m_cfg.MaxSlippagePoints);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
      
      if(m_cfg.TrailingMode == TRAILING_ATR && StringLen(m_cfg.Symbol) > 0)
      {
         m_handleATR = iATR(m_cfg.Symbol, PERIOD_CURRENT, m_cfg.ATRPeriod);
      }
      
      CLogger::Log(LOG_INFO, StringFormat("[POS_MGR] Initialized: Magic=%lld Symbol=%s", m_cfg.MagicNumber, m_cfg.Symbol));
   }
   
   //--- Main tick handler - call from EA's OnTick
   void OnTick()
   {
      if(m_cfg.EnableFridayCloseJST && IsFridayCloseWindowJST())
      {
         CloseAllPositionsForSymbolMagic("JST Friday close window");
         return;
      }

      if(m_cfg.EnablePersistentTpState)
      {
         RestoreAllOpenPositions();
         CleanupIfFlat();
      }

      if(m_cfg.EnablePartialClose)
         CheckPartialClose();
      
      if(m_cfg.TrailingMode != TRAILING_DISABLED)
         CheckTrailingStop();

      // Continuous SL synchronization (runs every tick, respects cooldown)
      EnsureStopLossSync();
   }
   
   //--- Get partial close level for ticket
   int GetPartialLevel(ulong ticket)
   {
      return m_partialLevels[(int)(ticket % 1000)];
   }
   
   //--- Set partial close level for ticket
   void SetPartialLevel(ulong ticket, int level)
   {
      m_partialLevels[(int)(ticket % 1000)] = level;
   }

private:
   //+------------------------------------------------------------------+
   //| SL safety helpers                                               |
   //+------------------------------------------------------------------+
   bool IsFinitePrice(const double v) const
   {
      if(v != v)
         return false;
      if(MathAbs(v) > 1e10)
         return false;
      return true;
   }

   bool IsSafeStopLossChange(const ENUM_POSITION_TYPE posType, const double currentSL, const double newSL, const double point) const
   {
      if(!IsFinitePrice(newSL))
         return false;
      if(newSL <= 0.0)
         return false;

      double tol = (point > 0.0) ? (point * 2.0) : 0.0;
      if(currentSL > 0.0)
      {
         // BUY: SLを下げる(悪化)のは禁止 / SELL: SLを上げる(悪化)のは禁止
         if(posType == POSITION_TYPE_BUY && newSL < (currentSL - tol))
            return false;
         if(posType == POSITION_TYPE_SELL && newSL > (currentSL + tol))
            return false;
      }
      return true;
   }

   bool ModifyPositionSltpByTicket(const ulong ticket, const double sl, const double tp, uint &retcode)
   {
      retcode = 0;
      if(ticket == 0)
         return false;
      if(!PositionSelectByTicket(ticket))
         return false;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = PositionGetString(POSITION_SYMBOL);
      req.magic    = (ulong)m_cfg.MagicNumber;
      req.sl       = sl;
      req.tp       = tp;

      const bool ok = OrderSend(req, res);
      retcode = res.retcode;
      if(!ok)
         return false;

      return (res.retcode == TRADE_RETCODE_DONE || res.retcode == TRADE_RETCODE_DONE_PARTIAL);
   }

   bool IsFridayCloseWindowJST() const
   {
      datetime jst = TimeGMT() + 9 * 3600;
      MqlDateTime dt; TimeToStruct(jst, dt);
      int minutes = dt.hour * 60 + dt.min;
      int start = m_cfg.FridayCloseStartHour * 60 + m_cfg.FridayCloseStartMinute;
      int end = m_cfg.FridayCloseEndHour * 60 + m_cfg.FridayCloseEndMinute;
      if(dt.day_of_week == 5)
      {
         if(start <= end) return (minutes >= start && minutes <= end);
         return (minutes >= start);
      }
      if(dt.day_of_week == 6 && start > end)
         return (minutes <= end);
      return false;
   }

   void CloseAllPositionsForSymbolMagic(const string reason)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_cfg.Symbol) continue;
         m_trade.PositionClose(ticket);
      }
      if(m_cfg.LogPersistentTpStateEvents)
         CLogger::Log(LOG_INFO, StringFormat("[FRI_CLOSE][MT5_PM] %s magic=%lld", reason, m_cfg.MagicNumber));
   }

   bool SafePositionModifySL(const ulong ticket, const double desiredSL, const double tp, const string tag)
   {
      if(ticket == 0)
         return false;
      if(!PositionSelectByTicket(ticket))
         return false;

      const ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const double currentSL = PositionGetDouble(POSITION_SL);
      const double point = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_POINT);
      const int digits = (int)SymbolInfoInteger(m_cfg.Symbol, SYMBOL_DIGITS);
      const double newSL = NormalizeDouble(desiredSL, digits);

      if(!IsSafeStopLossChange(posType, currentSL, newSL, point))
      {
         CLogger::Log(LOG_WARN, StringFormat("[SAFE_SL][MT5_PM] Skip PositionModify(%s): ticket=%lld sl=%.5f curSL=%.5f", tag, ticket, newSL, currentSL));
         return false;
      }

      uint retcode = 0;
      if(ModifyPositionSltpByTicket(ticket, newSL, tp, retcode))
         return true;

      const int err = GetLastError();
      CLogger::Log(LOG_WARN, StringFormat("[SAFE_SL][MT5_PM] Position SLTP modify failed(%s): ticket=%lld sl=%.5f tp=%.5f retcode=%u err=%d", tag, ticket, newSL, tp, retcode, err));
      ResetLastError();
      return false;
   }

   //+------------------------------------------------------------------+
   //| Persistent Partial Close (Terminal Global Variables)             |
   //+------------------------------------------------------------------+
   string PersistPrefix() const
   {
      return "PERSIST|MT5_PM|" + m_cfg.Symbol + "|" + StringFormat("%lld", m_cfg.MagicNumber) + "|";
   }

   string PersistKey(long identifier, const string field) const
   {
      return PersistPrefix() + StringFormat("%lld", identifier) + "|" + field;
   }

   double GVGetD(const string key, const double defaultValue = 0.0) const
   {
      if(GlobalVariableCheck(key))
         return GlobalVariableGet(key);
      return defaultValue;
   }

   bool HasAnyPositionForSymbolMagic() const
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_cfg.Symbol) continue;
         return true;
      }
      return false;
   }

   void PersistClearAllForSymbolMagic()
   {
      string prefix = PersistPrefix();
      int total = GlobalVariablesTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         string name = GlobalVariableName(i);
         if(StringFind(name, prefix) == 0)
            GlobalVariableDel(name);
      }

      if(m_cfg.LogPersistentTpStateEvents)
         CLogger::Log(LOG_INFO, StringFormat("[PERSIST][MT5_PM] cleared GV for %s magic=%lld", m_cfg.Symbol, m_cfg.MagicNumber));
   }

   void PersistSaveByTicket(const ulong ticket, const int stage)
   {
      if(!m_cfg.EnablePersistentTpState)
         return;
      if(ticket == 0)
         return;
      if(!PositionSelectByTicket(ticket))
         return;

      long identifier = (long)PositionGetInteger(POSITION_IDENTIFIER);
      int posType = (int)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      GlobalVariableSet(PersistKey(identifier, "stage"), (double)stage);
      GlobalVariableSet(PersistKey(identifier, "type"), (double)posType);
      GlobalVariableSet(PersistKey(identifier, "openPrice"), openPrice);
      GlobalVariableSet(PersistKey(identifier, "lastUpdate"), (double)TimeCurrent());

      if(m_cfg.LogPersistentTpStateEvents)
         CLogger::Log(LOG_INFO, StringFormat("[PERSIST][MT5_PM] saved ident=%lld ticket=%lld stage=%d", identifier, ticket, stage));
   }

   void RestoreForSelectedPosition(const ulong ticket)
   {
      if(!m_cfg.EnablePersistentTpState)
         return;
      if(ticket == 0)
         return;

      long identifier = (long)PositionGetInteger(POSITION_IDENTIFIER);
      string stageKey = PersistKey(identifier, "stage");
      if(!GlobalVariableCheck(stageKey))
         return;

      double point = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_POINT);
      if(point <= 0) point = 0.00001;

      int persistedStage = (int)GVGetD(stageKey, 0.0);
      int persistedType = (int)GVGetD(PersistKey(identifier, "type"), -1.0);
      double persistedOpen = GVGetD(PersistKey(identifier, "openPrice"), 0.0);

      int currentType = (int)PositionGetInteger(POSITION_TYPE);
      double currentOpen = PositionGetDouble(POSITION_PRICE_OPEN);

      // Guard: type match + open price near match
      if(persistedType != currentType)
         return;
      if(MathAbs(currentOpen - persistedOpen) > (point * 2))
         return;

      int idx = (int)(ticket % 1000);
      int merged = (int)MathMax(m_partialLevels[idx], persistedStage);
      if(merged != m_partialLevels[idx])
      {
         m_partialLevels[idx] = merged;
         if(m_cfg.LogPersistentTpStateEvents)
            CLogger::Log(LOG_INFO, StringFormat("[PERSIST][MT5_PM] restored ident=%lld ticket=%lld stage=%d", identifier, ticket, merged));

         // 復元後にSL位置を再同期（第2利確到達ならTP1へ、それ以外は建値へ）
         ApplyPersistedStopLoss(ticket, merged, currentOpen, (ENUM_POSITION_TYPE)currentType, point);
      }
   }

   void ApplyPersistedStopLoss(const ulong ticket, const int stage, const double openPrice, const ENUM_POSITION_TYPE posType, const double point)
   {
      if(stage <= 0) return;

      const double tp = PositionGetDouble(POSITION_TP);

      if(stage >= 2 && m_cfg.PartialCloseStages >= 3 && m_cfg.MoveSLAfterLevel2)
      {
         double level1Price = openPrice + ((posType == POSITION_TYPE_BUY) ? m_cfg.PartialClose1Points * point : -m_cfg.PartialClose1Points * point);
         MoveSLTo(ticket, level1Price);
         return;
      }

      if(stage >= 1 && m_cfg.MoveToBreakEvenAfterLevel1)
      {
         MoveToBreakEven(ticket, openPrice);
      }
   }

   void RestoreAllOpenPositions()
   {
      if(!m_cfg.EnablePersistentTpState)
         return;
      if(StringLen(m_cfg.Symbol) == 0)
         return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_cfg.Symbol) continue;

         RestoreForSelectedPosition(ticket);
      }
   }

   void CleanupIfFlat()
   {
      if(!m_cfg.EnablePersistentTpState)
         return;

      if(HasAnyPositionForSymbolMagic())
         return;

      datetime now = TimeCurrent();
      // クールダウン: 一度削除したら300秒（5分）は再削除しない
      if(m_lastPersistCleanup != 0 && (now - m_lastPersistCleanup) < 300)
         return;

      m_lastPersistCleanup = now;
      PersistClearAllForSymbolMagic();
   }

   //--- Check and execute partial close
   void CheckPartialClose()
   {
      double point = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_POINT);
      int maxLevel = (m_cfg.PartialCloseStages >= 3) ? 3 : 2;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_cfg.Symbol) continue;
         
         int ticketIdx = (int)(ticket % 1000);
         if(m_cfg.EnablePersistentTpState)
            RestoreForSelectedPosition(ticket);

         int currentLevel = m_partialLevels[ticketIdx];
         if(currentLevel >= maxLevel) continue;
         
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         double profitPoints = 0;
         if(posType == POSITION_TYPE_BUY)
            profitPoints = (currentPrice - openPrice) / point;
         else
            profitPoints = (openPrice - currentPrice) / point;
         
         // Determine target level
         int newLevel = currentLevel;
         double closePercent = 0;
         double targetPoints = 0;
         
         if(currentLevel == 0 && profitPoints >= m_cfg.PartialClose1Points)
         {
            targetPoints = m_cfg.PartialClose1Points;
            closePercent = m_cfg.PartialClose1Percent;
            newLevel = 1;
         }
         else if(currentLevel == 1 && profitPoints >= m_cfg.PartialClose2Points)
         {
            targetPoints = m_cfg.PartialClose2Points;
            closePercent = (maxLevel == 2) ? 100.0 : m_cfg.PartialClose2Percent;
            newLevel = 2;
         }
         else if(maxLevel >= 3 && currentLevel == 2 && profitPoints >= m_cfg.PartialClose3Points)
         {
            targetPoints = m_cfg.PartialClose3Points;
            closePercent = m_cfg.PartialClose3Percent;
            newLevel = 3;
         }
         else
         {
            continue;  // No level reached
         }
         
         // Execute partial close (残ポジション％方式)
         double currentLots = PositionGetDouble(POSITION_VOLUME);
         double lotStep = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_VOLUME_STEP);
         if(lotStep <= 0) lotStep = 0.01;
         double minLot = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_VOLUME_MIN);
         
         double lotsToClose = currentLots * closePercent / 100.0;
         // 余計に閉じてしまうのを避けるため、ロットは切り捨てでステップに合わせる
         lotsToClose = MathFloor(lotsToClose / lotStep) * lotStep;
         lotsToClose = NormalizeDouble(lotsToClose, 2);
         if(lotsToClose < minLot) lotsToClose = minLot;
         
         // 三段階運用で中間レベルの場合、次のレベル用に最小ロットを必ず残す
         if(maxLevel >= 3 && newLevel < maxLevel)
         {
            double remainingLots = currentLots - lotsToClose;
            if(remainingLots < minLot)
            {
               lotsToClose = currentLots - minLot;
               lotsToClose = MathFloor(lotsToClose / lotStep) * lotStep;
               lotsToClose = NormalizeDouble(lotsToClose, 2);
               
               if(lotsToClose < minLot)
               {
                  CLogger::Log(LOG_WARN, StringFormat("[PARTIAL_SKIP] Ticket=#%lld: Lots too small (current=%.2f, minLot=%.2f)", 
                        ticket, currentLots, minLot));
                  continue;
               }
            }
         }
         
         if(m_trade.PositionClosePartial(ticket, lotsToClose))
         {
            long identifier = PositionGetInteger(POSITION_IDENTIFIER);
            CLogger::Log(LOG_INFO, StringFormat("[TP_PARTIAL] Level %d: #%lld Lots=%.2f Profit=%.0fpts Identifier=%lld", 
                  newLevel, ticket, lotsToClose, profitPoints, identifier));
            
            m_partialLevels[ticketIdx] = newLevel;

            if(m_cfg.EnablePersistentTpState)
               PersistSaveByTicket(ticket, newLevel);
            
            // Post-close actions
            Sleep(100);
            
            // Find remaining position (same identifier, possibly new ticket after partial close in hedging mode)
            ulong remainingTicket = FindRemainingPositionByIdentifier(identifier);
            if(remainingTicket > 0)
            {
               m_partialLevels[(int)(remainingTicket % 1000)] = newLevel;

               if(m_cfg.EnablePersistentTpState)
                  PersistSaveByTicket(remainingTicket, newLevel);
               
               // Level 1: Move SL to break-even
               if(newLevel == 1 && m_cfg.MoveToBreakEvenAfterLevel1)
               {
                  MoveToBreakEven(remainingTicket, openPrice);
               }
               
               // Level 2 (3-stage mode): Move SL to Level 1 profit
               if(newLevel == 2 && maxLevel >= 3 && m_cfg.MoveSLAfterLevel2)
               {
                  double level1Price;
                  if(posType == POSITION_TYPE_BUY)
                     level1Price = openPrice + m_cfg.PartialClose1Points * point;
                  else
                     level1Price = openPrice - m_cfg.PartialClose1Points * point;
                  
                  MoveSLTo(remainingTicket, level1Price);
               }
            }
         }
      }
   }
   
   //--- Find remaining position after partial close using its unique identifier
   ulong FindRemainingPositionByIdentifier(long identifier)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         
         if(PositionGetInteger(POSITION_MAGIC) == m_cfg.MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == m_cfg.Symbol &&
            PositionGetInteger(POSITION_IDENTIFIER) == identifier)
         {
            return ticket;
         }
      }
      return 0;
   }
   
   //--- Move SL to break-even (entry price)
   void MoveToBreakEven(ulong ticket, double entryPrice)
   {
      if(!PositionSelectByTicket(ticket)) return;
      
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // Only move if current SL is worse than entry
      bool shouldMove = false;
      if(posType == POSITION_TYPE_BUY && (currentSL == 0 || currentSL < entryPrice))
         shouldMove = true;
      else if(posType == POSITION_TYPE_SELL && (currentSL == 0 || currentSL > entryPrice))
         shouldMove = true;
      
      if(shouldMove)
      {
         double newSL = NormalizeDouble(entryPrice, (int)SymbolInfoInteger(m_cfg.Symbol, SYMBOL_DIGITS));
         if(SafePositionModifySL(ticket, newSL, tp, "BE"))
            CLogger::Log(LOG_INFO, StringFormat("[SL_MOVE] Ticket=#%lld: Moved to Break-even @ %.5f", ticket, newSL));
      }
   }
   
   //--- Move SL to specific price
   void MoveSLTo(ulong ticket, double newSL)
   {
      if(!PositionSelectByTicket(ticket)) return;
      
      double tp = PositionGetDouble(POSITION_TP);
      newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(m_cfg.Symbol, SYMBOL_DIGITS));

      if(SafePositionModifySL(ticket, newSL, tp, "L1"))
         CLogger::Log(LOG_INFO, StringFormat("[SL_MOVE] Ticket=#%lld: Moved to Level1 profit @ %.5f", ticket, newSL));
   }
   
   //--- Trailing Stop
   void CheckTrailingStop()
   {
      double point = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_POINT);
      
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_cfg.Symbol) continue;
         
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double currentSL = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         // Calculate trailing parameters
         double trailStart = m_cfg.TrailingStartPoints * point;
         double trailStep = m_cfg.TrailingStepPoints * point;
         
         if(m_cfg.TrailingMode == TRAILING_ATR && m_handleATR != INVALID_HANDLE)
         {
            double atr[];
            ArraySetAsSeries(atr, true);
            if(CopyBuffer(m_handleATR, 0, 0, 1, atr) == 1)
            {
               trailStart = atr[0] * m_cfg.TrailingATRMulti;
               trailStep = atr[0] * 0.5;  // Step = 50% of ATR
            }
         }
         
         double newSL = 0;
         
         if(posType == POSITION_TYPE_BUY)
         {
            double profitDist = currentPrice - openPrice;
            if(profitDist >= trailStart)
            {
               double candidateSL = currentPrice - trailStep;
               if(currentSL == 0 || candidateSL > currentSL + point)
                  newSL = candidateSL;
            }
         }
         else  // SELL
         {
            double profitDist = openPrice - currentPrice;
            if(profitDist >= trailStart)
            {
               double candidateSL = currentPrice + trailStep;
               if(currentSL == 0 || candidateSL < currentSL - point)
                  newSL = candidateSL;
            }
         }
         
         if(newSL > 0)
         {
            newSL = NormalizeDouble(newSL, (int)SymbolInfoInteger(m_cfg.Symbol, SYMBOL_DIGITS));
            if(SafePositionModifySL(ticket, newSL, tp, "TRAIL"))
               CLogger::Log(LOG_INFO, StringFormat("[SL_MOVE] Ticket=#%lld: Trailing @ %.5f", ticket, newSL));
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Continuous SL Sync: Ensure server SL matches expected floor      |
   //| - Runs every tick, respects 5-second cooldown for OrderModify    |
   //| - Uses 'floor logic': FinalSL = max(SyncSL, TrailingSL) for BUY  |
   //+------------------------------------------------------------------+
   void EnsureStopLossSync()
   {
      // Find the single managed position (newest ticket with matching Symbol/Magic)
      ulong managedTicket = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.MagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_cfg.Symbol) continue;
         managedTicket = ticket;
         break;  // Newest ticket (single position policy)
      }

      if(managedTicket == 0)
         return;  // No position to sync

      if(!PositionSelectByTicket(managedTicket))
         return;

      // Get current state
      const double point = SymbolInfoDouble(m_cfg.Symbol, SYMBOL_POINT);
      const int digits = (int)SymbolInfoInteger(m_cfg.Symbol, SYMBOL_DIGITS);
      const double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      const double currentSL = PositionGetDouble(POSITION_SL);
      const double tp = PositionGetDouble(POSITION_TP);
      const ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const int stage = m_partialLevels[(int)(managedTicket % 1000)];

      // Calculate 'Sync SL' (the floor based on stage)
      double syncSL = 0;
      if(stage >= 2 && m_cfg.PartialCloseStages >= 3 && m_cfg.MoveSLAfterLevel2)
      {
         // After Level 2 in 3-stage mode: SL at TP1 level
         syncSL = (posType == POSITION_TYPE_BUY)
                  ? openPrice + m_cfg.PartialClose1Points * point
                  : openPrice - m_cfg.PartialClose1Points * point;
      }
      else if(stage >= 1 && m_cfg.MoveToBreakEvenAfterLevel1)
      {
         // After Level 1: SL at break-even (entry price)
         syncSL = openPrice;
      }

      if(syncSL <= 0)
         return;  // No floor defined for current stage

      syncSL = NormalizeDouble(syncSL, digits);

      // 'Floor logic': Final target SL = max(syncSL, currentSL) for BUY, min for SELL
      // This ensures SL never moves backwards while allowing trailing to advance it
      double targetSL = syncSL;
      if(currentSL > 0)
      {
         if(posType == POSITION_TYPE_BUY)
            targetSL = MathMax(syncSL, currentSL);
         else
            targetSL = MathMin(syncSL, currentSL);
      }
      targetSL = NormalizeDouble(targetSL, digits);

      // Check if sync is needed (Point * 2 tolerance)
      const double tolerance = point * 2.0;
      bool needsSync = false;
      if(posType == POSITION_TYPE_BUY && currentSL < (syncSL - tolerance))
         needsSync = true;
      else if(posType == POSITION_TYPE_SELL && currentSL > (syncSL + tolerance))
         needsSync = true;

      if(!needsSync)
         return;  // Already in sync

      // Cooldown check (5 seconds)
      datetime now = TimeCurrent();
      if((now - m_lastSLSyncAttempt) < 5)
         return;  // Wait for cooldown

      m_lastSLSyncAttempt = now;

      // Execute sync
      if(SafePositionModifySL(managedTicket, targetSL, tp, "SYNC"))
      {
         CLogger::Log(LOG_INFO, StringFormat("[SL_SYNC] Success: Ticket=#%lld Stage=%d SL=%.5f -> %.5f",
               managedTicket, stage, currentSL, targetSL));
      }
      else
      {
         CLogger::Log(LOG_WARN, StringFormat("[SL_SYNC] Failed: Ticket=#%lld Stage=%d TargetSL=%.5f",
               managedTicket, stage, targetSL));
      }
   }
};


#endif
