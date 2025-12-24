"""
建玉分析モジュール

オプション市場の建玉（Open Interest）データから
重要な価格帯（Support/Resistance）を特定します。

対象銘柄:
- FX: USDJPY, EURUSD, AUDUSD, EURJPY, AUDJPY
- 株価指数: JP225, US30, US500, NQ100

データソース:
- ETFオプション（SPY, QQQ, DIA）から株価指数の建玉を分析
- FX通貨は関連ETF/先物の代替データを使用
"""

import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum
import json
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass
class KeyLevel:
    """重要価格帯"""
    price: float
    level_type: str      # "support", "resistance", "pivot"
    strength: float      # 0.0-1.0 (建玉の相対的な大きさ)
    source: str          # "put_wall", "call_wall", "max_pain", etc.
    open_interest: int   # 実際の建玉数


@dataclass
class OpenInterestAnalysis:
    """建玉分析結果"""
    symbol: str
    underlying_symbol: str  # 実際に分析したティッカー（ETF等）
    
    key_levels: List[KeyLevel]
    max_pain: Optional[float]  # オプション売り手の最大利益価格
    put_wall: Optional[float]  # 最大プット建玉価格（サポート）
    call_wall: Optional[float] # 最大コール建玉価格（レジスタンス）
    
    total_put_oi: int
    total_call_oi: int
    put_call_ratio: float
    
    timestamp: datetime
    expiration_date: str  # 分析した満期日


