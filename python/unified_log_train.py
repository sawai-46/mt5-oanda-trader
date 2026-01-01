"""
Unified AI Training Pipeline
統合DBからAI学習データを抽出してモデルを訓練するスクリプト
"""

import pandas as pd
import numpy as np
import argparse
import os
import torch
from pathlib import Path
from typing import Tuple, Optional
from datetime import datetime

# 同じディレクトリからインポート
from unified_log_db import UnifiedLogDatabase


def load_data_from_db(db_path: str, source_system: str = None, symbol: str = None) -> pd.DataFrame:
    """データベースからAI学習データを読み込む"""
    db = UnifiedLogDatabase(db_path)
    conn = db._get_connection()
    
    query = "SELECT * FROM ai_learning_data WHERE 1=1"
    params = []
    
    if source_system:
        query += " AND source_system = ?"
        params.append(source_system)
    
    if symbol:
        query += " AND symbol LIKE ?"
        params.append(f"%{symbol}%")
    
    query += " ORDER BY timestamp"
    
    df = pd.read_sql_query(query, conn, params=params)
    db.close()
    
    print(f"Loaded {len(df)} rows from database")
    if len(df) > 0:
        print(f"  Source systems: {df['source_system'].value_counts().to_dict()}")
        print(f"  Symbols: {df['symbol'].value_counts().head(10).to_dict()}")
    
    return df


