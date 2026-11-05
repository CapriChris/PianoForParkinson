import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('assistant_server', Path(__file__).resolve().parents[2] / 'tools/assistant_server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

class AssistantContractTests(unittest.TestCase):
    def test_extended_evidence_and_full_history(self):
        body = {
            'request_id': 'a0000000-0000-4000-8000-000000000001',
            'locale': 'zh-Hans', 'question': '查看我的训练表现',
            'history': [{'role': role, 'text': f'message {i}'} for i in range(7) for role in ('user', 'assistant')],
            'context': {'evidence': [{'ref': i, 'kind': 'S2_RHYTHM', 'title': '节奏', 'date': '2026-11-05',
                'metrics': {'result.timing_groups.beat_error_absolute.p95_us': 42.5}} for i in range(1, 10)]},
        }
        allowed = server.validate_request(body)
        self.assertEqual(len(allowed), 9)
        reply = {'answer': 'Piano Companion 中该记录的指标为 42.5 微秒。', 'next_step': None,
            'references': [{'ref': 9, 'metrics': ['result.timing_groups.beat_error_absolute.p95_us']}]}
        self.assertEqual(server.validate_reply(reply, allowed), reply)
        reply['references'][0]['ref'] = 10
        with self.assertRaises(server.ApiError):
            server.validate_reply(reply, allowed)

    def test_brand_and_nonfinite_metric(self):
        self.assertIn('Piano Companion', server.INSTRUCTIONS)
        self.assertIn('琴伴', server.INSTRUCTIONS)
        self.assertNotIn('Qinban', server.INSTRUCTIONS)

if __name__ == '__main__':
    unittest.main()
