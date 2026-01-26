"""
戦略プリセット定義

Antigravity Core + 選択的サブモジュールのアーキテクチャ
PullbackEntry (MQL4) が従来テクニカルを担当し、
AI Trader (Python) は金融工学的アプローチに特化する

プリセット:
- antigravity_only: AI予測のみ（フィルターなし）
- antigravity_pullback: AI + プルバック戦略
- antigravity_hedge: ヘッジモード特化
- quantitative_pure: クオンツ純粋戦略
- full: 全モジュール有効（現行互換）
"""

from typing import Dict, Any


# ===== 戦略プリセット定義 =====

STRATEGY_PRESETS: Dict[str, Dict[str, Any]] = {
    
    'antigravity_only': {
        'modules': {
            'antigravity_core': True,
            'antigravity_transformer': True,
            'antigravity_kan': True,
            # すべてのサブモジュールを無効化
            'pullback': False,
            'technical': False,
            'trend': False,
            'chart_patterns': False,
            'false_breakout': False,
            'wave_structure': False,
            'structural': False,
            'volatility': False,
            'gk_volatility': False,
            'candle_patterns': False,
            'momentum': False,
            'mean_reversion': False,
            'volatility_breakout': False,
        },
        'weights': {
            'antigravity_core': 1.0,
        },
        'description': 'AI予測のみ使用（フィルターなし）'
    },
    
    'antigravity_pullback': {
        'modules': {
            'antigravity_core': True,
            'antigravity_transformer': True,
            'antigravity_kan': True,
            'pullback': True,
            'technical': True,
            'trend': True,
            'gk_volatility': True,
            # 無効化
            'chart_patterns': False,
            'false_breakout': False,
            'wave_structure': False,
            'structural': False,
            'volatility': False,  # ATRフィルター無効
            'candle_patterns': False,
            'momentum': False,
            'mean_reversion': False,
            'volatility_breakout': False,
        },
        'weights': {
            'antigravity_core': 0.60,
            'pullback': 0.25,
            'technical': 0.10,
            'trend': 0.05,
        },
        'description': 'AI + プルバック戦略'
    },
    
    'antigravity_hedge': {
        'modules': {
            'antigravity_core': True,
            'antigravity_transformer': True,
            'antigravity_kan': True,
            'false_breakout': True,
            'technical': True,
            'volatility': True,
            'mean_reversion': True,
            # 無効化
            'pullback': False,
            'trend': False,
            'chart_patterns': False,
            'wave_structure': False,
            'structural': False,
            'gk_volatility': True,
            'candle_patterns': False,
            'momentum': False,
            'volatility_breakout': False,
        },
        'weights': {
            'antigravity_core': 0.50,
            'false_breakout': 0.20,
            'technical': 0.15,
            'mean_reversion': 0.15,
        },
        'description': 'ヘッジモード（逆張り特化）'
    },
    
    'quantitative_pure': {
        'modules': {
            # Antigravity Core (AI予測)
            'antigravity_core': True,
            'antigravity_transformer': True,
            'antigravity_kan': True,
            # 金融工学モジュール（シンプル数理）
            'momentum': True,
            'mean_reversion': True,
            'volatility_breakout': True,
            'gk_volatility': True,
            # 除外（従来テクニカル）
            'technical': False,
            'trend': False,
            'candle_patterns': False,
            'chart_patterns': False,
            'pullback': False,
            'false_breakout': False,
            'wave_structure': False,
            'structural': False,
            'volatility': False,
        },
        'weights': {
            'antigravity_core': 0.50,
            'momentum': 0.20,
            'mean_reversion': 0.20,
            'volatility_breakout': 0.10,
        },
        'description': 'クオンツ純粋戦略（従来テクニカル指標なし）'
    },
    
    'full': {
        'modules': {
            'antigravity_core': True,
            'antigravity_transformer': True,
            'antigravity_kan': True,
            'pullback': True,
            'technical': True,
            'trend': True,
            'chart_patterns': True,
            'false_breakout': True,
            'wave_structure': True,
            'structural': True,
            'volatility': True,
            'gk_volatility': True,
            'candle_patterns': True,
            'momentum': True,
            'mean_reversion': True,
            'volatility_breakout': True,
        },
        'weights': {
            # 現行互換の重み（extended_aggregatorのデフォルト）
            'antigravity_core': 0.30,
            'pullback': 0.15,
            'technical': 0.10,
            'trend': 0.08,
            'chart_patterns': 0.08,
            'false_breakout': 0.08,
            'wave_structure': 0.05,
            'structural': 0.03,
            'momentum': 0.05,
            'mean_reversion': 0.05,
            'volatility_breakout': 0.03,
        },
        'description': '全モジュール有効（現行互換）'
    },
}