def prepare_sequences(df: pd.DataFrame, seq_len: int = 20) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    蓄積された特徴量データから学習用シーケンスを作成
    
    Returns:
        X: (N, seq_len, 5) 入力シーケンス
        y_reg: (N, 1) 回帰ターゲット
        y_cls: (N,) 分類ターゲット
    """
    X_list = []
    y_reg_list = []
    y_cls_list = []

    df = df.copy()
    
    # タイムスタンプでソート
    if 'timestamp' in df.columns:
        df['timestamp'] = pd.to_datetime(df['timestamp'])
        df = df.sort_values('timestamp')
    
    # 特徴量を構築
    features = pd.DataFrame(index=df.index)
    
    # 1. 変化率
    if 'entry_price' in df.columns:
        features['ret'] = df['entry_price'].pct_change().fillna(0)
    else:
        features['ret'] = 0
        
    # 2. ボラティリティ
    if 'atr' in df.columns and 'entry_price' in df.columns:
        features['vol'] = df['atr'].astype(float) / df['entry_price'].astype(float).replace(0, np.nan)
        features['vol'] = features['vol'].fillna(0.01)
    else:
        features['vol'] = 0.01
        
    # 3. テクニカルスコア
    if 'adx' in df.columns:
        features['alpha'] = (df['adx'].astype(float) - 25) / 50
    elif 'confidence' in df.columns:
        features['alpha'] = df['confidence'].astype(float) - 0.5
    else:
        features['alpha'] = 0
        
    # 4. 価格正規化
    if 'entry_price' in df.columns:
        price = df['entry_price'].astype(float)
        features['price'] = (price - price.mean()) / (price.std() + 1e-8)
    else:
        features['price'] = 0
    
    # 5. EMA関係
    if 'ema12' in df.columns and 'ema25' in df.columns:
        ema12 = df['ema12'].astype(float)
        ema25 = df['ema25'].astype(float)
        features['ema_diff'] = (ema12 - ema25) / (ema25 + 1e-8)
    else:
        features['ema_diff'] = 0

    feat_values = features.values.astype(np.float32)
    
    # NaN/Infを0に置換
    feat_values = np.nan_to_num(feat_values, nan=0.0, posinf=0.0, neginf=0.0)
    
    # ターゲット生成
    if 'entry_price' in df.columns:
        prices = df['entry_price'].astype(float).values
    else:
        print("Warning: entry_price not found, using dummy target")
        prices = np.zeros(len(df))
    
    for i in range(seq_len, len(df) - 1):
        X_list.append(feat_values[i-seq_len:i])
        
        # 次の価格変化
        if prices[i] != 0:
            future_ret = (prices[i+1] - prices[i]) / prices[i]
        else:
            future_ret = 0
        y_reg_list.append([future_ret])
        
        # 分類ラベル (0: DOWN, 1: FLAT, 2: UP)
        if future_ret > 0.0001:
            y_cls_list.append(2)
        elif future_ret < -0.0001:
            y_cls_list.append(0)
        else:
            y_cls_list.append(1)

    return np.array(X_list, dtype=np.float32), \
           np.array(y_reg_list, dtype=np.float32), \
           np.array(y_cls_list, dtype=np.int64)


def train_model(X: np.ndarray, y_reg: np.ndarray, y_cls: np.ndarray, 
                model_in: str = None, model_out: str = "refined_model.pt",
                epochs: int = 30, batch_size: int = 16):
    """モデルを訓練"""
    
    # TransformerPredictor のインポートを試みる
    try:
        from antigravity.forecasting.models import TransformerPredictor
        predictor = TransformerPredictor(input_dim=5)
        use_transformer = True
    except ImportError:
        print("Warning: TransformerPredictor not available, using simple training loop")
        use_transformer = False
        predictor = None
    
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Training on device: {device}")
    
    if use_transformer and predictor:
        if model_in and os.path.exists(model_in):
            print(f"Loading existing model: {model_in}")
            predictor.load(model_in)
        
        predictor.model.to(device)
        
        n_samples = len(X)
        for epoch in range(epochs):
            indices = np.random.permutation(n_samples)
            epoch_loss = 0
            n_batches = 0
            
            for i in range(0, n_samples, batch_size):
                idx = indices[i:i+batch_size]
                loss = predictor.train(X[idx], y_reg[idx], y_cls[idx])
                epoch_loss += loss
                n_batches += 1
            
            if (epoch + 1) % 5 == 0 or epoch == 0:
                avg_loss = epoch_loss / max(1, n_batches)
                print(f"Epoch {epoch+1}/{epochs}, Loss: {avg_loss:.6f}")
        
        # 保存
        os.makedirs(os.path.dirname(model_out) if os.path.dirname(model_out) else '.', exist_ok=True)
        predictor.save(model_out)
        print(f"Model saved to: {model_out}")
    else:
        print("Skipping training (TransformerPredictor not available)")
        print(f"Dataset ready: X.shape={X.shape}, y_reg.shape={y_reg.shape}, y_cls.shape={y_cls.shape}")


def main():
    parser = argparse.ArgumentParser(description="Train AI model from unified log database")
    parser.add_argument("--db", type=str, required=True, help="Path to unified_logs.db")
    parser.add_argument("--source", type=str, default=None, help="Filter by source_system (MT4/MT5)")
    parser.add_argument("--symbol", type=str, default=None, help="Filter by symbol (partial match)")
    parser.add_argument("--model-in", type=str, help="Existing model path to fine-tune")
    parser.add_argument("--model-out", type=str, default="antigravity/models/refined_model.pt", help="Output path")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--seq-len", type=int, default=20, help="Sequence length for training")
    parser.add_argument("--export", type=str, default=None, help="Export data to CSV instead of training")
    args = parser.parse_args()

    print(f"=" * 60)
    print(f"Unified AI Training Pipeline")
    print(f"Database: {args.db}")
    print(f"=" * 60)

    # データ読み込み
    df = load_data_from_db(args.db, source_system=args.source, symbol=args.symbol)
    
    if len(df) < 50:
        print(f"Error: Not enough data for training (min 50 rows required, got {len(df)})")
        return

    # エクスポートモード
    if args.export:
        df.to_csv(args.export, index=False)
        print(f"Exported {len(df)} rows to: {args.export}")
        return

    # シーケンス作成
    X, y_reg, y_cls = prepare_sequences(df, seq_len=args.seq_len)
    print(f"Sequences created: {len(X)}")
    
    if len(X) < 10:
        print("Error: Not enough sequences for training")
        return

    # 訓練
    train_model(X, y_reg, y_cls, 
                model_in=args.model_in, 
                model_out=args.model_out,
                epochs=args.epochs)


if __name__ == "__main__":
    main()
