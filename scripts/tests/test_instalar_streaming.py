import hashlib
import io
import json
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import instalar_streaming as m


class StreamingInstallerTests(unittest.TestCase):
    def test_stream_extract_and_split(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            archive = root / 'ficticio.tar.bz2'
            sizes = {'encoder.int8.onnx': 70, 'decoder.int8.onnx': 12,
                     'joiner.int8.onnx': 11, 'tokens.txt': 8}
            with tarfile.open(archive, 'w:bz2') as tar:
                for key, n in sizes.items():
                    data = bytes((i % 256 for i in range(n)))
                    entry = tarfile.TarInfo(name=f'model/{key}')
                    entry.size = len(data)
                    tar.addfile(entry, io.BytesIO(data))
            sha = hashlib.sha256(archive.read_bytes()).hexdigest()
            m.verify_archive(archive, sha, archive.stat().st_size)
            folder = root / 'extracted'
            manifest = m.extract_model(archive, folder,
                                       minimum_size={k: 1 for k in sizes},
                                       part_bytes=16)
            self.assertEqual(manifest['encoderParts'],
                             [f'encoder.part{i:03d}' for i in range(5)])
            self.assertEqual(len(b''.join((folder / p).read_bytes() for p in manifest['encoderParts'])), 70)
            self.assertEqual(json.loads((folder / 'manifest.json').read_text())['locale'], 'pt-BR')
            with self.assertRaises(ValueError):
                m.verify_archive(archive, '0' * 64, archive.stat().st_size)


if __name__ == '__main__':
    unittest.main()
