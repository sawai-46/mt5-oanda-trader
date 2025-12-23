"""
Antigravity Forecasting Models

金融時系列データ向けの高度なTransformerモデルを実装。
NotebookLMの研究結果に基づき、以下の手法を採用:
- 1D Convolutional Embedding (局所パターン抽出)
- Temporal Embedding (時間周期性)
- Time2Vec (学習可能な時間表現)
"""

import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
import math
from typing import Any, Optional, Tuple
from antigravity.core.interfaces import PredictionModel


class Time2Vec(nn.Module):
    """
    Time2Vec: 学習可能な時間表現
    
    周期的な時間パターン（日中、週次など）を捉えるための
    学習可能なサインベースの時間エンコーディング。
    """
    
    def __init__(self, embed_dim: int):
        super(Time2Vec, self).__init__()
        self.embed_dim = embed_dim
        
        # 線形成分（トレンド）
        self.linear = nn.Linear(1, 1)
        
        # 周期成分（サイン波）
        self.periodic = nn.Linear(1, embed_dim - 1)
    
    def forward(self, t: torch.Tensor) -> torch.Tensor:
        """
        Args:
            t: 時間インデックス [batch, seq_len, 1]
        Returns:
            Time embedding [batch, seq_len, embed_dim]
        """
        # 線形成分
        linear_out = self.linear(t)  # [batch, seq, 1]
        
        # 周期成分
        periodic_out = torch.sin(self.periodic(t))  # [batch, seq, embed_dim-1]
        
        # 結合
        return torch.cat([linear_out, periodic_out], dim=-1)


class Conv1DPositionalEmbedding(nn.Module):
    """
    1D Convolutional Embedding
    
    局所的な時間パターン（短期トレンド、ノイズ除去）を
    捉えるための1次元畳み込みベースの埋め込み層。
    """
    
    def __init__(self, input_dim: int, d_model: int, kernel_size: int = 3):
        super(Conv1DPositionalEmbedding, self).__init__()
        
        # 1D-CNN for local pattern extraction
        # Padding = kernel_size // 2 to maintain sequence length
        self.conv1 = nn.Conv1d(
            in_channels=input_dim,
            out_channels=d_model // 2,
            kernel_size=kernel_size,
            padding=kernel_size // 2
        )
        self.conv2 = nn.Conv1d(
            in_channels=d_model // 2,
            out_channels=d_model,
            kernel_size=kernel_size,
            padding=kernel_size // 2
        )
        
        self.norm = nn.LayerNorm(d_model)
        self.activation = nn.GELU()
        self.dropout = nn.Dropout(0.1)
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args:
            x: [batch, seq_len, input_dim]
        Returns:
            [batch, seq_len, d_model]
        """
        # Conv1d expects [batch, channels, seq_len]
        x = x.transpose(1, 2)  # [batch, input_dim, seq_len]
        
        x = self.activation(self.conv1(x))
        x = self.dropout(x)
        x = self.activation(self.conv2(x))
        
        # Back to [batch, seq_len, d_model]
        x = x.transpose(1, 2)
        x = self.norm(x)
        
        return x


class TemporalEmbedding(nn.Module):
    """
    Temporal Embedding (時間的埋め込み)
    
    時間的特徴（時間帯、曜日、月など）を捉えるための
    埋め込み層。金融市場の周期性をモデル化。
    """
    
    def __init__(self, d_model: int):
        super(TemporalEmbedding, self).__init__()
        
        # 時間帯 (0-23)
        self.hour_embed = nn.Embedding(24, d_model // 4)
        
        # 曜日 (0-6)
        self.day_embed = nn.Embedding(7, d_model // 4)
        
        # 月 (0-11)
        self.month_embed = nn.Embedding(12, d_model // 4)
        
        # 5分足のバー番号 (0-287: 24*60/5)
        self.bar_embed = nn.Embedding(288, d_model // 4)
        
        self.projection = nn.Linear(d_model, d_model)
    
    def forward(
        self, 
        hour: Optional[torch.Tensor] = None,
        day: Optional[torch.Tensor] = None,
        month: Optional[torch.Tensor] = None,
        bar_idx: Optional[torch.Tensor] = None
    ) -> torch.Tensor:
        """
        時間的特徴から埋め込みを生成。
        入力がNoneの場合はゼロベクトルを使用。
        """
        batch_size = 1
        seq_len = 1
        
        embeddings = []
        
        if hour is not None:
            batch_size, seq_len = hour.shape
            embeddings.append(self.hour_embed(hour))
        else:
            embeddings.append(torch.zeros(batch_size, seq_len, self.hour_embed.embedding_dim))
            
        if day is not None:
            embeddings.append(self.day_embed(day))
        else:
            embeddings.append(torch.zeros(batch_size, seq_len, self.day_embed.embedding_dim))
            
        if month is not None:
            embeddings.append(self.month_embed(month))
        else:
            embeddings.append(torch.zeros(batch_size, seq_len, self.month_embed.embedding_dim))
            
        if bar_idx is not None:
            embeddings.append(self.bar_embed(bar_idx.clamp(0, 287)))
        else:
            embeddings.append(torch.zeros(batch_size, seq_len, self.bar_embed.embedding_dim))
        
        # 結合して投影
        combined = torch.cat(embeddings, dim=-1)
        return self.projection(combined)


class SinusoidalPositionalEncoding(nn.Module):
    """
    標準的なサインベースの位置エンコーディング
    """
    
    def __init__(self, d_model: int, max_len: int = 512, dropout: float = 0.1):
        super(SinusoidalPositionalEncoding, self).__init__()
        self.dropout = nn.Dropout(p=dropout)
        
        pe = torch.zeros(max_len, d_model)
        position = torch.arange(0, max_len, dtype=torch.float).unsqueeze(1)
        div_term = torch.exp(torch.arange(0, d_model, 2).float() * (-math.log(10000.0) / d_model))
        
        pe[:, 0::2] = torch.sin(position * div_term)
        pe[:, 1::2] = torch.cos(position * div_term)
        pe = pe.unsqueeze(0)  # [1, max_len, d_model]
        
        self.register_buffer('pe', pe)
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args:
            x: [batch, seq_len, d_model]
        """
        seq_len = x.size(1)
        x = x + self.pe[:, :seq_len, :]
        return self.dropout(x)


