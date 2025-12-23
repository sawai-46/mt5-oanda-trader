import unittest
from antigravity.core.orchestrator import AntigravityOrchestrator

class TestIntegration(unittest.TestCase):
    def test_orchestrator(self):
        orch = AntigravityOrchestrator()
        
        # Simulate a bar
        bar_data = {
            'Open': 150.0,
            'High': 151.0,
            'Low': 149.0,
            'Close': 150.5,
            'Volume': 5000
        }
        
        # Test with news
        result = orch.process_bar(bar_data, news="Market is booming with positive earnings.")
        
        print("Orchestrator Result:", result)
        self.assertIn('action', result)
        self.assertIn('vpin', result)
        self.assertIn('sentiment', result)

if __name__ == '__main__':
    unittest.main()
