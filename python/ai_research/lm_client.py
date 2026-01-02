# LM Studio Client
# ローカルLLMとの連携クライアント

import requests
from typing import Optional


class LMStudioClient:
    """LM Studio APIクライアント"""

    def __init__(self, base_url: str = "http://localhost:1234"):
        self.base_url = base_url
        self.api_url = f"{base_url}/v1/chat/completions"

    def chat(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 1000,
    ) -> str:
        """LLMにプロンプトを送信してレスポンスを取得"""

        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": prompt})

        # モデルIDを動的に取得
        try:
            models_response = requests.get(f"{self.base_url}/v1/models", timeout=10)
            if models_response.status_code == 200:
                models_data = models_response.json()
                model_id = "local-model"
                for model in models_data.get("data", []):
                    m_id = model.get("id", "")
                    if "embed" not in str(m_id).lower():
                        model_id = m_id
                        break
            else:
                model_id = "local-model"
        except Exception:
            model_id = "local-model"

        payload = {
            "model": model_id,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }

        try:
            response = requests.post(self.api_url, json=payload, timeout=30)
            if response.status_code != 200:
                return f"エラー: {response.status_code} - {response.text}"

            result = response.json()
            return result["choices"][0]["message"]["content"]
        except requests.exceptions.ConnectionError:
            return "エラー: LM Studioが起動していません。localhost:1234 を確認してください。"
        except Exception as e:
            return f"エラー: {str(e)}"

    def analyze_market(self, event_data: str) -> str:
        system_prompt = """あなたはFX市場の専門アナリストです。
経済イベントが為替市場に与える影響を分析し、以下の形式で回答してください：
- 影響度: HIGH/MEDIUM/LOW
- 方向性: 円高/円安/中立
- 推奨アクション: TRADE/WAIT/AVOID
- 理由: 簡潔な説明"""

        return self.chat(event_data, system_prompt, temperature=0.3)

    def analyze_trade_log(self, trade_data: str) -> str:
        system_prompt = """あなたはトレード分析の専門家です。
トレードログを分析し、以下の観点で改善点を提案してください：
- 勝率パターン
- 時間帯の傾向
- ロットサイズの最適化
- リスク管理の改善点"""

        return self.chat(trade_data, system_prompt, temperature=0.5)
