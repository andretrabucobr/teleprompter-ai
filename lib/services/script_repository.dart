import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Roteiro salvo em arquivo no diretório privado do app.
/// Não é necessário criar conta ou enviar conteúdo para um servidor.
class ScriptRepository {
  static const _legacySample = '''Bem-vindo ao Oitosete FlowText!\n\n'''
      '''Este texto pode acompanhar sua fala, ou avançar em velocidade fixa.\n\n'''
      '''Para gravar na câmera do aplicativo, selecione Câmera.\n\n'''
      '''Para controlar de outro celular, abra Controle remoto nos dois aparelhos.''';

  static const sample = '''Olá, bom dia! Hoje eu vou falar com você sobre um novo projeto.

A ideia é simples. Eu quero ler cada palavra com calma e seguir o texto no meu próprio ritmo.

Agora vamos fazer uma pequena pausa. Muito bem, podemos continuar. O trabalho de hoje começa aqui.

Temos 3 etapas e 25 minutos para apresentar a proposta. A tecnologia de IA pode ajudar a nossa equipe.

Vamos voltar a um ponto importante. A ideia é simples. Eu quero ler cada palavra com calma.

Por fim, agradeço a sua atenção. Até a próxima!''';

  /// Atualiza somente o exemplo anterior intacto. Roteiros próprios são preservados.
  static String resolveSavedScript(String saved) =>
      saved == _legacySample ? sample : saved;

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/roteiro_principal.txt');
  }

  Future<String> load() async {
    final file = await _file();
    if (!await file.exists()) return sample;
    return resolveSavedScript(await file.readAsString());
  }

  Future<void> save(String text) async {
    final file = await _file();
    await file.writeAsString(text, flush: true);
  }

  Future<double> loadFontSize() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/fonte.txt');
    try {
      final value = double.tryParse(await file.readAsString());
      return value != null && value.isFinite ? value.clamp(12, 200).toDouble() : 36;
    } catch (_) { return 36; }
  }

  Future<void> saveFontSize(double size) async {
    final directory = await getApplicationDocumentsDirectory();
    await File('${directory.path}/fonte.txt').writeAsString('$size');
  }

  Future<List<String>> listVideos() async {
    final directory = await getApplicationDocumentsDirectory();
    final recordings = Directory('${directory.path}/gravacoes');
    if (!await recordings.exists()) return [];
    final videos = await recordings.list().where((item) =>
        item is File && (item.path.toLowerCase().endsWith('.mp4') ||
            item.path.toLowerCase().endsWith('.mov'))).toList();
    videos.sort((a, b) => b.path.compareTo(a.path));
    return [for (final video in videos) video.path];
  }

  Future<String> persistVideo(String temporaryPath) async {
    final directory = await getApplicationDocumentsDirectory();
    final recordings = Directory('${directory.path}/gravacoes');
    await recordings.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
    final extension = temporaryPath.toLowerCase().endsWith('.mov') ? 'mov' : 'mp4';
    final finalPath = '${recordings.path}/gravacao_$stamp.$extension';
    await File(temporaryPath).copy(finalPath);
    return finalPath;
  }
}


extension RecordedAudioRepository on ScriptRepository {
  Future<String> persistAudio(String temporaryPath) async {
    final directory = await getApplicationDocumentsDirectory();
    final recordings = Directory('${directory.path}/gravacoes');
    await recordings.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final finalPath = '${recordings.path}/audio_separado_$stamp.wav';
    await File(temporaryPath).copy(finalPath);
    return finalPath;
  }
}
