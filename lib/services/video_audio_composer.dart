import 'dart:io';

import 'package:native_video_editor/native_video_editor.dart';
import 'package:path_provider/path_provider.dart';

import 'shared_audio_capture.dart';
import 'wav_pcm_writer.dart';

class VideoAudioResult {
  const VideoAudioResult({
    required this.videoPath,
    this.separateAudioPath,
    this.warning,
  });

  final String videoPath;
  final String? separateAudioPath;
  final String? warning;
  bool get audioMerged => separateAudioPath == null && warning == null;
}

/// Junta o vídeo sem som do plugin camera à faixa criada pelo PCM compartilhado.
/// Preserva os originais quando o muxer da plataforma falha.
class VideoAudioComposer {
  static Future<VideoAudioResult> combine({
    required String silentVideoPath,
    required CapturedAudio audio,
    required int startSample,
    required int stopSample,
  }) async {
    final endSample = stopSample.clamp(0, audio.sampleCount);
    final beginSample = startSample.clamp(0, endSample);
    if (endSample <= beginSample) {
      return VideoAudioResult(
        videoPath: silentVideoPath,
        separateAudioPath: audio.wavPath,
        warning: 'Nenhum áudio foi recebido durante a gravação da câmera.',
      );
    }

    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final wavClip = '${tmp.path}/faixa_$stamp.wav';
    try {
      await WavPcmWriter.clip(
        source: audio.wavPath,
        destination: wavClip,
        firstSample: beginSample,
        lastSample: endSample,
        sampleRate: audio.sampleRate,
      );
    } catch (e) {
      return VideoAudioResult(
        videoPath: silentVideoPath,
        separateAudioPath: audio.wavPath,
        warning: 'Falha ao recortar áudio do microfone: $e',
      );
    }
    final composed = '${tmp.path}/video_com_audio_$stamp.mp4';
    try {
      final result = await NativeVideoEditor.mergeAudioIntoVideo(
        AudioMergeRequest(
          inputVideoPath: silentVideoPath,
          audioPath: wavClip,
          outputPath: composed,
          replaceExistingAudio: true,
        ),
      );
      if (!await File(result).exists() || await File(result).length() == 0) {
        throw StateError('Editor não produziu MP4 com áudio.');
      }
      await File(wavClip).delete();
      await File(audio.wavPath).delete();
      return VideoAudioResult(videoPath: result);
    } catch (e) {
      return VideoAudioResult(
        videoPath: silentVideoPath,
        separateAudioPath: wavClip,
        warning: 'Falha ao unir áudio/vídeo no dispositivo: $e',
      );
    }
  }
}