class FinancialTransformer(nn.Module):
    """
    金融時系列向け Transformer
    
    研究論文の推奨事項に基づき、以下を実装:
    - 1D Convolutional Embedding (局所パターン抽出)
    - Temporal Embedding (時間周期性)
    - Sinusoidal Positional Encoding (順序保持)
    - Multi-head Self-Attention
    - 3クラス分類 (UP/FLAT/DOWN) + 回帰出力
    """
    
    def __init__(
        self,
        input_dim: int,
        d_model: int = 64,
        nhead: int = 4,
        num_layers: int = 2,
        dropout: float = 0.1,
        use_temporal: bool = False
    ):
        super(FinancialTransformer, self).__init__()
        
        self.use_temporal = use_temporal
        
        # 1. 1D Convolutional Embedding
        self.conv_embed = Conv1DPositionalEmbedding(input_dim, d_model)
        
        # 2. Temporal Embedding (オプション)
        if use_temporal:
            self.temporal_embed = TemporalEmbedding(d_model)
        
        # 3. Positional Encoding
        self.pos_encoder = SinusoidalPositionalEncoding(d_model, dropout=dropout)
        
        # 4. Transformer Encoder
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=nhead,
            dim_feedforward=d_model * 4,
            dropout=dropout,
            activation='gelu',
            batch_first=True
        )
        self.transformer_encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        
        # 5. Output Heads
        # 回帰出力（次の価格変化率を予測）
        self.regression_head = nn.Sequential(
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, 1)
        )
        
        # 分類出力（方向を予測: 0=DOWN, 1=FLAT, 2=UP）
        self.classification_head = nn.Sequential(
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, 3)
        )
        
        self._init_weights()
    
    def _init_weights(self):
        for p in self.parameters():
            if p.dim() > 1:
                nn.init.xavier_uniform_(p)
    
    def forward(
        self,
        x: torch.Tensor,
        temporal_info: Optional[dict] = None,
        src_mask: Optional[torch.Tensor] = None
    ) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        Args:
            x: 入力シーケンス [batch, seq_len, input_dim]
            temporal_info: 時間的情報 {'hour': tensor, 'day': tensor, ...}
            src_mask: パディングマスク
            
        Returns:
            regression_output: 価格変化率予測 [batch, 1]
            classification_output: 方向予測ロジット [batch, 3]
        """
        # 1D-CNN Embedding
        x = self.conv_embed(x)  # [batch, seq, d_model]
        
        # Temporal Embedding (optional)
        if self.use_temporal and temporal_info is not None:
            temp_embed = self.temporal_embed(**temporal_info)
            if temp_embed.device != x.device:
                temp_embed = temp_embed.to(x.device)
            x = x + temp_embed
        
        # Positional Encoding
        x = self.pos_encoder(x)
        
        # Transformer Encoder
        x = self.transformer_encoder(x, src_key_padding_mask=src_mask)
        
        # Use last timestep for prediction
        last_hidden = x[:, -1, :]  # [batch, d_model]
        
        # Output heads
        regression_out = self.regression_head(last_hidden)  # [batch, 1]
        classification_out = self.classification_head(last_hidden)  # [batch, 3]
        
        return regression_out, classification_out
    
    def predict_direction(self, x: torch.Tensor) -> int:
        """
        方向を予測（推論用簡易メソッド）
        
        Returns: 0=DOWN, 1=FLAT, 2=UP
        """
        self.eval()
        with torch.no_grad():
            _, class_logits = self.forward(x)
            direction = torch.argmax(class_logits, dim=-1)
        return direction.item()


class TransformerPredictor(PredictionModel):
    """
    Transformerベースの価格予測モデル（ラッパークラス）
    
    Orchestratorから呼び出される統一インターフェース。
    """
    
    def __init__(
        self,
        input_dim: int,
        d_model: int = 64,
        nhead: int = 4,
        num_layers: int = 2,
        device: str = 'cpu'
    ):
        self.device = torch.device(device if torch.cuda.is_available() else 'cpu')
        self.input_dim = input_dim
        
        self.model = FinancialTransformer(
            input_dim=input_dim,
            d_model=d_model,
            nhead=nhead,
            num_layers=num_layers
        ).to(self.device)
        
        self.regression_criterion = nn.MSELoss()
        self.classification_criterion = nn.CrossEntropyLoss()
        self.optimizer = torch.optim.AdamW(self.model.parameters(), lr=0.001, weight_decay=0.01)
        
        self.trained = False
    
    def train(self, X: Any, y_reg: Any, y_cls: Optional[Any] = None) -> float:
        """
        モデルを学習する。
        
        Args:
            X: 入力シーケンス [batch, seq, features]
            y_reg: 回帰ターゲット（価格変化率）[batch, 1]
            y_cls: 分類ターゲット（方向）[batch] (optional)
        
        Returns:
            loss: 学習損失
        """
        self.model.train()
        
        X_tensor = torch.FloatTensor(X).to(self.device)
        y_reg_tensor = torch.FloatTensor(y_reg).to(self.device)
        
        self.optimizer.zero_grad()
        
        reg_out, cls_out = self.model(X_tensor)
        
        # 回帰損失
        loss = self.regression_criterion(reg_out, y_reg_tensor)
        
        # 分類損失（ターゲットがある場合）
        if y_cls is not None:
            y_cls_tensor = torch.LongTensor(y_cls).to(self.device)
            loss += self.classification_criterion(cls_out, y_cls_tensor)
        
        loss.backward()
        
        # Gradient clipping
        torch.nn.utils.clip_grad_norm_(self.model.parameters(), max_norm=1.0)
        
        self.optimizer.step()
        self.trained = True
        
        return loss.item()
    
    def predict(self, X: Any) -> Tuple[np.ndarray, np.ndarray]:
        """
        予測を行う。
        
        Args:
            X: 入力シーケンス [batch, seq, features]
            
        Returns:
            regression_pred: 価格変化率予測 [batch, 1]
            direction_pred: 方向予測（確率）[batch, 3]
        """
        self.model.eval()
        
        with torch.no_grad():
            X_tensor = torch.FloatTensor(X).to(self.device)
            reg_out, cls_out = self.model(X_tensor)
            
            # Softmax for direction probabilities
            direction_probs = F.softmax(cls_out, dim=-1)
        
        return reg_out.cpu().numpy(), direction_probs.cpu().numpy()
    
    def predict_direction(self, X: Any) -> int:
        """
        方向のみを予測（簡易API）。
        
        Returns:
            0 = DOWN, 1 = FLAT, 2 = UP
        """
        _, direction_probs = self.predict(X)
        return int(np.argmax(direction_probs[0]))
    
    def save(self, path: str):
        """モデルを保存"""
        torch.save({
            'model_state_dict': self.model.state_dict(),
            'optimizer_state_dict': self.optimizer.state_dict(),
            'input_dim': self.input_dim,
            'trained': self.trained
        }, path)
    
    def load(self, path: str):
        """モデルを読み込み"""
        checkpoint = torch.load(path, map_location=self.device)
        self.model.load_state_dict(checkpoint['model_state_dict'])
        self.optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
        self.trained = checkpoint['trained']


# =============================================================================
# Kolmogorov-Arnold Network (KAN) Implementation
# 2024年に発表された最新のニューラルネットワークアーキテクチャ
# 従来のMLPよりも解釈可能性が高く、少ないパラメータで高精度を実現
# =============================================================================

class KANLayer(nn.Module):
    """
    Kolmogorov-Arnold Network Layer
    
    従来のMLPが固定活性化関数（ReLU等）をノードに持つのに対し、
    KANは学習可能なスプライン関数をエッジに持つ。
    
    これにより:
    - 少ないパラメータで複雑な関数を近似可能
    - 各スプラインを可視化でき、解釈可能性が高い
    - 時系列予測で高い精度を実現
    """
    
    def __init__(
        self, 
        in_features: int, 
        out_features: int, 
        grid_size: int = 5,
        spline_order: int = 3,
        base_activation: nn.Module = nn.SiLU
    ):
        """
        Args:
            in_features: 入力次元
            out_features: 出力次元
            grid_size: B-splineのグリッドサイズ
            spline_order: B-splineの次数（3 = cubic spline）
            base_activation: ベース活性化関数
        """
        super(KANLayer, self).__init__()
        
        self.in_features = in_features
        self.out_features = out_features
        self.grid_size = grid_size
        self.spline_order = spline_order
        
        # スプラインの係数（学習可能）
        # 各入力-出力ペアに対して grid_size + spline_order 個の係数
        self.spline_coeffs = nn.Parameter(
            torch.randn(out_features, in_features, grid_size + spline_order) * 0.1
        )
        
        # グリッド点（固定）
        # スプラインを評価するためのノード
        grid = torch.linspace(-1, 1, grid_size + 2 * spline_order + 1)
        self.register_buffer('grid', grid)
        
        # ベース活性化関数（残差接続用）
        self.base_activation = base_activation()
        
        # スケーリングパラメータ
        self.base_weight = nn.Parameter(torch.randn(out_features, in_features) * 0.1)
        self.spline_scale = nn.Parameter(torch.ones(out_features, in_features))
        
        # RBF中心点（簡易版: B-splineの代わりにRBFを使用）
        centers = torch.linspace(-1, 1, grid_size)
        self.register_buffer('centers', centers)
        
        # RBF係数（学習可能）
        self.rbf_coeffs = nn.Parameter(
            torch.randn(out_features, in_features, grid_size) * 0.1
        )
        
        # RBF幅パラメータ
        self.rbf_width = nn.Parameter(torch.ones(1) * 0.5)
        
    def compute_rbf_basis(self, x: torch.Tensor) -> torch.Tensor:
        """
        RBF基底関数を計算（B-splineの簡易代替）
        
        Args:
            x: 入力 [batch, in_features], 範囲 [-1, 1]
        Returns:
            基底関数の値 [batch, in_features, grid_size]
        """
        # x: [batch, in_features] -> [batch, in_features, 1]
        x = x.unsqueeze(-1)
        
        # centers: [grid_size] -> [1, 1, grid_size]
        centers = self.centers.view(1, 1, -1)
        
        # RBF: exp(-width * (x - center)^2)
        distances = (x - centers) ** 2
        rbf = torch.exp(-self.rbf_width.abs() * distances)
        
        return rbf
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args:
            x: [batch, in_features]
        Returns:
            [batch, out_features]
        """
        # 入力を[-1, 1]に正規化（tanh）
        x_normalized = torch.tanh(x)
        
        # RBF基底を計算
        rbf = self.compute_rbf_basis(x_normalized)  # [batch, in_features, grid_size]
        
        # スプライン出力を計算
        # rbf_coeffs: [out_features, in_features, grid_size]
        # rbf: [batch, in_features, grid_size]
        # 出力: [batch, out_features]
        spline_output = torch.einsum('oig,big->bo', self.rbf_coeffs, rbf)
        
        # ベース活性化関数からの出力（残差接続）
        base_output = F.linear(self.base_activation(x), self.base_weight)
        
        # 合計
        output = spline_output + base_output
        
        return output


