# Non-log diff report (mt5-oanda-trader)
Generated: 2025-12-29T19:17:25

## mql4/EA_PullbackEntry.mq4
-input int    Max_Slippage_Points = 0;            // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(points) 窶ｻ莠呈鋤逕ｨ縲・=pips謠帷ｮ励ｒ菴ｿ逕ｨ
-input bool   Use_Slippage_Pips_Conversion = false; // 繧ｹ繝ｪ繝・・繝ｼ繧ｸ縺ｮpips竊恥oints謠帷ｮ励ｒ譛牙柑蛹厄ｼ・rue謗ｨ螂ｨ・俄ｻ莠呈鋤縺ｮ縺溘ａ譌｢螳喃alse
+input int    Max_Slippage_Points = 0;            // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT4 points) 窶ｻ莠呈鋤逕ｨ縲・=pips謠帷ｮ励ｒ菴ｿ逕ｨ
+input bool   Use_Slippage_Pips_Conversion = false; // 繧ｹ繝ｪ繝・・繝ｼ繧ｸ縺ｮpips竊樽T4 points謠帷ｮ励ｒ譛牙柑蛹厄ｼ・rue謗ｨ螂ｨ・俄ｻ莠呈鋤縺ｮ縺溘ａ譌｢螳喃alse

## mql4/EA_PullbackEntry_Nikkei225.mq4
-input double Confirmation_Bar_Min_Size = 50.0;    // 遒ｺ隱崎ｶｳ譛蟆上し繧､繧ｺ(Points)
-input double Confirmation_Bar_Max_Size = 200.0;   // 遒ｺ隱崎ｶｳ譛螟ｧ繧ｵ繧､繧ｺ(Points縲・=辟｡蛻ｶ髯・
+input double Confirmation_Bar_Min_Size = 50.0;    // 遒ｺ隱崎ｶｳ譛蟆上し繧､繧ｺ・亥・/萓｡譬ｼ蟾ｮ・・+input double Confirmation_Bar_Max_Size = 200.0;   // 遒ｺ隱崎ｶｳ譛螟ｧ繧ｵ繧､繧ｺ・亥・/萓｡譬ｼ蟾ｮ縲・=辟｡蛻ｶ髯撰ｼ・@@ -169,4 +169,4 @@ input int    Entry_Confirmations = 2;            // 蠢・ｦ√↑陬懷勧譚｡莉ｶ謨ｰ(0-6
-input double Entry_Buffer_Points = 30.0;            // 繝悶Ξ繧､繧ｯ繝舌ャ繝輔ぃ(Points)
-input double Max_Slippage_Pips = 50.0;              // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(蜀・ 窶ｻ謗ｨ螂ｨ
-input int    Max_Slippage_Points = 0;               // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(Points) 窶ｻ莠呈鋤逕ｨ縲・=Pips菴ｿ逕ｨ
-input double Max_Spread_Points = 30.0;             // 譛螟ｧ繧ｹ繝励Ξ繝・ラ(蜀・ 窶ｻ騾壼ｸｸ5-10蜀・+input double Entry_Buffer_Points = 30.0;            // 繝悶Ξ繧､繧ｯ繝舌ャ繝輔ぃ・亥・/萓｡譬ｼ蟾ｮ・・+input double Max_Slippage_Pips = 50.0;              // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ・亥・/萓｡譬ｼ蟾ｮ・・窶ｻ謗ｨ螂ｨ
+input int    Max_Slippage_Points = 0;               // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ・・T4 points・・窶ｻ莠呈鋤逕ｨ縲・=Max_Slippage_Pips菴ｿ逕ｨ
+input double Max_Spread_Points = 30.0;             // 譛螟ｧ繧ｹ繝励Ξ繝・ラ・亥・/萓｡譬ｼ蟾ｮ・・窶ｻ騾壼ｸｸ5-10蜀・@@ -176 +176 @@ input int    ATR_Period = 14;                    // ATR譛滄俣
-input double ATR_Threshold_Points = 70.0;        // ATR譛菴主､(Points) 窶ｻ螳滄°逕ｨ譛驕ｩ蛟､
+input double ATR_Threshold_Points = 70.0;        // ATR譛菴主､・亥・/萓｡譬ｼ蟾ｮ・・窶ｻ螳滄°逕ｨ譛驕ｩ蛟､
-input double TakeProfit_Fixed_Points = 500.0;       // 蝗ｺ螳啜P(Points)
+input double StopLoss_Fixed_Points = 150.0;         // 蝗ｺ螳售L・亥・・・+input double TakeProfit_Fixed_Points = 500.0;       // 蝗ｺ螳啜P・亥・・・@@ -201 +201 @@ input double PartialClosePercent1 = 50.0;        // 隨ｬ1蛻ｩ遒ｺ蜑ｲ蜷・%)
-input double PartialCloseLevel1_Points = 150.0;     // 隨ｬ1蛻ｩ遒ｺ繝ｬ繝吶Ν(Points)
+input double PartialCloseLevel1_Points = 150.0;     // 隨ｬ1蛻ｩ遒ｺ繝ｬ繝吶Ν・亥・・・@@ -203 +203 @@ input double PartialClosePercent2 = 50.0;        // 隨ｬ2蛻ｩ遒ｺ蜑ｲ蜷・%)
-input double PartialCloseLevel2_Points = 500.0;     // 隨ｬ2蛻ｩ遒ｺ繝ｬ繝吶Ν(Points)
+input double PartialCloseLevel2_Points = 500.0;     // 隨ｬ2蛻ｩ遒ｺ繝ｬ繝吶Ν・亥・・・@@ -205 +205 @@ input double PartialClosePercent3 = 0.0;         // 隨ｬ3蛻ｩ遒ｺ蜑ｲ蜷・%)
-input double PartialCloseLevel3_Points = 450.0;     // 隨ｬ3蛻ｩ遒ｺ繝ｬ繝吶Ν(Points)
+input double PartialCloseLevel3_Points = 450.0;     // 隨ｬ3蛻ｩ遒ｺ繝ｬ繝吶Ν・亥・・・@@ -210 +210 @@ input bool   MoveToTP1OnPartial2 = false;        // 隨ｬ2蛻ｩ遒ｺ縺ｧSL繧堤ｬｬ1蛻ｩ遒ｺ
-input double BreakevenOffset_Points = 50.0;         // 蟒ｺ蛟､繧ｪ繝輔そ繝・ヨ(Points)
+input double BreakevenOffset_Points = 50.0;         // 蟒ｺ蛟､繧ｪ繝輔そ繝・ヨ・亥・・・@@ -218 +218 @@ input int    Trailing_ATR_Period = 14;           // 繝医Ξ繝ｼ繝ｪ繝ｳ繧ｰ逕ｨATR譛・-input double TrailingUpdate_Step_Points = 30.0;     // 譖ｴ譁ｰ繧ｹ繝・ャ繝・Points)
+input double TrailingUpdate_Step_Points = 30.0;     // 譖ｴ譁ｰ繧ｹ繝・ャ繝暦ｼ亥・・・@@ -224 +224 @@ input string TL_Lower_Name = "TL_Lower";         // 荳矩剞繝ｩ繧､繝ｳ蜷搾ｼ医メ繝｣
-input double TL_Touch_Buffer_Points = 20.0;      // 繧ｿ繝・メ蛻､螳壹ヰ繝・ヵ繧｡(Points)
+input double TL_Touch_Buffer_Points = 20.0;      // 繧ｿ繝・メ蛻､螳壹ヰ繝・ヵ繧｡・亥・/萓｡譬ｼ蟾ｮ・・@@ -241 +241 @@ input bool   RN_Use_50_Line = true;              // 250/750繝ｩ繧､繝ｳ菴ｿ逕ｨ・医が
-input double RN_Touch_Buffer_Points = 30.0;      // 繧ｿ繝・メ蛻､螳壹ヰ繝・ヵ繧｡(Points)
+input double RN_Touch_Buffer_Points = 30.0;      // 繧ｿ繝・メ蛻､螳壹ヰ繝・ヵ繧｡・亥・/萓｡譬ｼ蟾ｮ・・@@ -251 +251 @@ input bool   RN_Avoid_Entry_Near = false;        // 1000/500莉倩ｿ代〒縺ｮ繧ｨ繝ｳ
-input double RN_Avoid_Buffer_Points = 50.0;      // 蝗樣∩遽・峇(Points) 窶ｻ繝励Ν繝舌ャ繧ｯ繧ｿ繝・メ譎ゅ・髯､螟・+input double RN_Avoid_Buffer_Points = 50.0;      // 蝗樣∩遽・峇・亥・/萓｡譬ｼ蟾ｮ・・窶ｻ繝励Ν繝舌ャ繧ｯ繧ｿ繝・メ譎ゅ・髯､螟・@@ -262 +262 @@ input bool   Use_Micro_Volatility_Filter = false; // 繝槭う繧ｯ繝ｭ繝懊Λ繝・ぅ繝ｪ
-input double Min_Bar_Range_Pips = 30.0;          // 譛蟆上ヰ繝ｼ繧ｵ繧､繧ｺ(Points) - 縺薙ｌ譛ｪ貅縺ｯ繝弱う繧ｺ
+input double Min_Bar_Range_Pips = 30.0;          // 譛蟆上ヰ繝ｼ繧ｵ繧､繧ｺ・亥・/萓｡譬ｼ蟾ｮ・・- 縺薙ｌ譛ｪ貅縺ｯ繝弱う繧ｺ
+input double Algo_Price_Clustering = 50.0;      // 萓｡譬ｼ髮・ｸｭ蠎ｦ・亥・/萓｡譬ｼ蟾ｮ・・- 繧｢繝ｫ繧ｴ蜿榊ｿ懃ｯ・峇
-double g_Min_Bar_Range_Points;  // 譌･邨・25迚育畑・・oints蜊倅ｽ搾ｼ・+double g_Min_Bar_Range_Points;  // 蜀・萓｡譬ｼ蜊倅ｽ・@@ -422 +422 @@ int g_Noise_Detection_Period;
-      double channel_width = (highest - lowest) / 1.0; // Points
+      double channel_width = (highest - lowest) / 1.0; // 蜀・萓｡譬ｼ蜊倅ｽ・@@ -773 +773 @@ void CheckForPullbackEntry()
-                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_00), 0), "points");
+               " 霍晞屬=", DoubleToString(MathAbs(price - rn_00), 0), "蜀・);
-                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_50), 0), "points");
+               " 霍晞屬=", DoubleToString(MathAbs(price - rn_50), 0), "蜀・);

