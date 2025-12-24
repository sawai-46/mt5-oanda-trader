"""
オプション市場リスク監視モジュール

大きなドローダウン（リーマンショック級）を回避するための
オプション市場指標監視システム。

主要指標:
- VIX (恐怖指数): 市場の予想ボラティリティ
- SKEW (スキュー指数): テールリスク警戒度
- Put/Call Ratio: 投資家センチメント

更新頻度: 1日1回（日次）
目的: 極端な市場環境での取引回避
"""

import logging
from datetime import datetime, timedelta
from typing import Dict, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
import json
from pathlib import Path

logger = logging.getLogger(__name__)


class RiskLevel(Enum):
    """リスクレベル定義"""
    SAFE = "safe"           # 通常運用
    CAUTION = "caution"     # 警戒（ロット削減推奨）
    DANGER = "danger"       # 危険（取引停止推奨）
    EXTREME = "extreme"     # 極度の危険（全ポジション決済推奨）


@dataclass
class OptionsRiskData:
    """オプション市場リスクデータ"""
    vix: float
    skew: float
    put_call_ratio: float
    nikkei_vi: Optional[float]  # 日経VI（日本市場向け）
    
    vix_score: int      # 0-3
    skew_score: int     # 0-3
    pcr_score: int      # 0-3
    total_score: int    # 0-9
    
    risk_level: RiskLevel
    timestamp: datetime
    
    recommendation: str  # 取引推奨事項


