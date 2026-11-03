"""Verificações isoladas do relatório de tamanho (sem Flutter)."""
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
from relatorio_tamanho import inspect_apk, report


class RelatorioTamanhoTests(unittest.TestCase):
    def test_classifica_modelo_e_bibliotecas(self):
        with tempfile.TemporaryDirectory() as root:
            apk = Path(root) / 'app-arm64-v8a-release.apk'
            with zipfile.ZipFile(apk, 'w', compression=zipfile.ZIP_DEFLATED) as dst:
                dst.writestr('assets/flutter_assets/assets/models/streaming/encoder.part000', b'X' * 1024)
                dst.writestr('assets/flutter_assets/assets/models/whisper/tokens.txt', b'abc')
                dst.writestr('lib/arm64-v8a/libapp.so', b'Y' * 64)
            size, entries = inspect_apk(apk)
            self.assertGreater(size, 0)
            self.assertEqual(entries['Modelo de voz: streaming'][1], 1024)
            self.assertEqual(entries['Modelo de voz: Whisper'][1], 3)
            self.assertEqual(entries['Bibliotecas nativas e Flutter'][1], 64)
            self.assertIn('app-arm64-v8a-release.apk', report([apk]))


if __name__ == '__main__':
    unittest.main()
