#!/usr/bin/env python3
"""Baixa o modelo oficial Vosk PT, verifica a estrutura e empacota no Android."""
import hashlib
import shutil
import tempfile
import urllib.request
import zipfile
from pathlib import Path

URL = 'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip'
ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'android/app/src/main/assets/flowtext-vosk.zip'
PREFIX = 'vosk-model-small-pt-0.3/'

def main():
    DEST.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as folder:
        archive = Path(folder) / 'model.zip'
        with urllib.request.urlopen(URL, timeout=120) as response, archive.open('wb') as out:
            shutil.copyfileobj(response, out)
        if not 20_000_000 < archive.stat().st_size < 50_000_000:
            raise ValueError('Tamanho inesperado do Vosk PT')
        with zipfile.ZipFile(archive) as z:
            names = z.namelist()
            if any(not n.startswith(PREFIX) or '..' in Path(n).parts for n in names):
                raise ValueError('Estrutura inesperada no ZIP Vosk')
            if not any(n.endswith('/final.mdl') for n in names):
                raise ValueError('Modelo acústico ausente')
            if z.testzip() is not None:
                raise ValueError('ZIP corrompido')
        print('Vosk PT SHA256:', hashlib.sha256(archive.read_bytes()).hexdigest())
        shutil.copyfile(archive, DEST)

if __name__ == '__main__':
    main()