# ===== 銘柄別ATR閾値（検証済み最適値）=====

SYMBOL_ATR_THRESHOLDS: Dict[str, float] = {
    # === FX通貨ペア ===
    'USDJPY': 7.0,    # 検証済み
    'GBPJPY': 7.0,    # 検証済み
    'AUDJPY': 9.0,    # クロス円
    'EURJPY': 10.0,   # 中間
    'EURUSD': 6.0,    # 低ボラ → 閾値緩和
    'AUDUSD': 6.0,    # 低ボラ → 閾値緩和
    'GBPUSD': 6.0,    # 中間
    
    # === 株価指数 ===
    'JP225': 70.0,    # 検証済み
    'NIKKEI225': 70.0,
    'N225': 70.0,
    'JPN225': 70.0,   # XM
    'US30': 35.0,     # ダウ
    'US500': 5.0,     # S&P500
    'NQ100': 50.0,    # ナスダック
    'US100': 50.0,    # ナスダック (別名)
    'NAS100': 50.0,   # ナスダック (別名)
    'USTEC': 50.0,
}

# デフォルト値
FX_DEFAULT_ATR = 7.0
INDEX_DEFAULT_ATR = 70.0

# 株価指数判定キーワード
INDEX_KEYWORDS = ['JP225', 'N225', 'NIKKEI', 'US30', 'US500', 'NQ100', 
                  'USTEC', 'JPN', 'DAX', 'FTSE', 'UK100', 'GER40']


def get_preset(name: str) -> Dict[str, Any]:
    """
    プリセット設定を取得
    
    Args:
        name: プリセット名
    
    Returns:
        プリセット設定辞書
    """
    return STRATEGY_PRESETS.get(name, STRATEGY_PRESETS['antigravity_pullback'])


def get_atr_threshold(symbol: str) -> float:
    """
    銘柄別ATR閾値を取得
    
    Args:
        symbol: 銘柄名（USDJPY, JP225など）
    
    Returns:
        ATR閾値（pips/points）
    """
    symbol_upper = symbol.upper()
    
    # 完全一致
    if symbol_upper in SYMBOL_ATR_THRESHOLDS:
        return SYMBOL_ATR_THRESHOLDS[symbol_upper]
    
    # 部分一致（JP225を含む場合など）
    for key, value in SYMBOL_ATR_THRESHOLDS.items():
        if key in symbol_upper:
            return value
    
    # 株価指数判定
    if any(kw in symbol_upper for kw in INDEX_KEYWORDS):
        return INDEX_DEFAULT_ATR
    
    # FXデフォルト
    return FX_DEFAULT_ATR


def is_index_symbol(symbol: str) -> bool:
    """
    株価指数かどうかを判定
    
    Args:
        symbol: 銘柄名
    
    Returns:
        True: 株価指数, False: FX
    """
    symbol_upper = symbol.upper()
    return any(kw in symbol_upper for kw in INDEX_KEYWORDS)


def get_enabled_modules(preset_name: str) -> Dict[str, bool]:
    """
    プリセットから有効モジュール辞書を取得
    
    Args:
        preset_name: プリセット名
    
    Returns:
        モジュール名 -> 有効フラグの辞書
    """
    preset = get_preset(preset_name)
    return preset.get('modules', {})


def get_module_weights(preset_name: str) -> Dict[str, float]:
    """
    プリセットからモジュール重みを取得
    
    Args:
        preset_name: プリセット名
    
    Returns:
        モジュール名 -> 重みの辞書
    """
    preset = get_preset(preset_name)
    return preset.get('weights', {})


# ===== テストコード =====
if __name__ == "__main__":
    print("=== Strategy Presets ===")
    for name, preset in STRATEGY_PRESETS.items():
        enabled = sum(1 for v in preset['modules'].values() if v)
        print(f"{name}: {preset['description']} ({enabled} modules enabled)")
    
    print("\n=== ATR Thresholds ===")
    test_symbols = ['USDJPY', 'EURUSD', 'JP225', 'US30', 'UNKNOWN']
    for sym in test_symbols:
        threshold = get_atr_threshold(sym)
        is_idx = is_index_symbol(sym)
        print(f"{sym}: {threshold} {'points' if is_idx else 'pips'}")