class KAN(nn.Module):
    """
    Kolmogorov-Arnold Network
    
    複数のKANLayerを積み重ねた完全なネットワーク。
    時系列予測やリターン予測に使用可能。
    """
    
    def __init__(
        self, 
        layers: list,  # [input_dim, hidden1, hidden2, ..., output_dim]
        grid_size: int = 5,
        spline_order: int = 3
    ):
        super(KAN, self).__init__()
        
        self.layers = nn.ModuleList()
        for i in range(len(layers) - 1):
            self.layers.append(
                KANLayer(
                    in_features=layers[i],
                    out_features=layers[i + 1],
                    grid_size=grid_size,
                    spline_order=spline_order
                )
            )
    
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        for layer in self.layers:
            x = layer(x)
        return x


class KANForecaster(PredictionModel):
    """
    KANを使った金融時系列予測モデル
    
    Transformerの代替として、またはTransformerの出力層として使用可能。
    """
    
    def __init__(
        self,
        input_dim: int,
        seq_len: int = 60,
        hidden_dims: list = [64, 32],
        grid_size: int = 5,
        learning_rate: float = 0.001,
        device: str = None
    ):
        self.input_dim = input_dim
        self.seq_len = seq_len
        self.hidden_dims = hidden_dims
        self.grid_size = grid_size
        self.learning_rate = learning_rate
        
        if device is None:
            self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        else:
            self.device = torch.device(device)
        
        # ネットワーク構築
        # 入力: flatten(seq_len * input_dim) -> hidden -> output
        flat_input = seq_len * input_dim
        layers = [flat_input] + hidden_dims + [4]  # 4 outputs: regression + 3 classes
        
        self.model = KAN(layers, grid_size=grid_size).to(self.device)
        self.optimizer = torch.optim.AdamW(self.model.parameters(), lr=learning_rate)
        self.trained = False
    
    def train(self, X: Any, y: Any, epochs: int = 50, batch_size: int = 32) -> dict:
        """
        モデルを訓練
        
        Args:
            X: [n_samples, seq_len, features]
            y: [n_samples] or [n_samples, 2] (regression, classification)
        """
        self.model.train()
        
        X_tensor = torch.FloatTensor(X).to(self.device)
        
        if len(y.shape) == 1:
            y_reg = torch.FloatTensor(y).to(self.device)
            y_cls = torch.zeros(len(y), dtype=torch.long).to(self.device)
        else:
            y_reg = torch.FloatTensor(y[:, 0]).to(self.device)
            y_cls = torch.LongTensor(y[:, 1]).to(self.device)
        
        # Flatten input
        X_flat = X_tensor.view(X_tensor.shape[0], -1)
        
        dataset = torch.utils.data.TensorDataset(X_flat, y_reg, y_cls)
        loader = torch.utils.data.DataLoader(dataset, batch_size=batch_size, shuffle=True)
        
        history = {'loss': [], 'reg_loss': [], 'cls_loss': []}
        
        for epoch in range(epochs):
            epoch_loss = 0
            for batch_x, batch_y_reg, batch_y_cls in loader:
                self.optimizer.zero_grad()
                
                output = self.model(batch_x)  # [batch, 4]
                
                reg_pred = output[:, 0]
                cls_pred = output[:, 1:]
                
                reg_loss = F.mse_loss(reg_pred, batch_y_reg)
                cls_loss = F.cross_entropy(cls_pred, batch_y_cls)
                
                loss = reg_loss + 0.5 * cls_loss
                loss.backward()
                self.optimizer.step()
                
                epoch_loss += loss.item()
            
            avg_loss = epoch_loss / len(loader)
            history['loss'].append(avg_loss)
            
            if (epoch + 1) % 10 == 0:
                print(f"KAN Epoch {epoch+1}/{epochs}, Loss: {avg_loss:.6f}")
        
        self.trained = True
        return history
    
    def predict(self, X: Any) -> Tuple[np.ndarray, np.ndarray]:
        """予測"""
        self.model.eval()
        
        with torch.no_grad():
            X_tensor = torch.FloatTensor(X).to(self.device)
            X_flat = X_tensor.view(X_tensor.shape[0], -1)
            
            output = self.model(X_flat)
            
            reg_pred = output[:, 0:1]
            cls_pred = F.softmax(output[:, 1:], dim=-1)
        
        return reg_pred.cpu().numpy(), cls_pred.cpu().numpy()
    
    def predict_direction(self, X: Any) -> int:
        """方向予測"""
        _, cls_probs = self.predict(X)
        return int(np.argmax(cls_probs[0]))
    
    def save(self, path: str):
        """保存"""
        torch.save({
            'model_state_dict': self.model.state_dict(),
            'optimizer_state_dict': self.optimizer.state_dict(),
            'input_dim': self.input_dim,
            'seq_len': self.seq_len,
            'hidden_dims': self.hidden_dims,
            'grid_size': self.grid_size,
            'trained': self.trained
        }, path)
    
    def load(self, path: str):
        """読み込み"""
        checkpoint = torch.load(path, map_location=self.device)
        self.model.load_state_dict(checkpoint['model_state_dict'])
        self.optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
        self.trained = checkpoint['trained']


