import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Roteiro salvo em arquivo no diretório privado do app.
/// Não é necessário criar conta ou enviar conteúdo para um servidor.
class ScriptRepository {
  static const sample = '''Bem-vindo ao Oitosete FlowText!\n\n'''
      '''Este texto pode acompanhar sua fala, ou avançar em velocidade fixa.\n\n'''
      '''Para gravar na câmera do aplicativo, selecione Câmera.\n\n'''
      '''Para controlar de outro celular, abra Controle remoto nos dois aparelhos.''';

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/roteiro_principal.txt');
  }

  Future<String> load() async {
    final file = await _file();
    if (!await file.exists()) return sample;
    return file.readAsString();
  }

  Future<void> save(String text) async {
    final file = await _file();
    await file.writeAsString(text, flush: true);
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
