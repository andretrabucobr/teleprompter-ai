#!/usr/bin/env python3
"""Relatório de tamanho real por arquivo APK gerado no GitHub Actions.

Mede bytes do arquivo e das entradas do ZIP APK. Não confunde o tamanho
compactado com o espaço efetivamente ocupado após instalar e copiar modelos.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
from zipfile import ZipFile

MIB = 1024 * 1024


def classify(name: str) -> str:
    name = name.lower()
    if '/models/streaming/' in name or name.startswith('assets/models/streaming/'):
        return 'Modelo de voz: streaming'
    if '/models/whisper/' in name or name.startswith('assets/models/whisper/'):
        return 'Modelo de voz: Whisper'
    if 'sherpa_onnx_web/' in name:
        return 'Recursos WASM/web'
    if name.startswith('lib/'):
        return 'Bibliotecas nativas e Flutter'
    if name.startswith('assets/'):
        return 'Outros assets'
    if name.startswith('res/'):
        return 'Recursos Android'
    if name.endswith('.dex'):
        return 'Código Android (DEX)'
    return 'Outros'


def inspect_apk(apk: Path) -> tuple[int, dict[str, tuple[int, int]]]:
    if not apk.is_file():
        raise FileNotFoundError(f'APK não encontrado: {apk}')
    totals: dict[str, tuple[int, int]] = {}
    with ZipFile(apk) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            name = classify(info.filename)
            compressed, raw = totals.get(name, (0, 0))
            totals[name] = (compressed + info.compress_size, raw + info.file_size)
    return apk.stat().st_size, totals


def mib(n: int) -> str:
    return f'{n / MIB:,.1f} MiB'


def report(apks: list[Path]) -> str:
    lines = [
        '# Relatório de tamanho — Oitosete FlowText',
        '',
        'Medições do arquivo APK; não são medições do espaço total ocupado no celular.',
        'Modelos de voz podem ser copiados para o armazenamento interno na primeira execução.',
        '',
    ]
    for path in apks:
        total, entries = inspect_apk(path)
        lines += [f'## {path.name}', '', f'**Arquivo:** {mib(total)} ({total:,} bytes)', '',
                  '| Categoria | Compactado no APK | Dados sem compressão |',
                  '|---|---:|---:|']
        for cat, (compressed, raw) in sorted(entries.items(), key=lambda kv: kv[1][0], reverse=True):
            lines.append(f'| {cat} | {mib(compressed)} | {mib(raw)} |')
        lines += ['', '']
    return '\n'.join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk-dir', type=Path, default=Path('build/app/outputs/flutter-apk'))
    parser.add_argument('--output', type=Path, default=Path('relatorio_tamanho_build.md'))
    args = parser.parse_args()
    apks = sorted(args.apk_dir.glob('*.apk'))
    if not apks:
        raise SystemExit(f'Nenhum APK encontrado em {args.apk_dir}')
    value = report(apks)
    args.output.write_text(value + '\n', encoding='utf-8')
    print(value)
    summary = os.getenv('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as fd:
            fd.write(value + '\n')


if __name__ == '__main__':
    main()
