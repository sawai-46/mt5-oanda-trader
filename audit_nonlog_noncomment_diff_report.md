# Non-log & non-comment diff report (mt5-oanda-trader)
Generated: 2025-12-29T19:23:45

## mql4/EA_PullbackEntry.mq4
(none)

## mql4/EA_PullbackEntry_Nikkei225.mq4
-input double Confirmation_Bar_Max_Size = 200.0;   // 遒ｺ隱崎ｶｳ譛螟ｧ繧ｵ繧､繧ｺ(Points縲・=辟｡蛻ｶ髯・
-input double Entry_Buffer_Points = 30.0;            // 繝悶Ξ繧､繧ｯ繝舌ャ繝輔ぃ(Points)
-input double Max_Slippage_Pips = 50.0;              // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(蜀・ 窶ｻ謗ｨ螂ｨ
-input double TakeProfit_Fixed_Points = 500.0;       // 蝗ｺ螳啜P(Points)
+input double StopLoss_Fixed_Points = 150.0;         // 蝗ｺ螳售L・亥・・・+input double TakeProfit_Fixed_Points = 500.0;       // 蝗ｺ螳啜P・亥・・・@@ -201 +201 @@ input double PartialClosePercent1 = 50.0;        // 隨ｬ1蛻ｩ遒ｺ蜑ｲ蜷・%)
+input double TrailingUpdate_Step_Points = 30.0;     // 譖ｴ譁ｰ繧ｹ繝・ャ繝暦ｼ亥・・・@@ -224 +224 @@ input string TL_Lower_Name = "TL_Lower";         // 荳矩剞繝ｩ繧､繝ｳ蜷搾ｼ医メ繝｣
-input double RN_Avoid_Buffer_Points = 50.0;      // 蝗樣∩遽・峇(Points) 窶ｻ繝励Ν繝舌ャ繧ｯ繧ｿ繝・メ譎ゅ・髯､螟・+input double RN_Avoid_Buffer_Points = 50.0;      // 蝗樣∩遽・峇・亥・/萓｡譬ｼ蟾ｮ・・窶ｻ繝励Ν繝舌ャ繧ｯ繧ｿ繝・メ譎ゅ・髯､螟・@@ -262 +262 @@ input bool   Use_Micro_Volatility_Filter = false; // 繝槭う繧ｯ繝ｭ繝懊Λ繝・ぅ繝ｪ
+input double Algo_Price_Clustering = 50.0;      // 萓｡譬ｼ髮・ｸｭ蠎ｦ・亥・/萓｡譬ｼ蟾ｮ・・- 繧｢繝ｫ繧ｴ蜿榊ｿ懃ｯ・峇
-double g_Min_Bar_Range_Points;  // 譌･邨・25迚育畑・・oints蜊倅ｽ搾ｼ・+double g_Min_Bar_Range_Points;  // 蜀・萓｡譬ｼ蜊倅ｽ・@@ -422 +422 @@ int g_Noise_Detection_Period;
-                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_00), 0), "points");
+               " 霍晞屬=", DoubleToString(MathAbs(price - rn_00), 0), "蜀・);
-                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_50), 0), "points");
+               " 霍晞屬=", DoubleToString(MathAbs(price - rn_50), 0), "蜀・);

## mql4/EA_PullbackEntry_USIndex.mq4
-input double Confirmation_Bar_Max_Size = 200.0;   // 遒ｺ隱崎ｶｳ譛螟ｧ繧ｵ繧､繧ｺ(Points縲・=辟｡蛻ｶ髯・
-input double Max_Slippage_Pips = 50.0;              // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(繝峨Ν) 窶ｻ謗ｨ螂ｨ
+input double Min_Channel_Width_Points = 100.0;   // 譛菴弱メ繝｣繝阪Ν蟷・ｼ域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・窶ｻUS Index謗ｨ螂ｨ蛟､
+input double StopLoss_Fixed_Points = 100.0;         // 蝗ｺ螳售L・域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
+input double TrailingUpdate_Step_Points = 20.0;     // 譖ｴ譁ｰ繧ｹ繝・ャ繝暦ｼ域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
-input double RN_Avoid_Buffer_Points = 50.0;      // 蝗樣∩遽・峇(Points) 窶ｻ繝励Ν繝舌ャ繧ｯ繧ｿ繝・メ譎ゅ・髯､螟・+input double RN_Avoid_Buffer_Points = 50.0;      // 蝗樣∩遽・峇・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・窶ｻ繝励Ν繝舌ャ繧ｯ繧ｿ繝・メ譎ゅ・髯､螟・@@ -284 +284 @@ input bool   Use_Micro_Volatility_Filter = false; // 繝槭う繧ｯ繝ｭ繝懊Λ繝・ぅ繝ｪ
+input double Algo_Price_Clustering = 50.0;      // 萓｡譬ｼ髮・ｸｭ蠎ｦ・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・- 繧｢繝ｫ繧ｴ蜿榊ｿ懃ｯ・峇
-double g_Min_Bar_Range_Points;  // 譌･邨・25迚育畑・・oints蜊倅ｽ搾ｼ・+double g_Min_Bar_Range_Points;  // 謖・焚繝昴う繝ｳ繝・萓｡譬ｼ蜊倅ｽ・@@ -448 +448 @@ int g_Noise_Detection_Period;
-   double init_atr_Points = init_atr / 1.0;
+   double init_atr_price = init_atr;
+   double init_atr_mt4pt = (Point > 0.0) ? (init_atr_price / Point) : 0.0;
+   } else {
-   double atr_Points = current_atr / 1.0;
+   double atr_mt4pt = (Point > 0.0) ? (atr_price / Point) : 0.0;
-   if (atr_Points < g_ATR_Threshold_Points) {
+      if (Point > 0.0)
+      else
+   }
+   if (atr_price < g_ATR_Threshold_Points) {
+      if (Point > 0.0)
+      else
-                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_00), 0), "points");
+                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_00), 0), " 謖・焚繝昴う繝ｳ繝・);
-                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_50), 0), "points");
+                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_50), 0), " 謖・焚繝昴う繝ｳ繝・);