## mql4/EA_PullbackEntry_USIndex.mq4
-input double Confirmation_Bar_Min_Size = 50.0;    // 遒ｺ隱崎ｶｳ譛蟆上し繧､繧ｺ(Points)
-input double Confirmation_Bar_Max_Size = 200.0;   // 遒ｺ隱崎ｶｳ譛螟ｧ繧ｵ繧､繧ｺ(Points縲・=辟｡蛻ｶ髯・
+input double Confirmation_Bar_Min_Size = 50.0;    // 遒ｺ隱崎ｶｳ譛蟆上し繧､繧ｺ・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・+input double Confirmation_Bar_Max_Size = 200.0;   // 遒ｺ隱崎ｶｳ譛螟ｧ繧ｵ繧､繧ｺ・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ縲・=辟｡蛻ｶ髯撰ｼ・@@ -191,4 +191,4 @@ input int    Entry_Confirmations = 2;            // 蠢・ｦ√↑陬懷勧譚｡莉ｶ謨ｰ(0-6
-input double Entry_Buffer_Points = 20.0;            // 繝悶Ξ繧､繧ｯ繝舌ャ繝輔ぃ(Points)
-input double Max_Slippage_Pips = 50.0;              // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(繝峨Ν) 窶ｻ謗ｨ螂ｨ
-input int    Max_Slippage_Points = 0;               // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(Points) 窶ｻ莠呈鋤逕ｨ縲・=Pips菴ｿ逕ｨ
-input double Max_Spread_Points = 20.0;             // 譛螟ｧ繧ｹ繝励Ξ繝・ラ(繝峨Ν) 窶ｻ騾壼ｸｸ5-10繝峨Ν
+input double Entry_Buffer_Points = 20.0;            // 繝悶Ξ繧､繧ｯ繝舌ャ繝輔ぃ・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・+input double Max_Slippage_Pips = 50.0;              // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・窶ｻ謗ｨ螂ｨ
+input int    Max_Slippage_Points = 0;               // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ・・T4 points・・窶ｻ莠呈鋤逕ｨ縲・=Max_Slippage_Pips菴ｿ逕ｨ
+input double Max_Spread_Points = 20.0;             // 譛螟ｧ繧ｹ繝励Ξ繝・ラ・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・窶ｻ騾壼ｸｸ5-10謖・焚繝昴う繝ｳ繝育ｨ句ｺｦ
-input double ATR_Threshold_Points = 30.0;        // ATR譛菴主､(Points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double ATR_Threshold_Points = 30.0;        // ATR譛菴主､・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・窶ｻUS Index謗ｨ螂ｨ蛟､
+input double Min_Channel_Width_Points = 100.0;   // 譛菴弱メ繝｣繝阪Ν蟷・ｼ域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・窶ｻUS Index謗ｨ螂ｨ蛟､
-input double TakeProfit_Fixed_Points = 200.0;       // 蝗ｺ螳啜P(Points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double StopLoss_Fixed_Points = 100.0;         // 蝗ｺ螳售L・域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
+input double TakeProfit_Fixed_Points = 200.0;       // 蝗ｺ螳啜P・域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
-input double PartialCloseLevel1_Points = 50.0;      // 隨ｬ1蛻ｩ遒ｺ繝ｬ繝吶Ν(Points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double PartialCloseLevel1_Points = 50.0;      // 隨ｬ1蛻ｩ遒ｺ繝ｬ繝吶Ν・域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
-input double PartialCloseLevel2_Points = 100.0;     // 隨ｬ2蛻ｩ遒ｺ繝ｬ繝吶Ν(Points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double PartialCloseLevel2_Points = 100.0;     // 隨ｬ2蛻ｩ遒ｺ繝ｬ繝吶Ν・域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
-input double PartialCloseLevel3_Points = 150.0;     // 隨ｬ3蛻ｩ遒ｺ繝ｬ繝吶Ν(Points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double PartialCloseLevel3_Points = 150.0;     // 隨ｬ3蛻ｩ遒ｺ繝ｬ繝吶Ν・域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
-input double BreakevenOffset_Points = 20.0;         // 蟒ｺ蛟､繧ｪ繝輔そ繝・ヨ(Points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double BreakevenOffset_Points = 20.0;         // 蟒ｺ蛟､繧ｪ繝輔そ繝・ヨ・域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
+input double TrailingUpdate_Step_Points = 20.0;     // 譖ｴ譁ｰ繧ｹ繝・ャ繝暦ｼ域欠謨ｰ繝昴う繝ｳ繝茨ｼ・窶ｻUS Index謗ｨ螂ｨ蛟､
-input double TL_Touch_Buffer_Points = 20.0;      // 繧ｿ繝・メ蛻､螳壹ヰ繝・ヵ繧｡(Points)
+input double TL_Touch_Buffer_Points = 20.0;      // 繧ｿ繝・メ蛻､螳壹ヰ繝・ヵ繧｡・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・@@ -263 +263 @@ input bool   RN_Use_50_Line = true;              // 250/750繝ｩ繧､繝ｳ菴ｿ逕ｨ・医が
-input double RN_Touch_Buffer_Points = 30.0;      // 繧ｿ繝・メ蛻､螳壹ヰ繝・ヵ繧｡(Points)
+input double RN_Touch_Buffer_Points = 30.0;      // 繧ｿ繝・メ蛻､螳壹ヰ繝・ヵ繧｡・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・@@ -273 +273 @@ input bool   RN_Avoid_Entry_Near = false;        // 1000/500莉倩ｿ代〒縺ｮ繧ｨ繝ｳ
-input double RN_Avoid_Buffer_Points = 50.0;      // 蝗樣∩遽・峇(Points) 窶ｻ繝励Ν繝舌ャ繧ｯ繧ｿ繝・メ譎ゅ・髯､螟・+input double RN_Avoid_Buffer_Points = 50.0;      // 蝗樣∩遽・峇・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・窶ｻ繝励Ν繝舌ャ繧ｯ繧ｿ繝・メ譎ゅ・髯､螟・@@ -284 +284 @@ input bool   Use_Micro_Volatility_Filter = false; // 繝槭う繧ｯ繝ｭ繝懊Λ繝・ぅ繝ｪ
-input double Min_Bar_Range_Pips = 30.0;          // 譛蟆上ヰ繝ｼ繧ｵ繧､繧ｺ(Points) - 縺薙ｌ譛ｪ貅縺ｯ繝弱う繧ｺ
+input double Min_Bar_Range_Pips = 30.0;          // 譛蟆上ヰ繝ｼ繧ｵ繧､繧ｺ・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・- 縺薙ｌ譛ｪ貅縺ｯ繝弱う繧ｺ
+input double Algo_Price_Clustering = 50.0;      // 萓｡譬ｼ髮・ｸｭ蠎ｦ・域欠謨ｰ繝昴う繝ｳ繝・萓｡譬ｼ蟾ｮ・・- 繧｢繝ｫ繧ｴ蜿榊ｿ懃ｯ・峇
-double g_Min_Bar_Range_Points;  // 譌･邨・25迚育畑・・oints蜊倅ｽ搾ｼ・+double g_Min_Bar_Range_Points;  // 謖・焚繝昴う繝ｳ繝・萓｡譬ｼ蜊倅ｽ・@@ -448 +448 @@ int g_Noise_Detection_Period;
-   double init_atr_Points = init_atr / 1.0;
+   double init_atr_price = init_atr;
+   double init_atr_mt4pt = (Point > 0.0) ? (init_atr_price / Point) : 0.0;
+   } else {
+   }
-   double atr_Points = current_atr / 1.0;
+   double atr_mt4pt = (Point > 0.0) ? (atr_price / Point) : 0.0;
-   }
-   if (atr_Points < g_ATR_Threshold_Points) {
+      if (Point > 0.0)
+      else
+   }
+   if (atr_price < g_ATR_Threshold_Points) {
+      if (Point > 0.0)
+      else
-      double channel_width = (highest - lowest) / 1.0; // Points
+      double channel_width = (highest - lowest) / 1.0; // 謖・焚繝昴う繝ｳ繝・萓｡譬ｼ蜊倅ｽ・@@ -902 +916 @@ void CheckForPullbackEntry()
-                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_00), 0), "points");
+                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_00), 0), " 謖・焚繝昴う繝ｳ繝・);
-                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_50), 0), "points");
+                  " 霍晞屬=", DoubleToString(MathAbs(price - rn_50), 0), " 謖・焚繝昴う繝ｳ繝・);
-         g_TrailingStop_ATR_Multi = 2.0;              // ATR 2.0蛟搾ｼ医ヰ繝ｩ繝ｳ繧ｹ蝙九・蝗ｺ螳・2Points・・-         g_TrailingUpdate_Step_Points = 30.0;            // 譖ｴ譁ｰ繧ｹ繝・ャ繝・Points
+         g_TrailingStop_ATR_Multi = 2.0;              // ATR 2.0蛟搾ｼ医ヰ繝ｩ繝ｳ繧ｹ蝙九・蝗ｺ螳・2謖・焚繝昴う繝ｳ繝茨ｼ・+         g_TrailingUpdate_Step_Points = 30.0;            // 譖ｴ譁ｰ繧ｹ繝・ャ繝・謖・焚繝昴う繝ｳ繝・@@ -2662,2 +2676,2 @@ void ApplyStrategyPreset()

