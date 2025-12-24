"""
統一ログシステム
すべてのPythonモジュールで使用する共通ロガー

出力先: MT4/Files/OneDriveLogs/SystemLogs/
"""

import os
import sys
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional
import json

# MT4 Filesフォルダのパス
MT4_FILES_PATH = Path(os.environ.get(
    'MT4_FILES_PATH',
    r'C:\Users\chanm\AppData\Roaming\MetaQuotes\Terminal\A84B568DA10F82FE5A8FF6A859153D6F\MQL4\Files'
))

# ログ出力先
LOG_DIR = MT4_FILES_PATH / 'OneDriveLogs' / 'SystemLogs'


class UnifiedLogger:
    """統一ロガークラス"""
    
    # ログレベル定義
    LEVELS = {
        'DEBUG': logging.DEBUG,
        'INFO': logging.INFO,
        'WARNING': logging.WARNING,
        'ERROR': logging.ERROR,
        'CRITICAL': logging.CRITICAL
    }
    
    # モジュール別のログファイル名
    MODULES = {
        'market_sentinel': 'market_sentinel.log',
        'inference': 'inference.log',
        'trade_optimizer': 'trade_optimizer.log',
        'signal_engine': 'signal_engine.log',
        'system': 'system.log'
    }
    
    _instances = {}
    
    def __new__(cls, module_name: str = 'system'):
        """シングルトンパターン（モジュール別）"""
        if module_name not in cls._instances:
            instance = super().__new__(cls)
            instance._initialized = False
            cls._instances[module_name] = instance
        return cls._instances[module_name]
    
    def __init__(self, module_name: str = 'system'):
        if self._initialized:
            return
        
        self.module_name = module_name
        self.log_dir = LOG_DIR
        self._ensure_log_dir()
        
        # ログファイル名
        log_file = self.MODULES.get(module_name, f'{module_name}.log')
        self.log_path = self.log_dir / log_file
        
        # 日付別ログ
        today = datetime.now().strftime('%Y%m%d')
        self.daily_log_path = self.log_dir / f'{module_name}_{today}.log'
        
        # ロガー設定
        self.logger = logging.getLogger(f'mt4.{module_name}')
        self.logger.setLevel(logging.DEBUG)
        self.logger.handlers = []  # 既存ハンドラをクリア
        
        # フォーマッター（統一形式）
        formatter = logging.Formatter(
            '%(asctime)s | %(levelname)-8s | %(name)s | %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        
        # ファイルハンドラ（日別）
        file_handler = logging.FileHandler(
            self.daily_log_path, 
            encoding='utf-8',
            mode='a'
        )
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(formatter)
        self.logger.addHandler(file_handler)
        
        # コンソールハンドラ
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(logging.INFO)
        console_handler.setFormatter(formatter)
        self.logger.addHandler(console_handler)
        
        self._initialized = True
    
    def _ensure_log_dir(self):
        """ログディレクトリを作成"""
        self.log_dir.mkdir(parents=True, exist_ok=True)
    
    def debug(self, message: str, **kwargs):
        """デバッグログ"""
        self._log('DEBUG', message, **kwargs)
    
    def info(self, message: str, **kwargs):
        """情報ログ"""
        self._log('INFO', message, **kwargs)
    
    def warning(self, message: str, **kwargs):
        """警告ログ"""
        self._log('WARNING', message, **kwargs)
    
    def error(self, message: str, **kwargs):
        """エラーログ"""
        self._log('ERROR', message, **kwargs)
    
    def critical(self, message: str, **kwargs):
        """重大エラーログ"""
        self._log('CRITICAL', message, **kwargs)
    
    def _log(self, level: str, message: str, **kwargs):
        """ログ出力"""
        if kwargs:
            # 追加データをJSON形式で追加
            extra = json.dumps(kwargs, ensure_ascii=False, default=str)
            message = f"{message} | {extra}"
        
        log_func = getattr(self.logger, level.lower())
        log_func(message)
    
    def log_event(self, event_type: str, data: dict):
        """イベントログ（構造化データ）"""
        event = {
            'timestamp': datetime.now().isoformat(),
            'module': self.module_name,
            'event_type': event_type,
            'data': data
        }
        
        # JSONログファイルに追記
        json_log_path = self.log_dir / f'{self.module_name}_events.jsonl'
        with open(json_log_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps(event, ensure_ascii=False, default=str) + '\n')
        
        # 通常ログにも出力
        self.info(f"[{event_type}] {json.dumps(data, ensure_ascii=False, default=str)}")
    
    def log_trade(self, action: str, symbol: str, direction: str, 
                  lot: float, price: float, sl: float = 0, tp: float = 0,
                  ticket: int = 0, reason: str = ''):
        """トレードログ（統一形式）"""
        trade_data = {
            'action': action,
            'symbol': symbol,
            'direction': direction,
            'lot': lot,
            'price': price,
            'sl': sl,
            'tp': tp,
            'ticket': ticket,
            'reason': reason
        }
        self.log_event('TRADE', trade_data)
    
    def log_signal(self, symbol: str, signal: str, confidence: float,
                   sources: list = None, reason: str = ''):
        """シグナルログ（統一形式）"""
        signal_data = {
            'symbol': symbol,
            'signal': signal,
            'confidence': confidence,
            'sources': sources or [],
            'reason': reason
        }
        self.log_event('SIGNAL', signal_data)
    
    def log_risk(self, status: str, risk_level: int, 
                 events: list = None, reason: str = ''):
        """リスク評価ログ（統一形式）"""
        risk_data = {
            'status': status,
            'risk_level': risk_level,
            'events': events or [],
            'reason': reason
        }
        self.log_event('RISK', risk_data)


def get_logger(module_name: str = 'system') -> UnifiedLogger:
    """ロガーを取得"""
    return UnifiedLogger(module_name)


# 便利なショートカット
def get_market_sentinel_logger() -> UnifiedLogger:
    return get_logger('market_sentinel')

def get_inference_logger() -> UnifiedLogger:
    return get_logger('inference')

def get_trade_optimizer_logger() -> UnifiedLogger:
    return get_logger('trade_optimizer')

def get_signal_engine_logger() -> UnifiedLogger:
    return get_logger('signal_engine')


if __name__ == '__main__':
    # テスト
    logger = get_logger('test')
    logger.info('テストログ')
    logger.warning('警告テスト')
    logger.error('エラーテスト', error_code=123)
    logger.log_event('TEST_EVENT', {'key': 'value'})
    logger.log_signal('USDJPY', 'BUY', 0.75, ['EMA', 'MACD'], 'テスト')
    logger.log_risk('SUSPENDED', 5, [{'name': '米CPI'}], '重要イベント前')
    print(f"\nログ出力先: {LOG_DIR}")