## mql4/MT4_AI_Trader_v2_File.mq4
+input int    MaxSlippagePoints = 3;     // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT4 points) 窶ｻ4譯：X縺ｧ縺ｯpips縺ｨ蜷悟､縲・譯：X縺ｧ縺ｯ10 points = 1 pip
-      g_pipValue = 1.0;  // 1 point = 1蜀・繝昴う繝ｳ繝・+      g_pipValue = 1.0;  // 萓｡譬ｼ蟾ｮ縺ｮ陦ｨ遉ｺ蜊倅ｽ・1.0・域欠謨ｰ/CFD蜷代￠縺ｮ謠帷ｮ礼畑・・

## mql4/MT4_AI_Trader_v2_File_JP225.mq4
+input double StopLoss_Fixed_Points = 100.0;   // 蝗ｺ螳售L(蜀・ 窶ｻJP225謗ｨ螂ｨ蛟､
-               ", Target1=", PartialClose1Points, " points");
+            ", Target1=", PartialClose1Points, " MT4 points");
-               " Profit=", DoubleToString(profitPoints, 1), " points");
+            " Profit=", DoubleToString(profitPoints, 1), " MT4 points");

## mql4/MT4_AI_Trader_v2_File_USIndex.mq4
+input double StopLoss_Fixed_Points = 100.0;   // 蝗ｺ螳售L(繝峨Ν) 窶ｻUS Index謗ｨ螂ｨ蛟､
-               ", Target1=", PartialClose1Points, " points");
+            ", Target1=", PartialClose1Points, " MT4 points");
-               " Profit=", DoubleToString(profitPoints, 1), " points");
+            " Profit=", DoubleToString(profitPoints, 1), " MT4 points");

## mql4/MT4_AI_Trader_v2_HTTP.mq4
-input int    MaxSpreadPips = 5;         // 譛螟ｧ繧ｹ繝励Ξ繝・ラ(pips/points) 窶ｻFX=5pips, JP225=10points
-input int    DefaultSLPips = 20;        // 繝・ヵ繧ｩ繝ｫ繝・L(pips)
-input double ATRThresholdPips = 7.0;        // ATR譛菴朱明蛟､・・X:7.0pips, JP225:70point謗ｨ螂ｨ・・+input double ATRThresholdPips = 7.0;        // ATR譛菴朱明蛟､・井ｾ｡譬ｼ蟾ｮ蜊倅ｽ・ FX=7.0pips, JP225=70蜀・岼螳会ｼ・@@ -66 +66 @@ input int    PartialCloseStages = 2;        // 谿ｵ髫取焚(2=莠梧ｮｵ髫・ 3=荳画ｮｵ
+input double StopLoss_Fixed_Pips = 15.0;    // 蝗ｺ螳售L(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ)
-   string unit_name = "pips/points";
+   string unit_name = "price units";
-      string unit = (iClose(NULL, 0, 0) >= 1000) ? "points" : "pips";
+      string unit = (iClose(NULL, 0, 0) >= 1000) ? "price" : "pips";

## mql5/Experts/EA_PullbackEntry_v5_FX.mq5
(none)

## mql5/Experts/EA_PullbackEntry_v5_JP225.mq5
(none)

## mql5/Experts/EA_PullbackEntry_v5_USIndex.mq5
(none)

## mql5/Experts/MT5_AI_Trader_FX.mq5
+input int    InpMaxSlippagePoints = 50;    // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT5 points)
-         " SL=", InpStopLossPips, "pips竊・, g_StopLossPoints, "pts",
-         " TP=", InpTakeProfitPips, "pips竊・, g_TakeProfitPoints, "pts");
+         " SL=", InpStopLossPips, "pips竊・, g_StopLossPoints, "MT5pt",
+         " TP=", InpTakeProfitPips, "pips竊・, g_TakeProfitPoints, "MT5pt");
-               " Profit=", DoubleToString(profitPoints, 1), " points");
+            " Profit=", DoubleToString(profitPoints, 1), " MT5 points");

## mql5/Experts/MT5_AI_Trader_JP225.mq5
+input int    InpMaxSlippagePoints = 50;    // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT5 points)
-         " SL=", InpStopLossYen, "蜀・・", g_StopLossPoints, "pts",
-         " TP=", InpTakeProfitYen, "蜀・・", g_TakeProfitPoints, "pts");
+         " SL=", InpStopLossYen, "蜀・・", g_StopLossPoints, "MT5pt",
+         " TP=", InpTakeProfitYen, "蜀・・", g_TakeProfitPoints, "MT5pt");
-               " Profit=", DoubleToString(profitPoints, 1), " points");
+            " Profit=", DoubleToString(profitPoints, 1), " MT5 points");

## mql5/Experts/MT5_AI_Trader_USIndex.mq5
+input int    InpMaxSlippagePoints = 50;    // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT5 points)
-         " SL=", InpStopLossDollars, "$竊・, g_StopLossPoints, "pts",
-         " TP=", InpTakeProfitDollars, "$竊・, g_TakeProfitPoints, "pts");
+         " SL=", InpStopLossDollars, "$竊・, g_StopLossPoints, "MT5pt",
+         " TP=", InpTakeProfitDollars, "$竊・, g_TakeProfitPoints, "MT5pt");
-               " Profit=", DoubleToString(profitPoints, 1), " points");
+            " Profit=", DoubleToString(profitPoints, 1), " MT5 points");

