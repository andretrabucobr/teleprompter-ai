#!/usr/bin/env python3
"""Instala Nemotron 3.5 INT8 streaming pt-BR para Flutter sem Git LFS.

Downloads oficiais da sherpa-onnx. Modelo com 560 ms de lookahead;
a latência real também depende do dispositivo e da decodificação.
A divisão do encoder em partes de 8 MiB evita carregar ~627 MB em RAM no
primeiro início do aplicativo.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets' / 'models' / 'streaming'
MODEL = 'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11'
ARCHIVE_NAME = MODEL + '.tar.bz2'
URL = f'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/{ARCHIVE_NAME}'
# SHA256 e tamanho da distribuição sherpa-onnx (arquivo fixado).
SHA256 = 'c6bf5e0df765f9d5b43bc9e0536d4b4b3e7d40bdf5ecf13e45f134c51c05ae3a'
SIZE = 475271763
PART_BYTES = 8 * 1024 * 1024
REQUIRED = {'encoder.int8.onnx', 'decoder.int8.onnx', 'joiner.int8.onnx', 'tokens.txt'}
MINIMUM_SIZE = {'encoder.int8.onnx': 400_000_000,
                'decoder.int8.onnx': 1_000_000,
                'joiner.int8.onnx': 1_000_000,
                'tokens.txt': 1024}


def verify_archive(path: Path, expected_sha256: str = SHA256,
                   expected_size: int = SIZE) -> None:
    if path.stat().st_size != expected_size:
        raise ValueError('Tamanho inesperado do arquivo Nemotron; arquivo incompleto?')
    h = hashlib.sha256()
    with path.open('rb') as fd:
        for block in iter(lambda: fd.read(1024 * 1024), b''):
            h.update(block)
    if h.hexdigest() != expected_sha256:
        raise ValueError('SHA256 do modelo inválido. Não instalar um arquivo diferente.')


def extract_model(archive: Path, destination: Path, *,
                  minimum_size: dict[str, int] | None = None,
                  part_bytes: int = PART_BYTES) -> dict:
    """Extrai somente os quatro arquivos conhecidos sem executar paths do TAR."""
    minimum = MINIMUM_SIZE if minimum_size is None else minimum_size
    destination.mkdir(parents=True, exist_ok=True)
    seen: dict[str, int] = {}
    parts: list[str] = []
    with tarfile.open(archive, mode='r|bz2') as tar:
        for member in tar:
            name = Path(member.name).name
            if name not in REQUIRED or not member.isfile():
                continue
            if name in seen:
                raise ValueError(f'Duplicado no TAR: {name}')
            if member.size < minimum[name]:
                raise ValueError(f'Modelo incompleto: {name} ({member.size} bytes)')
            source = tar.extractfile(member)
            if source is None:
                raise ValueError(f'Sem dados: {name}')
            seen[name] = member.size
            copied = 0
            if name == 'encoder.int8.onnx':
                while True:
                    chunk = source.read(part_bytes)
                    if not chunk:
                        break
                    filename = f'encoder.part{len(parts):03d}'
                    (destination / filename).write_bytes(chunk)
                    parts.append(filename)
                    copied += len(chunk)
            else:
                with (destination / name).open('wb') as output:
                    shutil.copyfileobj(source, output)
                copied = (destination / name).stat().st_size
            source.close()
            if copied != member.size:
                raise ValueError(f'Arquivo truncado: {name}')
    if set(seen) != REQUIRED:
        raise ValueError(f'Arquivos faltando no arquivo oficial: {REQUIRED - set(seen)}')
    manifest = {'model': MODEL, 'locale': 'pt-BR', 'sampleRate': 16000,
                'encoderBytes': seen['encoder.int8.onnx'],
                'encoderParts': parts,
                'files': {name: seen[name] for name in sorted(REQUIRED - {'encoder.int8.onnx'})}}
    (destination / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    return manifest


def install(offline_archive: Path | None = None, *,
            expected_sha256: str = SHA256, expected_size: int = SIZE,
            minimum_size: dict[str, int] | None = None,
            part_bytes: int = PART_BYTES) -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='nemotron-', dir=str(DEST)) as temp:
        tmp = Path(temp)
        archive = tmp / ARCHIVE_NAME
        if offline_archive:
            shutil.copyfile(offline_archive, archive)
        else:
            print(f'Baixando Nemotron streaming pt-BR: {URL}', flush=True)
            with urllib.request.urlopen(URL, timeout=120) as response, archive.open('wb') as fd:
                shutil.copyfileobj(response, fd, 1024 * 1024)
        verify_archive(archive, expected_sha256, expected_size)
        extracted = tmp / 'files'
        manifest = extract_model(archive, extracted,
                                 minimum_size=minimum_size,
                                 part_bytes=part_bytes)
        for old in DEST.glob('encoder.part*'):
            old.unlink()
        for entry in extracted.iterdir():
            entry.replace(DEST / entry.name)
        print(f'Modelo pronto: {len(manifest["encoderParts"])} partes no APK; arquivos verificados.', flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, help='Cópia do arquivo .tar.bz2 oficial para build offline')
    args = parser.parse_args()
    install(args.archive)


if __name__ == '__main__':
    main()