## mql4/MT4_AI_Trader_v2_File.mq4
+input int    MaxSlippagePoints = 3;     // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT4 points) 窶ｻ4譯：X縺ｧ縺ｯpips縺ｨ蜷悟､縲・譯：X縺ｧ縺ｯ10 points = 1 pip
-input int    DefaultSLPoints = 20;      // 繝・ヵ繧ｩ繝ｫ繝・L(points) 窶ｻFX謗ｨ螂ｨ蛟､
-input int    DefaultTPPoints = 40;      // 繝・ヵ繧ｩ繝ｫ繝・P(points) 窶ｻFX謗ｨ螂ｨ蛟､
+input int    DefaultSLPoints = 20;      // 繝・ヵ繧ｩ繝ｫ繝・L(MT4 points) 窶ｻ4譯：X縺ｧ縺ｯpips縺ｨ蜷悟､縲・譯：X縺ｧ縺ｯ10 points = 1 pip
+input int    DefaultTPPoints = 40;      // 繝・ヵ繧ｩ繝ｫ繝・P(MT4 points) 窶ｻ4譯：X縺ｧ縺ｯpips縺ｨ蜷悟､縲・譯：X縺ｧ縺ｯ10 points = 1 pip
-      g_pipValue = 1.0;  // 1 point = 1蜀・繝昴う繝ｳ繝・+      g_pipValue = 1.0;  // 萓｡譬ｼ蟾ｮ縺ｮ陦ｨ遉ｺ蜊倅ｽ・1.0・域欠謨ｰ/CFD蜷代￠縺ｮ謠帷ｮ礼畑・・

