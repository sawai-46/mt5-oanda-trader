"""
MT4 Log Learning Script
=======================
データベースからエクスポートされた実稼働データ（特徴量済みデータ）を使用して
AIモデルを学習・微調整（Fine-tuning）するスクリプト。
"""

import pandas as pd
import numpy as np
import argparse
import os
import torch
from pathlib import Path
from typing import Tuple

from antigravity.forecasting.models import TransformerPredictor

def load_exported_data(file_path: str) -> pd.DataFrame:
    """エクスポートされたCSVを読み込む"""
    df = pd.read_csv(file_path)
    # タイムスタンプでソート
    if 'timestamp' in df.columns:
        df['timestamp'] = pd.to_datetime(df['timestamp'])
        df = df.sort_values('timestamp')
    return df

def prepare_sequences_from_features(df: pd.DataFrame, seq_len: int = 20) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    蓄積された特徴量データから学習用シーケンスを作成する。
    DBのカラム名を TransformerPredictor の期待する 5次元特徴量にマッピング。
    
    マッピング案:
    0: log_return (or pct_change)
    1: gk_volatility (or atr_ratio)
    2: alpha (or technical_score)
    3: price_norm (normalized entry_price)
    4: vol_norm (normalized ATR)
    """
    X_list = []
    y_reg_list = []
    y_cls_list = []

    # カラムの正規化
    df = df.copy()
    
    # ターゲット（結果）の準備
    # DBに結果データがない場合は、次の行の価格変化から計算するか、
    # 既存の 'signal' などをラベルとして使う（今回は自己教師あり学習的アプローチ）
    
    # 特徴量抽出 (DBの構成に合わせる)
    # 'ema_fast', 'ema_slow', 'macd', 'rsi', 'atr' などが記録されている想定
    
    # 簡易的な特徴量合成
    features = pd.DataFrame(index=df.index)
    
    # 1. 変化率
    if 'entry_price' in df.columns:
        features['ret'] = df['entry_price'].pct_change().fillna(0)
    else:
        features['ret'] = 0
        
    # 2. ボラティリティ代用
    if 'atr' in df.columns:
        features['vol'] = df['atr'] / df['entry_price']
    else:
        features['vol'] = 0.01
        
    # 3. テクニカルスコア代用
    if 'rsi' in df.columns:
        features['alpha'] = (df['rsi'] - 50) / 100
    else:
        features['alpha'] = 0
        
    # 4. 価格正規化
    features['price'] = (df['entry_price'] - df['entry_price'].mean()) / (df['entry_price'].std() + 1e-8)
    
    # 5. その他
    features['misc'] = 0

    feat_values = features.values
    
    # ターゲット: 実際の勝敗データがあればそれを使うが、
    # なければ「後の価格が上がったか」を学習
    prices = df['entry_price'].values
    
    for i in range(seq_len, len(df) - 1):
        # シーケンス
        X_list.append(feat_values[i-seq_len:i])
        
        # 次の価格変化 (y)
        future_ret = (prices[i+1] - prices[i]) / prices[i]
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

def main():
    parser = argparse.ArgumentParser(description="Train model from DB logs")
    parser.add_argument("--file", type=str, required=True, help="Path to exported CSV")
    parser.add_argument("--model-in", type=str, help="Existing model path to fine-tune")
    parser.add_argument("--model-out", type=str, default="antigravity/data/refined_model.pt", help="Output path")
    parser.add_argument("--epochs", type=int, default=30)
    args = parser.parse_args()

    print(f"Loading data: {args.file}")
    df = load_exported_data(args.file)
    print(f"Total rows: {len(df)}")

    if len(df) < 50:
        print("Error: Not enough data for training (min 50 rows required).")
        return

    X, y_reg, y_cls = prepare_sequences_from_features(df)
    print(f"Sequences created: {len(X)}")

    # モデル初期化 (既存があればロード)
    predictor = TransformerPredictor(input_dim=5)
    if args.model_in and os.path.exists(args.model_in):
        print(f"Loading existing model: {args.model_in}")
        predictor.load(args.model_in)

    # 訓練
    print(f"Starting training for {args.epochs} epochs...")
    batch_size = 16
    n_samples = len(X)
    
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    predictor.model.to(device)
    
    for epoch in range(args.epochs):
        indices = np.random.permutation(n_samples)
        epoch_loss = 0
        for i in range(0, n_samples, batch_size):
            idx = indices[i:i+batch_size]
            loss = predictor.train(X[idx], y_reg[idx], y_cls[idx])
            epoch_loss += loss
        
        if (epoch + 1) % 5 == 0:
            print(f"Epoch {epoch+1}/{args.epochs}, Loss: {epoch_loss/max(1, n_samples//batch_size):.6f}")

    # 保存
    os.makedirs(os.path.dirname(args.model_out), exist_ok=True)
    predictor.save(args.model_out)
    print(f"Refined model saved to: {args.model_out}")

if __name__ == "__main__":
    main()
