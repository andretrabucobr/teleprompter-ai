O ZIP não inclui pesos de reconhecimento de fala.

Execute ANTES da compilação:
  python3 scripts/instalar_modelo.py --model base  # prioriza precisão
ou
  python3 scripts/instalar_modelo.py --model tiny  # prioriza velocidade

O script baixa um pacote oficial multilíngue (não .en) do sherpa-onnx.
Extrai encoder.int8.onnx, decoder.int8.onnx, tokens.txt e gera installed-model.txt.
Para uso offline, use --archive <arquivo-oficial.tar.bz2>.