## mql4/MT4_AI_Trader_v2_File_JP225.mq4
-input int    MaxSlippagePoints = 0;       // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(points) 窶ｻ莠呈鋤逕ｨ縲・=SlippagePips菴ｿ逕ｨ
+input int    MaxSlippagePoints = 0;       // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT4 points) 窶ｻ莠呈鋤逕ｨ縲・=SlippagePips菴ｿ逕ｨ
-input int    DefaultSLPoints = 200;     // 繝・ヵ繧ｩ繝ｫ繝・L(points) 窶ｻJP225謗ｨ螂ｨ蛟､
-input int    DefaultTPPoints = 400;     // 繝・ヵ繧ｩ繝ｫ繝・P(points) 窶ｻJP225謗ｨ螂ｨ蛟､
+input int    DefaultSLPoints = 200;     // 繝・ヵ繧ｩ繝ｫ繝・L(蜀・ 窶ｻJP225謗ｨ螂ｨ蛟､
+input int    DefaultTPPoints = 400;     // 繝・ヵ繧ｩ繝ｫ繝・P(蜀・ 窶ｻJP225謗ｨ螂ｨ蛟､
-input double PartialClose1Points = 100.0;   // 1谿ｵ髫守岼(points) 窶ｻJP225謗ｨ螂ｨ蛟､
+input double PartialClose1Points = 100.0;   // 1谿ｵ髫守岼(MT4 points) 窶ｻ萓｡譬ｼ蟾ｮ(蜀・=MT4points*Point
-input double PartialClose2Points = 200.0;   // 2谿ｵ髫守岼(points) 窶ｻJP225謗ｨ螂ｨ蛟､
+input double PartialClose2Points = 200.0;   // 2谿ｵ髫守岼(MT4 points) 窶ｻ萓｡譬ｼ蟾ｮ(蜀・=MT4points*Point
-input double PartialClose3Points = 300.0;   // 3谿ｵ髫守岼(points) 窶ｻJP225謗ｨ螂ｨ蛟､
+input double PartialClose3Points = 300.0;   // 3谿ｵ髫守岼(MT4 points) 窶ｻ萓｡譬ｼ蟾ｮ(蜀・=MT4points*Point
-input double TakeProfit_Fixed_Points = 200.0; // 蝗ｺ螳啜P(points) 窶ｻJP225謗ｨ螂ｨ蛟､
+input double StopLoss_Fixed_Points = 100.0;   // 蝗ｺ螳售L(蜀・ 窶ｻJP225謗ｨ螂ｨ蛟､
+input double TakeProfit_Fixed_Points = 200.0; // 蝗ｺ螳啜P(蜀・ 窶ｻJP225謗ｨ螂ｨ蛟､
-               ", Target1=", PartialClose1Points, " points");
+            ", Target1=", PartialClose1Points, " MT4 points");
-               " Profit=", DoubleToString(profitPoints, 1), " points");
+            " Profit=", DoubleToString(profitPoints, 1), " MT4 points");