class OptionsRiskModule:
    """
    オプション市場リスク監視モジュール
    
    大きなドローダウン回避のため、1日1回オプション市場指標を取得し
    リスクレベルを判定します。
    """
    
    # リスク閾値設定
    VIX_THRESHOLDS = {
        "safe": 15,      # VIX < 15: 低ボラ
        "caution": 25,   # VIX 15-25: 中ボラ
        "danger": 35,    # VIX 25-35: 高ボラ
        # VIX > 35: 極度の危険
    }
    
    SKEW_THRESHOLDS = {
        "safe": 130,     # SKEW < 130: テールリスク低
        "caution": 145,  # SKEW 130-145: やや警戒
        "danger": 160,   # SKEW 145-160: 高警戒
        # SKEW > 160: 機関投資家が大暴落を警戒
    }
    
    PCR_THRESHOLDS = {
        # Put/Call Ratio の正常範囲は 0.7-1.2
        "extreme_bullish": 0.5,   # < 0.5: 過度な楽観
        "bullish": 0.7,           # 0.5-0.7: 楽観
        "neutral_low": 0.8,       # 0.7-0.8: やや楽観
        "neutral_high": 1.2,      # 0.8-1.2: 中立
        "bearish": 1.4,           # 1.2-1.4: 悲観
        # > 1.4: 過度な悲観（コントラリアン的には買いシグナル）
    }
    
    def __init__(self, cache_file: Optional[Path] = None, cache_hours: int = 24):
        """
        初期化
        
        Args:
            cache_file: キャッシュファイルパス
            cache_hours: キャッシュ有効時間（時間）
        """
        self.cache_file = cache_file or Path(__file__).parent.parent / "data" / "options_risk_cache.json"
        self.cache_hours = cache_hours
        self._cached_data: Optional[OptionsRiskData] = None
        self._last_update: Optional[datetime] = None
        
        # yfinance は遅延インポート（必要時のみ）
        self._yf = None
        
    def _get_yfinance(self):
        """yfinance の遅延インポート"""
        if self._yf is None:
            try:
                import yfinance as yf
                self._yf = yf
            except ImportError:
                logger.error("yfinance がインストールされていません。pip install yfinance を実行してください。")
                raise
        return self._yf
    
    def _fetch_vix(self) -> float:
        """
        VIX（CBOE恐怖指数）を取得
        
        Returns:
            VIX値（取得失敗時は20.0をデフォルト）
        """
        try:
            yf = self._get_yfinance()
            ticker = yf.Ticker("^VIX")
            hist = ticker.history(period="1d")
            if not hist.empty:
                vix = float(hist['Close'].iloc[-1])
                logger.info(f"VIX取得成功: {vix:.2f}")
                return vix
        except Exception as e:
            logger.warning(f"VIX取得失敗: {e}")
        return 20.0  # デフォルト（中程度のボラティリティ）
    
    def _fetch_skew(self) -> float:
        """
        SKEW指数を取得
        
        Returns:
            SKEW値（取得失敗時は130.0をデフォルト）
        """
        try:
            yf = self._get_yfinance()
            ticker = yf.Ticker("^SKEW")
            hist = ticker.history(period="1d")
            if not hist.empty:
                skew = float(hist['Close'].iloc[-1])
                logger.info(f"SKEW取得成功: {skew:.2f}")
                return skew
        except Exception as e:
            logger.warning(f"SKEW取得失敗: {e}")
        return 130.0  # デフォルト（通常レベル）
    
    def _fetch_nikkei_vi(self) -> Optional[float]:
        """
        日経VI（日本版VIX）を取得
        
        Returns:
            日経VI値（取得失敗時はNone）
        """
        try:
            yf = self._get_yfinance()
            # 日経VIのティッカー
            ticker = yf.Ticker("^JNIV")
            hist = ticker.history(period="1d")
            if not hist.empty:
                nikkei_vi = float(hist['Close'].iloc[-1])
                logger.info(f"日経VI取得成功: {nikkei_vi:.2f}")
                return nikkei_vi
        except Exception as e:
            logger.warning(f"日経VI取得失敗: {e}")
        return None
    
    def _calculate_put_call_ratio(self) -> float:
        """
        Put/Call Ratio を計算（SPYオプションから）
        
        Returns:
            PCR値（取得失敗時は1.0をデフォルト）
        """
        try:
            yf = self._get_yfinance()
            spy = yf.Ticker("SPY")
            
            # 最も近い満期日のオプションを取得
            expirations = spy.options
            if not expirations:
                return 1.0
            
            # 最初の満期日（最も近い）
            exp_date = expirations[0]
            opt_chain = spy.option_chain(exp_date)
            
            # 建玉ベースでPCR計算
            put_oi = opt_chain.puts['openInterest'].sum()
            call_oi = opt_chain.calls['openInterest'].sum()
            
            if call_oi > 0:
                pcr = put_oi / call_oi
                logger.info(f"PCR計算成功: {pcr:.3f} (Put OI: {put_oi:,}, Call OI: {call_oi:,})")
                return pcr
        except Exception as e:
            logger.warning(f"PCR計算失敗: {e}")
        return 1.0  # デフォルト（中立）
    
    def _score_vix(self, vix: float) -> int:
        """VIXスコア計算（0-3）"""
        if vix < self.VIX_THRESHOLDS["safe"]:
            return 0
        elif vix < self.VIX_THRESHOLDS["caution"]:
            return 1
        elif vix < self.VIX_THRESHOLDS["danger"]:
            return 2
        else:
            return 3
    
    def _score_skew(self, skew: float) -> int:
        """SKEWスコア計算（0-3）"""
        if skew < self.SKEW_THRESHOLDS["safe"]:
            return 0
        elif skew < self.SKEW_THRESHOLDS["caution"]:
            return 1
        elif skew < self.SKEW_THRESHOLDS["danger"]:
            return 2
        else:
            return 3
    
    def _score_pcr(self, pcr: float) -> int:
        """PCRスコア計算（0-3）"""
        # 中立範囲: 0.8-1.2
        if 0.8 <= pcr <= 1.2:
            return 0
        # やや偏り: 0.7-0.8 or 1.2-1.4
        elif 0.7 <= pcr < 0.8 or 1.2 < pcr <= 1.4:
            return 1
        # 偏り大: 0.5-0.7 or 1.4-1.6
        elif 0.5 <= pcr < 0.7 or 1.4 < pcr <= 1.6:
            return 2
        # 極端: < 0.5 or > 1.6
        else:
            return 3
    
    def _determine_risk_level(self, total_score: int) -> RiskLevel:
        """総合スコアからリスクレベルを判定"""
        if total_score <= 2:
            return RiskLevel.SAFE
        elif total_score <= 4:
            return RiskLevel.CAUTION
        elif total_score <= 6:
            return RiskLevel.DANGER
        else:
            return RiskLevel.EXTREME
    
    def _generate_recommendation(self, risk_level: RiskLevel, vix: float, skew: float, pcr: float) -> str:
        """リスクレベルに基づく推奨事項を生成"""
        recommendations = {
            RiskLevel.SAFE: "通常運用可能。標準ロットでの取引を継続。",
            RiskLevel.CAUTION: f"警戒レベル。ロットを50%に削減推奨。VIX={vix:.1f}",
            RiskLevel.DANGER: f"危険レベル。新規エントリー停止を推奨。VIX={vix:.1f}, SKEW={skew:.1f}",
            RiskLevel.EXTREME: f"極度の危険。全ポジション決済、取引停止を強く推奨。VIX={vix:.1f}, SKEW={skew:.1f}, PCR={pcr:.2f}",
        }
        return recommendations.get(risk_level, "判定不能")
    
    def _load_cache(self) -> Optional[OptionsRiskData]:
        """キャッシュからデータを読み込み"""
        if not self.cache_file.exists():
            return None
        
        try:
            with open(self.cache_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            timestamp = datetime.fromisoformat(data['timestamp'])
            
            # キャッシュ有効期限チェック
            if datetime.now() - timestamp > timedelta(hours=self.cache_hours):
                logger.info("キャッシュ期限切れ")
                return None
            
            return OptionsRiskData(
                vix=data['vix'],
                skew=data['skew'],
                put_call_ratio=data['put_call_ratio'],
                nikkei_vi=data.get('nikkei_vi'),
                vix_score=data['vix_score'],
                skew_score=data['skew_score'],
                pcr_score=data['pcr_score'],
                total_score=data['total_score'],
                risk_level=RiskLevel(data['risk_level']),
                timestamp=timestamp,
                recommendation=data['recommendation']
            )
        except Exception as e:
            logger.warning(f"キャッシュ読み込み失敗: {e}")
            return None
    
    def _save_cache(self, data: OptionsRiskData) -> None:
        """データをキャッシュに保存"""
        try:
            self.cache_file.parent.mkdir(parents=True, exist_ok=True)
            
            cache_data = {
                'vix': data.vix,
                'skew': data.skew,
                'put_call_ratio': data.put_call_ratio,
                'nikkei_vi': data.nikkei_vi,
                'vix_score': data.vix_score,
                'skew_score': data.skew_score,
                'pcr_score': data.pcr_score,
                'total_score': data.total_score,
                'risk_level': data.risk_level.value,
                'timestamp': data.timestamp.isoformat(),
                'recommendation': data.recommendation
            }
            
            with open(self.cache_file, 'w', encoding='utf-8') as f:
                json.dump(cache_data, f, ensure_ascii=False, indent=2)
            
            logger.info(f"キャッシュ保存完了: {self.cache_file}")
        except Exception as e:
            logger.warning(f"キャッシュ保存失敗: {e}")
    
    def get_risk_data(self, force_refresh: bool = False) -> OptionsRiskData:
        """
        オプション市場リスクデータを取得
        
        Args:
            force_refresh: True の場合、キャッシュを無視して最新データを取得
            
        Returns:
            OptionsRiskData: リスク分析結果
        """
        # キャッシュ確認
        if not force_refresh:
            cached = self._load_cache()
            if cached:
                logger.info(f"キャッシュからデータ取得 (更新: {cached.timestamp})")
                return cached
        
        logger.info("オプション市場データ取得開始...")
        
        # データ取得
        vix = self._fetch_vix()
        skew = self._fetch_skew()
        pcr = self._calculate_put_call_ratio()
        nikkei_vi = self._fetch_nikkei_vi()
        
        # スコア計算
        vix_score = self._score_vix(vix)
        skew_score = self._score_skew(skew)
        pcr_score = self._score_pcr(pcr)
        total_score = vix_score + skew_score + pcr_score
        
        # リスクレベル判定
        risk_level = self._determine_risk_level(total_score)
        
        # 推奨事項生成
        recommendation = self._generate_recommendation(risk_level, vix, skew, pcr)
        
        # データ構築
        data = OptionsRiskData(
            vix=vix,
            skew=skew,
            put_call_ratio=pcr,
            nikkei_vi=nikkei_vi,
            vix_score=vix_score,
            skew_score=skew_score,
            pcr_score=pcr_score,
            total_score=total_score,
            risk_level=risk_level,
            timestamp=datetime.now(),
            recommendation=recommendation
        )
        
        # キャッシュ保存
        self._save_cache(data)
        
        logger.info(f"リスク分析完了: {risk_level.value} (Score: {total_score}/9)")
        
        return data
    
    def get_risk_score(self) -> Dict:
        """
        リスクスコアをAPI向けの辞書形式で取得
        
        Returns:
            dict: API レスポンス形式のリスクデータ
        """
        data = self.get_risk_data()
        
        return {
            "risk_level": data.risk_level.value,
            "total_score": data.total_score,
            "max_score": 9,
            "indicators": {
                "vix": {"value": data.vix, "score": data.vix_score, "max": 3},
                "skew": {"value": data.skew, "score": data.skew_score, "max": 3},
                "put_call_ratio": {"value": data.put_call_ratio, "score": data.pcr_score, "max": 3},
                "nikkei_vi": {"value": data.nikkei_vi} if data.nikkei_vi else None,
            },
            "recommendation": data.recommendation,
            "timestamp": data.timestamp.isoformat(),
            "cache_valid_until": (data.timestamp + timedelta(hours=self.cache_hours)).isoformat()
        }
    
    def should_trade(self) -> Tuple[bool, str]:
        """
        取引可否判定
        
        Returns:
            Tuple[bool, str]: (取引可否, 理由)
        """
        data = self.get_risk_data()
        
        if data.risk_level == RiskLevel.SAFE:
            return True, "市場環境は安定しています。"
        elif data.risk_level == RiskLevel.CAUTION:
            return True, f"警戒レベル。ロット削減を推奨。{data.recommendation}"
        elif data.risk_level == RiskLevel.DANGER:
            return False, f"危険レベル。新規取引は非推奨。{data.recommendation}"
        else:
            return False, f"極度の危険。取引停止を強く推奨。{data.recommendation}"


# テスト用コード
if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    
    module = OptionsRiskModule()
    
    print("=" * 60)
    print("オプション市場リスク分析")
    print("=" * 60)
    
    try:
        risk = module.get_risk_score()
        print(f"\nリスクレベル: {risk['risk_level'].upper()}")
        print(f"総合スコア: {risk['total_score']}/{risk['max_score']}")
        print(f"\n指標詳細:")
        for name, indicator in risk['indicators'].items():
            if indicator:
                if 'score' in indicator:
                    print(f"  {name}: {indicator['value']:.2f} (スコア: {indicator['score']}/{indicator['max']})")
                else:
                    print(f"  {name}: {indicator['value']:.2f}")
        print(f"\n推奨: {risk['recommendation']}")
        print(f"更新時刻: {risk['timestamp']}")
        
        can_trade, reason = module.should_trade()
        print(f"\n取引判定: {'可' if can_trade else '不可'}")
        print(f"理由: {reason}")
        
    except Exception as e:
        print(f"エラー: {e}")