class OpenInterestAnalyzer:
    """
    建玉分析クラス
    
    オプションの建玉データから重要な価格帯を特定し、
    サポート/レジスタンスレベルとして提供します。
    """
    
    # MT4シンボル → 分析用ETF/ティッカーのマッピング
    SYMBOL_MAPPING = {
        # 株価指数
        "US500": "SPY",     # S&P 500 → SPDR S&P 500 ETF
        "NQ100": "QQQ",     # NASDAQ 100 → Invesco QQQ
        "US30": "DIA",      # Dow Jones → SPDR Dow Jones ETF
        "JP225": "EWJ",     # 日経225 → iShares MSCI Japan ETF (代替)
        
        # FX通貨（関連ETF/先物）
        "USDJPY": "FXY",    # 円ETF（逆相関として使用）
        "EURUSD": "FXE",    # ユーロETF
        "AUDUSD": "FXA",    # 豪ドルETF
        "EURJPY": "FXE",    # ユーロETF（EUR側を分析）
        "AUDJPY": "FXA",    # 豪ドルETF（AUD側を分析）
    }
    
    # ETF価格 → MT4価格への変換係数（概算）
    # これは建玉の「強さ」を見るためのもので、正確な価格変換は行わない
    PRICE_MULTIPLIERS = {
        "US500": 10.0,      # SPY ~500 -> SPX ~5000
        "NQ100": 40.0,      # QQQ ~500 -> NDX ~20000
        "US30": 100.0,      # DIA ~400 -> DJI ~40000
        "JP225": 1000.0,    # EWJ ~70 -> NKY ~35000
        "USDJPY": 1.0,      # FXYは参考値のみ
        "EURUSD": 1.0,
        "AUDUSD": 1.0,
        "EURJPY": 1.0,
        "AUDJPY": 1.0,
    }
    
    def __init__(self, cache_dir: Optional[Path] = None, cache_hours: int = 24):
        """
        初期化
        
        Args:
            cache_dir: キャッシュディレクトリ
            cache_hours: キャッシュ有効時間
        """
        self.cache_dir = cache_dir or Path(__file__).parent.parent / "data" / "open_interest"
        self.cache_hours = cache_hours
        self._yf = None
    
    def _get_yfinance(self):
        """yfinance の遅延インポート"""
        if self._yf is None:
            try:
                import yfinance as yf
                self._yf = yf
            except ImportError:
                logger.error("yfinance がインストールされていません。")
                raise
        return self._yf
    
    def _get_cache_path(self, symbol: str) -> Path:
        """キャッシュファイルパスを取得"""
        return self.cache_dir / f"{symbol}_oi.json"
    
    def _load_cache(self, symbol: str) -> Optional[OpenInterestAnalysis]:
        """キャッシュからデータを読み込み"""
        cache_path = self._get_cache_path(symbol)
        if not cache_path.exists():
            return None
        
        try:
            with open(cache_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            timestamp = datetime.fromisoformat(data['timestamp'])
            if datetime.now() - timestamp > timedelta(hours=self.cache_hours):
                return None
            
            key_levels = [
                KeyLevel(
                    price=kl['price'],
                    level_type=kl['level_type'],
                    strength=kl['strength'],
                    source=kl['source'],
                    open_interest=kl['open_interest']
                )
                for kl in data['key_levels']
            ]
            
            return OpenInterestAnalysis(
                symbol=data['symbol'],
                underlying_symbol=data['underlying_symbol'],
                key_levels=key_levels,
                max_pain=data.get('max_pain'),
                put_wall=data.get('put_wall'),
                call_wall=data.get('call_wall'),
                total_put_oi=data['total_put_oi'],
                total_call_oi=data['total_call_oi'],
                put_call_ratio=data['put_call_ratio'],
                timestamp=timestamp,
                expiration_date=data['expiration_date']
            )
        except Exception as e:
            logger.warning(f"キャッシュ読み込み失敗 ({symbol}): {e}")
            return None
    
    def _save_cache(self, analysis: OpenInterestAnalysis) -> None:
        """データをキャッシュに保存"""
        try:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            cache_path = self._get_cache_path(analysis.symbol)
            
            data = {
                'symbol': analysis.symbol,
                'underlying_symbol': analysis.underlying_symbol,
                'key_levels': [
                    {
                        'price': kl.price,
                        'level_type': kl.level_type,
                        'strength': kl.strength,
                        'source': kl.source,
                        'open_interest': kl.open_interest
                    }
                    for kl in analysis.key_levels
                ],
                'max_pain': analysis.max_pain,
                'put_wall': analysis.put_wall,
                'call_wall': analysis.call_wall,
                'total_put_oi': analysis.total_put_oi,
                'total_call_oi': analysis.total_call_oi,
                'put_call_ratio': analysis.put_call_ratio,
                'timestamp': analysis.timestamp.isoformat(),
                'expiration_date': analysis.expiration_date
            }
            
            with open(cache_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            
            logger.info(f"キャッシュ保存完了: {cache_path}")
        except Exception as e:
            logger.warning(f"キャッシュ保存失敗: {e}")
    
    def _calculate_max_pain(self, puts_df, calls_df) -> Optional[float]:
        """
        Max Pain（オプション売り手の最大利益価格）を計算
        
        Max Pain = 全オプション買い手の損失が最大となる価格
        """
        try:
            # ストライク価格の一覧を取得
            all_strikes = sorted(set(puts_df['strike'].tolist() + calls_df['strike'].tolist()))
            
            if not all_strikes:
                return None
            
            min_pain = float('inf')
            max_pain_strike = None
            
            for strike in all_strikes:
                total_pain = 0
                
                # コール側の損失（現在価格がstrikeより下の場合）
                for _, call in calls_df.iterrows():
                    if strike < call['strike']:
                        # コール買い手の損失 = 0（無価値）
                        pass
                    else:
                        # コール買い手の利益 = (strike - call['strike']) * OI
                        total_pain += (strike - call['strike']) * call['openInterest']
                
                # プット側の損失（現在価格がstrikeより上の場合）
                for _, put in puts_df.iterrows():
                    if strike > put['strike']:
                        # プット買い手の損失 = 0（無価値）
                        pass
                    else:
                        # プット買い手の利益 = (put['strike'] - strike) * OI
                        total_pain += (put['strike'] - strike) * put['openInterest']
                
                if total_pain < min_pain:
                    min_pain = total_pain
                    max_pain_strike = strike
            
            return max_pain_strike
        except Exception as e:
            logger.warning(f"Max Pain計算失敗: {e}")
            return None
    
    def analyze_symbol(self, symbol: str, force_refresh: bool = False) -> Optional[OpenInterestAnalysis]:
        """
        指定銘柄の建玉分析を実行
        
        Args:
            symbol: MT4シンボル (USDJPY, US500, etc.)
            force_refresh: キャッシュを無視して最新データを取得
            
        Returns:
            OpenInterestAnalysis or None
        """
        # シンボルマッピング確認
        if symbol not in self.SYMBOL_MAPPING:
            logger.warning(f"未対応シンボル: {symbol}")
            return None
        
        # キャッシュ確認
        if not force_refresh:
            cached = self._load_cache(symbol)
            if cached:
                logger.info(f"キャッシュからデータ取得: {symbol}")
                return cached
        
        underlying = self.SYMBOL_MAPPING[symbol]
        logger.info(f"建玉分析開始: {symbol} (underlying: {underlying})")
        
        try:
            yf = self._get_yfinance()
            ticker = yf.Ticker(underlying)
            
            # オプション満期日一覧を取得
            expirations = ticker.options
            if not expirations:
                logger.warning(f"オプションデータなし: {underlying}")
                return None
            
            # 最も近い満期日を使用
            exp_date = expirations[0]
            opt_chain = ticker.option_chain(exp_date)
            
            puts_df = opt_chain.puts
            calls_df = opt_chain.calls
            
            # 建玉合計
            total_put_oi = int(puts_df['openInterest'].sum())
            total_call_oi = int(calls_df['openInterest'].sum())
            pcr = total_put_oi / total_call_oi if total_call_oi > 0 else 1.0
            
            # プット壁（最大プット建玉価格）
            put_wall = None
            if not puts_df.empty:
                max_put_idx = puts_df['openInterest'].idxmax()
                put_wall = float(puts_df.loc[max_put_idx, 'strike'])
                max_put_oi = int(puts_df.loc[max_put_idx, 'openInterest'])
            
            # コール壁（最大コール建玉価格）
            call_wall = None
            if not calls_df.empty:
                max_call_idx = calls_df['openInterest'].idxmax()
                call_wall = float(calls_df.loc[max_call_idx, 'strike'])
                max_call_oi = int(calls_df.loc[max_call_idx, 'openInterest'])
            
            # Max Pain計算
            max_pain = self._calculate_max_pain(puts_df, calls_df)
            
            # 重要価格帯のリスト生成
            key_levels = []
            
            # 上位プット建玉をサポートとして追加
            top_puts = puts_df.nlargest(3, 'openInterest')
            max_oi = max(total_put_oi, total_call_oi)
            
            for _, row in top_puts.iterrows():
                strength = row['openInterest'] / max_oi if max_oi > 0 else 0
                key_levels.append(KeyLevel(
                    price=float(row['strike']),
                    level_type="support",
                    strength=strength,
                    source="put_concentration",
                    open_interest=int(row['openInterest'])
                ))
            
            # 上位コール建玉をレジスタンスとして追加
            top_calls = calls_df.nlargest(3, 'openInterest')
            for _, row in top_calls.iterrows():
                strength = row['openInterest'] / max_oi if max_oi > 0 else 0
                key_levels.append(KeyLevel(
                    price=float(row['strike']),
                    level_type="resistance",
                    strength=strength,
                    source="call_concentration",
                    open_interest=int(row['openInterest'])
                ))
            
            # Max Painをピボットとして追加
            if max_pain:
                key_levels.append(KeyLevel(
                    price=max_pain,
                    level_type="pivot",
                    strength=0.8,
                    source="max_pain",
                    open_interest=0
                ))
            
            # 価格でソート
            key_levels.sort(key=lambda x: x.price)
            
            analysis = OpenInterestAnalysis(
                symbol=symbol,
                underlying_symbol=underlying,
                key_levels=key_levels,
                max_pain=max_pain,
                put_wall=put_wall,
                call_wall=call_wall,
                total_put_oi=total_put_oi,
                total_call_oi=total_call_oi,
                put_call_ratio=pcr,
                timestamp=datetime.now(),
                expiration_date=exp_date
            )
            
            # キャッシュ保存
            self._save_cache(analysis)
            
            logger.info(f"建玉分析完了: {symbol} - Put Wall: {put_wall}, Call Wall: {call_wall}, Max Pain: {max_pain}")
            
            return analysis
            
        except Exception as e:
            logger.error(f"建玉分析失敗 ({symbol}): {e}")
            return None
    
    def get_key_levels(self, symbol: str) -> Dict:
        """
        API向けに重要価格帯を辞書形式で取得
        
        Args:
            symbol: MT4シンボル
            
        Returns:
            dict: API レスポンス形式
        """
        analysis = self.analyze_symbol(symbol)
        
        if not analysis:
            return {
                "symbol": symbol,
                "error": "データ取得失敗",
                "supported_symbols": list(self.SYMBOL_MAPPING.keys())
            }
        
        return {
            "symbol": symbol,
            "underlying_symbol": analysis.underlying_symbol,
            "expiration_date": analysis.expiration_date,
            "key_levels": [
                {
                    "price": kl.price,
                    "type": kl.level_type,
                    "strength": round(kl.strength, 3),
                    "source": kl.source,
                    "open_interest": kl.open_interest
                }
                for kl in analysis.key_levels
            ],
            "summary": {
                "put_wall": analysis.put_wall,
                "call_wall": analysis.call_wall,
                "max_pain": analysis.max_pain,
                "put_call_ratio": round(analysis.put_call_ratio, 3),
                "total_put_oi": analysis.total_put_oi,
                "total_call_oi": analysis.total_call_oi
            },
            "timestamp": analysis.timestamp.isoformat()
        }
    
    def analyze_all_symbols(self) -> Dict[str, Dict]:
        """
        全対象銘柄の建玉分析を実行
        
        Returns:
            dict: 銘柄別の分析結果
        """
        results = {}
        for symbol in self.SYMBOL_MAPPING.keys():
            logger.info(f"分析中: {symbol}")
            results[symbol] = self.get_key_levels(symbol)
        return results


# テスト用コード
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    
    analyzer = OpenInterestAnalyzer()
    
    print("=" * 60)
    print("建玉分析テスト")
    print("=" * 60)
    
    # US500 (SPY) のテスト
    test_symbols = ["US500", "NQ100", "USDJPY"]
    
    for symbol in test_symbols:
        print(f"\n--- {symbol} ---")
        try:
            result = analyzer.get_key_levels(symbol)
            
            if "error" in result:
                print(f"エラー: {result['error']}")
                continue
            
            print(f"Underlying: {result['underlying_symbol']}")
            print(f"満期日: {result['expiration_date']}")
            print(f"Put Wall: {result['summary']['put_wall']}")
            print(f"Call Wall: {result['summary']['call_wall']}")
            print(f"Max Pain: {result['summary']['max_pain']}")
            print(f"PCR: {result['summary']['put_call_ratio']}")
            print(f"\n重要価格帯:")
            for level in result['key_levels'][:5]:
                print(f"  {level['price']:.2f} ({level['type']}) - 強度: {level['strength']:.3f}")
                
        except Exception as e:
            print(f"エラー: {e}")