## mql4/MT4_AI_Trader_v2_File_USIndex.mq4
-input int    MaxSlippagePoints = 0;       // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(points) 窶ｻ莠呈鋤逕ｨ縲・=SlippagePips菴ｿ逕ｨ
+input int    MaxSlippagePoints = 0;       // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT4 points) 窶ｻ莠呈鋤逕ｨ縲・=SlippagePips菴ｿ逕ｨ
-input double PartialClose1Points = 50.0;    // 1谿ｵ髫守岼(points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double PartialClose1Points = 50.0;    // 1谿ｵ髫守岼(MT4 points) 窶ｻ萓｡譬ｼ蟾ｮ($)=MT4points*Point
-input double PartialClose2Points = 100.0;   // 2谿ｵ髫守岼(points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double PartialClose2Points = 100.0;   // 2谿ｵ髫守岼(MT4 points) 窶ｻ萓｡譬ｼ蟾ｮ($)=MT4points*Point
-input double PartialClose3Points = 150.0;   // 3谿ｵ髫守岼(points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double PartialClose3Points = 150.0;   // 3谿ｵ髫守岼(MT4 points) 窶ｻ萓｡譬ｼ蟾ｮ($)=MT4points*Point
-input double TakeProfit_Fixed_Points = 200.0; // 蝗ｺ螳啜P(points) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double StopLoss_Fixed_Points = 100.0;   // 蝗ｺ螳售L(繝峨Ν) 窶ｻUS Index謗ｨ螂ｨ蛟､
+input double TakeProfit_Fixed_Points = 200.0; // 蝗ｺ螳啜P(繝峨Ν) 窶ｻUS Index謗ｨ螂ｨ蛟､
-
-               ", Target1=", PartialClose1Points, " points");
+            ", Target1=", PartialClose1Points, " MT4 points");
-               " Profit=", DoubleToString(profitPoints, 1), " points");
+            " Profit=", DoubleToString(profitPoints, 1), " MT4 points");

