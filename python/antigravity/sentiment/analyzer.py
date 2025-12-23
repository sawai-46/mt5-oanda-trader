import sys
import os
import json
from pathlib import Path

# Add the python directory to sys.path to allow importing ai_research
# Assuming code is running from repo root or antigravity package
current_file = Path(__file__)
repo_root = current_file.parent.parent.parent
python_dir = repo_root / 'python'
if str(python_dir) not in sys.path:
    sys.path.append(str(python_dir))

try:
    from ai_research.lm_client import LMStudioClient
except ImportError:
    print("Warning: Could not import ai_research.lm_client. Sentiment functionality will be disabled.")
    LMStudioClient = None

class SentimentAnalyzer:
    def __init__(self):
        if LMStudioClient:
            self.client = LMStudioClient()
        else:
            self.client = None

    def analyze_news(self, news_text: str) -> float:
        """
        Analyzes news text and returns a sentiment score between -1.0 (Negative) and 1.0 (Positive).
        """
        if not self.client:
            return 0.0

        prompt = f"""
        Analyze the following financial news and provide a sentiment score from -1.0 (Very Bearish) to 1.0 (Very Bullish).
        Return purely the number, nothing else.
        
        News: {news_text}
        """
        
        try:
            response = self.client.chat(prompt)
            # Naive parsing, expecting just a number or valid json
            # In a real system, we'd use better parsing or struct output
            score = float(response.strip())
            return max(-1.0, min(1.0, score))
        except Exception as e:
            print(f"Error analyzing sentiment: {e}")
            return 0.0
