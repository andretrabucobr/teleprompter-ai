#!/usr/bin/env python3
"""Instala os modelos Whisper multilíngues INT8 distribuídos pelo sherpa-onnx.

Small: prioriza reconhecimento de palavras difíceis (mais CPU/memória).
Base: equilíbrio entre precisão e desempenho.
Tiny: prioriza latência e aparelhos com menos recursos.
Nenhuma transcrição é enviada à rede; o download ocorre somente no build.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'assets' / 'models' / 'whisper'
FILENAME = 'installed-model.txt'


def install(model: str, source_archive: Path | None = None) -> None:
    if model not in ('base', 'tiny', 'small'):
        raise ValueError('Modelo desconhecido')
    DEST.mkdir(parents=True, exist_ok=True)
    target_files = ['encoder.int8.onnx', 'decoder.int8.onnx', 'tokens.txt']
    current = (DEST / FILENAME)
    if (current.exists() and current.read_text().strip() == model and
            all((DEST / name).exists() and (DEST / name).stat().st_size > 1024
                for name in target_files)):
        print(f'Modelo multilíngue {model} já instalado em {DEST}')
        return

    with tempfile.TemporaryDirectory(prefix='teleprompter-model-') as tmp:
        staging = Path(tmp)
        archive = staging / 'model.tar.bz2'
        if source_archive is None:
            url = ('https://github.com/k2-fsa/sherpa-onnx/releases/download/'
                   f'asr-models/sherpa-onnx-whisper-{model}.tar.bz2')
            print(f'Baixando modelo Whisper {model} de {url}')
            with urllib.request.urlopen(url, timeout=90) as response, archive.open('wb') as out:
                shutil.copyfileobj(response, out)
        else:
            if not source_archive.is_file():
                raise FileNotFoundError(source_archive)
            shutil.copyfile(source_archive, archive)

        with tarfile.open(archive, 'r:bz2') as tar:
            members = [entry for entry in tar if entry.isfile()]
            for target in target_files:
                names = {f'{model}-{target}', target}
                found = [entry for entry in members if Path(entry.name).name in names]
                if not found:
                    raise RuntimeError(f'O arquivo não contém {model}-{target}.')
                # Arquivo int8 de modelo é grande; evita extrair arquivos extras.
                selected = next((entry for entry in found if
                                 Path(entry.name).name == f'{model}-{target}'), found[0])
                if selected.size <= 1024:
                    raise RuntimeError(f'Arquivo de modelo inválido: {selected.name}')
                source = tar.extractfile(selected)
                if source is None:
                    raise RuntimeError(f'Não foi possível ler {selected.name}')
                with source, (staging / target).open('wb') as output:
                    shutil.copyfileobj(source, output)
                if (staging / target).stat().st_size != selected.size:
                    raise RuntimeError(f'Download incompleto: {target}')
                print(f'Verificado: {target} ({selected.size:,} bytes)')

        # Sinalização gravada por último; instalação interrompida será repetida.
        for target in target_files:
            os.replace(staging / target, DEST / target)
        (DEST / FILENAME).write_text(model + '\n', encoding='utf-8')
    print(f'Modelo Whisper {model} pronto para o build Flutter.')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', choices=['tiny', 'base', 'small'], default='base',
                        help='small = maior precisão potencial; base = equilíbrio; tiny = velocidade. Padrão: base')
    parser.add_argument('--archive', type=Path,
                        help='Opcional: .tar.bz2 oficial já baixado (uso offline)')
    args = parser.parse_args()
    install(args.model, args.archive)


if __name__ == '__main__':
    main()