## mql4/MT4_AI_Trader_v2_HTTP.mq4
-input int    MaxSlippagePips = 50;       // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(pips/points) 窶ｻFX=3pips, JP225=50points
-input int    MaxSpreadPips = 5;         // 譛螟ｧ繧ｹ繝励Ξ繝・ラ(pips/points) 窶ｻFX=5pips, JP225=10points
-input int    DefaultSLPips = 20;        // 繝・ヵ繧ｩ繝ｫ繝・L(pips)
-input int    DefaultTPPips = 40;        // 繝・ヵ繧ｩ繝ｫ繝・P(pips)
+input int    MaxSlippagePips = 50;       // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ) 窶ｻFX=3pips, JP225=50蜀・岼螳・+input int    MaxSpreadPips = 5;         // 譛螟ｧ繧ｹ繝励Ξ繝・ラ(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ) 窶ｻFX=5pips, JP225=10蜀・岼螳・+input int    DefaultSLPips = 20;        // 繝・ヵ繧ｩ繝ｫ繝・L(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ)
+input int    DefaultTPPips = 40;        // 繝・ヵ繧ｩ繝ｫ繝・P(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ)
-input double ATRThresholdPips = 7.0;        // ATR譛菴朱明蛟､・・X:7.0pips, JP225:70point謗ｨ螂ｨ・・+input double ATRThresholdPips = 7.0;        // ATR譛菴朱明蛟､・井ｾ｡譬ｼ蟾ｮ蜊倅ｽ・ FX=7.0pips, JP225=70蜀・岼螳会ｼ・@@ -66 +66 @@ input int    PartialCloseStages = 2;        // 谿ｵ髫取焚(2=莠梧ｮｵ髫・ 3=荳画ｮｵ
-input double PartialClose1Pips = 15.0;      // 1谿ｵ髫守岼(pips/points)
+input double PartialClose1Pips = 15.0;      // 1谿ｵ髫守岼(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ)
-input double PartialClose2Pips = 30.0;      // 2谿ｵ髫守岼(pips/points)
+input double PartialClose2Pips = 30.0;      // 2谿ｵ髫守岼(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ)
-input double PartialClose3Pips = 45.0;      // 3谿ｵ髫守岼(pips/points) 窶ｻ荳画ｮｵ髫取凾縺ｮ縺ｿ
+input double PartialClose3Pips = 45.0;      // 3谿ｵ髫守岼(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ) 窶ｻ荳画ｮｵ髫取凾縺ｮ縺ｿ
-input double TakeProfit_Fixed_Pips = 30.0;  // 蝗ｺ螳啜P(pips)
+input double StopLoss_Fixed_Pips = 15.0;    // 蝗ｺ螳售L(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ)
+input double TakeProfit_Fixed_Pips = 30.0;  // 蝗ｺ螳啜P(萓｡譬ｼ蟾ｮ蜊倅ｽ・ FX=pips / 謖・焚=萓｡譬ｼ蟾ｮ)
-   string unit_name = "pips/points";
+   string unit_name = "price units";
-      string unit = (iClose(NULL, 0, 0) >= 1000) ? "points" : "pips";
+      string unit = (iClose(NULL, 0, 0) >= 1000) ? "price" : "pips";

## mql5/Experts/EA_PullbackEntry_v5_FX.mq5
-input int    InpDeviationPoints = 50;        // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(points)
+input int    InpDeviationPoints = 50;        // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT5 points)

## mql5/Experts/EA_PullbackEntry_v5_JP225.mq5
-input int    InpDeviationPoints = 50;        // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(points)
+input int    InpDeviationPoints = 50;        // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT5 points)

## mql5/Experts/EA_PullbackEntry_v5_USIndex.mq5
-input int    InpDeviationPoints = 50;        // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(points)
+input int    InpDeviationPoints = 50;        // 譛螟ｧ繧ｹ繝ｪ繝・・繝ｼ繧ｸ(MT5 points)

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
-   g_MaxSpreadPoints = InpMaxSpreadYen;       // 蜀・= points
+   g_MaxSpreadPoints = InpMaxSpreadYen;       // 蜀・ｼ井ｾ｡譬ｼ蟾ｮ・俄沿 MT5 points
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

