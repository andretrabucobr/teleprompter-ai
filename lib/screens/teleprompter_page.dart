import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/script_matcher.dart';
import '../core/speech_alignment_tracker.dart';
import '../services/remote_session.dart';
import '../services/shared_audio_capture.dart';
import '../services/video_audio_composer.dart';
import '../services/script_repository.dart';
import '../services/speech_follow_service.dart';
import 'remote_controller_page.dart';

enum PrompterMode { external, camera }
enum ScrollMode { speed, voice }

class TeleprompterPage extends StatefulWidget {
  const TeleprompterPage({super.key});

  @override
  State<TeleprompterPage> createState() => _TeleprompterPageState();
}

class _TeleprompterPageState extends State<TeleprompterPage>
    with WidgetsBindingObserver {
  final _repository = ScriptRepository();
  final _script = TextEditingController(text: ScriptRepository.sample);
  final _scroll = ScrollController();
  late final SpeechFollowService _speech = SpeechFollowService(
    onTranscript: _onTranscript,
    onStatus: (status) {
      if (mounted) setState(() => _voiceStatus = status);
    },
    onError: (message) {
      if (mounted) {
        setState(() => _voiceStatus = message);
        _notice(message);
      }
    },
  );
  late final SharedAudioCapture _capture = SharedAudioCapture(
    onTranscript: _onTranscript,
    onStatus: (status) {
      if (mounted) setState(() => _voiceStatus = status);
    },
  );
  ScriptMatcher _matcher = ScriptMatcher(ScriptRepository.sample);
  late SpeechAlignmentTracker _tracker = SpeechAlignmentTracker(_matcher);
  RemoteHost? _host;
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  Timer? _ticker;
  Timer? _saveTimer;

  PrompterMode _mode = PrompterMode.external;
  ScrollMode _scrollMode = ScrollMode.speed;
  bool _editing = true;
  bool _playing = false;
  bool _mirror = false;
  bool _recording = false;
  bool _cameraBusy = false;
  bool _recordingBusy = false;
  bool _playPending = false;
  int _playGeneration = 0;
  bool _remoteConnected = false;
  bool _allowRemoteRecording = false;
  double _fontSize = 36;
  double _speed = 40;
  double _viewerWidth = 320;
  double _viewerHeight = 400;
  int _activeIndex = -1;
  String _voiceStatus = 'Inativo';
  String _lastRecognizedText = '';
  String? _cameraError;
  String? _latestVideo;
  String? _latestAudio;
  int _recordStartSample = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _script.addListener(_scriptChanged);
    _load();
  }

  Future<void> _load() async {
    try {
      final content = await _repository.load();
      final savedVideos = await _repository.listVideos();
      if (mounted) {
        _script.text = content;
        setState(() {
          _matcher = ScriptMatcher(content);
          _tracker = SpeechAlignmentTracker(_matcher);
          if (savedVideos.isNotEmpty) _latestVideo = savedVideos.first;
        });
      }
    } catch (e) {
      if (mounted) _notice('Não foi possível abrir o roteiro salvo: $e');
    }
  }

  void _scriptChanged() {
    _matcher = ScriptMatcher(_script.text);
    _tracker = SpeechAlignmentTracker(_matcher);
    _activeIndex = -1;
    _lastRecognizedText = '';
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        await _repository.save(_script.text);
      } catch (e) {
        if (mounted) _notice('Falha ao salvar roteiro: $e');
      }
    });
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  void _broadcast() => _host?.sendState();

  Map<String, dynamic> _snapshot() => {
        'playing': _playing,
        'mode': _mode == PrompterMode.camera ? 'camera' : 'external',
        'scrollMode': _scrollMode.name,
        'mirror': _mirror,
        'speed': _speed,
        'fontSize': _fontSize,
        'activeIndex': _activeIndex,
        'recording': _recording,
        'voiceListening': _capture.followingVoice || _speech.running,
      };

  void _onTranscript(String transcript, bool isFinal) {
    if (!_playing || _scrollMode != ScrollMode.voice || !mounted) return;
    final position = _tracker.accept(transcript, isFinal: isFinal);
    final trimmed = transcript.trim();
    if (trimmed.isNotEmpty) {
      setState(() => _lastRecognizedText = trimmed.length > 100
          ? trimmed.substring(trimmed.length - 100) : trimmed);
    }
    if (position == null || position == _activeIndex) return;
    setState(() => _activeIndex = position);
    _scrollToActive();
    _broadcast();
  }

  TextStyle _readingStyle() => TextStyle(
        fontSize: _fontSize,
        color: Colors.white,
        height: 1.5,
        fontWeight: FontWeight.w600,
      );

  void _scrollToActive() {
    if (_activeIndex < 0 || _activeIndex >= _matcher.words.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final word = _matcher.words[_activeIndex];
      final painter = TextPainter(
        text: TextSpan(text: _script.text, style: _readingStyle()),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textScaler: MediaQuery.textScalerOf(context),
      );
      try {
        painter.layout(maxWidth: math.max(1.0, _viewerWidth - 48));
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        );
        if (boxes.isEmpty) return;
        final topPadding = _viewerHeight * .3;
        final destination = (boxes.first.top + topPadding - _viewerHeight * .36)
            .clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
        _scroll.animateTo(
          destination,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } finally {
        painter.dispose();
      }
    });
  }

  void _tick(Timer _) {
    if (!_playing || _scrollMode != ScrollMode.speed || !_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    final next = math.min(end, _scroll.offset + _speed / 30);
    _scroll.jumpTo(next);
    if (next >= end) _pause();
  }

  Future<void> _play() async {
    if (_playing || _playPending) return;
    _playPending = true;
    final generation = ++_playGeneration;
    try {
      if (_matcher.words.isEmpty) {
        throw StateError('Escreva um roteiro para começar.');
      }
      if (_scrollMode == ScrollMode.voice) {
        if (_mode == PrompterMode.camera) {
          // Mesmo fluxo PCM usado para salvar a voz da gravação.
          await _capture.start(followVoice: true);
        } else {
          // No leitor externo, prioriza o mesmo ASR offline de gravação.
          // Se o modelo não estiver instalado, usa API nativa como fallback.
          try {
            await _capture.start(followVoice: true, saveAudio: false);
          } catch (offlineError) {
            if (mounted) setState(() => _voiceStatus =
                'Modelo local não disponível, usando reconhecimento nativo.');
            final ready = await _speech.start();
            if (!ready) {
              throw StateError('ASR offline e nativo indisponíveis: $offlineError');
            }
          }
        }
        if (generation != _playGeneration) {
          if (_capture.running && !_recording) await _capture.discard();
          if (_speech.running) await _speech.stop();
          return;
        }
      } else {
        _ticker?.cancel();
        _ticker = Timer.periodic(const Duration(milliseconds: 33), _tick);
      }
      if (mounted) {
        setState(() { _editing = false; _playing = true; });
      }
      _broadcast();
    } catch (e) {
      if (mounted) _notice('Não foi possível iniciar a leitura: $e');
      rethrow;
    } finally {
      _playPending = false;
    }
  }

  Future<void> _pause() async {
    // Não solta o microfone enquanto a inicialização do vídeo está em curso.
    if (_recordingBusy && !_recording) return;
    ++_playGeneration;
    _ticker?.cancel();
    if (_speech.running) await _speech.stop();
    // Ao pausar a leitura durante um vídeo, o microfone segue gravando.
    if (_recording && _capture.running) {
      _capture.pauseFollowing(); // O WAV continua, mesmo com o texto pausado.
    } else if (_capture.running) {
      await _capture.discard();
    }
    if (mounted) setState(() => _playing = false);
    _broadcast();
  }

  Future<void> _restart() async {
    await _pause();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _tracker.seek(-1);
    if (mounted) setState(() => _activeIndex = -1);
    _broadcast();
  }

  void _seek(int delta) {
    if (_matcher.words.isEmpty) return;
    final next = (_activeIndex + delta).clamp(0, _matcher.words.length - 1).toInt();
    _tracker.seek(next);
    setState(() => _activeIndex = next);
    _scrollToActive();
    _broadcast();
  }

  Future<void> _changeScrollMode(ScrollMode mode) async {
    if (_recording || _recordingBusy) {
      _notice('Finalize a gravação antes de trocar o modo de leitura.');
      return;
    }
    await _pause();
    if (mounted) setState(() => _scrollMode = mode);
    _broadcast();
  }

  Future<void> _changeMode(PrompterMode mode) async {
    if (_recording || _recordingBusy || _cameraBusy || mode == _mode) return;
    await _pause();
    if (mode == PrompterMode.camera) {
      await _initCamera();
      // Mantém a seleção Voz, agora suportada com o motor PCM local.
    } else {
      final previous = _camera;
      _camera = null;
      await previous?.dispose();
    }
    if (mounted) setState(() => _mode = mode);
    _broadcast();
  }

  Future<void> _initCamera({bool changeLens = false}) async {
    if (_cameraBusy || _recording) return;
    setState(() { _cameraBusy = true; _cameraError = null; });
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw StateError('Nenhuma câmera encontrada.');
      CameraDescription selected;
      final old = _camera?.description;
      if (changeLens && old != null) {
        selected = _cameras.firstWhere(
          (camera) => camera.lensDirection != old.lensDirection,
          orElse: () => _cameras.first,
        );
      } else {
        selected = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras.first,
        );
      }
      final previous = _camera;
      _camera = null;
      await previous?.dispose();
      // Crucial: somente SharedAudioCapture abre o microfone.
      final next = CameraController(selected, ResolutionPreset.high, enableAudio: false);
      await next.initialize();
      if (!mounted) { await next.dispose(); return; }
      setState(() => _camera = next);
    } catch (e) {
      if (mounted) setState(() => _cameraError = 'Câmera indisponível: $e');
    } finally {
      if (mounted) setState(() => _cameraBusy = false);
    }
  }

  Future<void> _startRecording() async {
    if (_recordingBusy || _recording) return;
    if (_mode != PrompterMode.camera || _camera?.value.isInitialized != true) {
      _notice('Abra o modo Câmera e conceda as permissões.');
      throw StateError('Câmera não preparada.');
    }
    _recordingBusy = true;
    try {
      if (mounted && _editing) setState(() => _editing = false);
      // O microfone é aberto apenas aqui (ou já estava aberto pela leitura).
      await _capture.start(followVoice: _scrollMode == ScrollMode.voice);
      if (_scrollMode == ScrollMode.voice && !_playing) {
        // Iniciar gravação no modo Voz também inicia a leitura inteligente.
        await _play();
      }
      final startBefore = _capture.sampleCount;
      await _camera!.startVideoRecording();
      // Estimativa entre chamada/retorno, não timestamps nativos exatos.
      _recordStartSample = (startBefore + _capture.sampleCount) ~/ 2;
      if (mounted) setState(() => _recording = true);
      _broadcast();
    } catch (e) {
      ++_playGeneration;
      _ticker?.cancel();
      if (mounted) setState(() => _playing = false);
      if (!_recording && _capture.running) await _capture.discard();
      _notice('Não foi possível iniciar a gravação com áudio: $e');
      rethrow;
    } finally {
      _recordingBusy = false;
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording || _camera == null || _recordingBusy) return;
    _recordingBusy = true;
    bool videoStopped = false;
    try {
      final stopBefore = _capture.sampleCount;
      final captured = await _camera!.stopVideoRecording();
      videoStopped = true;
      final stopSample = (stopBefore + _capture.sampleCount) ~/ 2;
      final sourceWav = _capture.currentWavPath;
      CapturedAudio? audio;
      late VideoAudioResult composed;
      try {
        audio = await _capture.stop();
        if (audio == null) throw StateError('Áudio do microfone ausente.');
        composed = await VideoAudioComposer.combine(
          silentVideoPath: captured.path,
          audio: audio,
          startSample: _recordStartSample,
          stopSample: stopSample,
        );
      } catch (e) {
        // Nunca descarta o vídeo apenas por erro na transcrição/na faixa PCM.
        try { if (_capture.running) await _capture.stop(); }
        catch (_) { /* a gravação da câmera já terminou */ }
        composed = VideoAudioResult(
          videoPath: captured.path,
          separateAudioPath: sourceWav != null && await File(sourceWav).exists()
              ? sourceWav : null,
          warning: 'A composição falhou; o vídeo foi preservado sem som. $e',
        );
      }
      final saved = await _repository.persistVideo(composed.videoPath);
      String? separateAudio;
      if (composed.separateAudioPath != null &&
          await File(composed.separateAudioPath!).length() > 44) {
        separateAudio = await _repository.persistAudio(composed.separateAudioPath!);
      }
      if (mounted) {
        setState(() { _latestVideo = saved; _latestAudio = separateAudio; });
        if (composed.warning == null) {
          _notice('Vídeo com áudio salvo no aplicativo.');
        } else {
          _notice('Vídeo preservado. Verifique se o áudio foi exportado '
              'separadamente. ${composed.warning}');
        }
      }
      // Limpa apenas arquivos temporários; preserva as cópias persistidas.
      for (final path in <String>{captured.path, composed.videoPath,
        if (audio != null) audio.wavPath,
        if (composed.separateAudioPath != null) composed.separateAudioPath!}) {
        try { if (await File(path).exists()) await File(path).delete(); }
        catch (_) { /* limpeza opcional */ }
      }
    } catch (e) {
      _notice('Falha ao salvar a gravação: $e');
      rethrow;
    } finally {
      _recordingBusy = false;
      if (mounted) setState(() => _recording = _camera?.value.isRecordingVideo ?? false);
      if (videoStopped) await _pause();
      _broadcast();
    }
  }

  Future<void> _shareVideo() async {
    if (_latestVideo == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(_latestVideo!), if (_latestAudio != null) XFile(_latestAudio!)],
          text: _latestAudio == null
              ? 'Gravação Teleprompter AI'
              : 'Gravação Teleprompter AI (vídeo e áudio separados)',
        ),
      );
    } catch (e) {
      _notice('Falha ao exportar gravação: $e');
    }
  }

  Future<void> _onRemoteCommand(String command, dynamic value) async {
    switch (command) {
      case 'play':
        if (_editing) setState(() => _editing = false);
        await _play();
      case 'pause':
        await _pause();
      case 'reset':
        await _restart();
      case 'seek':
        if (value is! num) throw StateError('Posição inválida.');
        _seek(value.toInt().clamp(-100, 100).toInt());
      case 'set_speed':
        if (value is! num) throw StateError('Velocidade inválida.');
        setState(() => _speed = value.toDouble().clamp(10, 140).toDouble());
      case 'set_font_size':
        if (value is! num) throw StateError('Fonte inválida.');
        setState(() => _fontSize = value.toDouble().clamp(20, 72).toDouble());
        _scrollToActive();
      case 'set_mirror':
        if (value is! bool) throw StateError('Espelhamento inválido.');
        setState(() => _mirror = value);
      case 'record_start':
        if (mounted && _editing) setState(() => _editing = false);
        if (!_allowRemoteRecording) {
          throw StateError('Autorize a gravação remota no celular principal.');
        }
        await _startRecording();
      case 'record_stop':
        await _stopRecording();
    }
    _broadcast();
  }

  Future<void> _showHostPairing() async {
    _host ??= RemoteHost(
      onCommand: _onRemoteCommand,
      currentState: _snapshot,
      onConnection: (connected) {
        if (mounted) setState(() => _remoteConnected = connected);
      },
    );
    try {
      final pairing = await _host!.start();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Parear controle remoto',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                const Text('Abra este mesmo aplicativo no segundo celular, '
                    'toque em "Ser controle" e escaneie o código.'),
                const SizedBox(height: 18),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(data: pairing.qrData, size: 190),
                ),
                const SizedBox(height: 14),
                SelectableText('IP: ${pairing.host}   Porta: ${pairing.port}'),
                SelectableText('PIN: ${pairing.pin}',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 14),
                SwitchListTile(
                  title: const Text('Permitir iniciar gravação remotamente'),
                  subtitle: const Text('Desativado por padrão. O app principal '
                      'precisa estar aberto e com a câmera preparada.'),
                  value: _allowRemoteRecording,
                  onChanged: (value) {
                    setState(() => _allowRemoteRecording = value);
                    setSheetState(() {});
                  },
                ),
                const Text('Somente Wi-Fi de confiança. O tráfego da versão '
                    'experimental ainda não é criptografado.'),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _host?.stop();
                    if (mounted) setState(() => _remoteConnected = false);
                  },
                  icon: const Icon(Icons.link_off),
                  label: const Text('Encerrar pareamento e conexão'),
                ),
              ]),
            ),
          ),
        ),
      );
    } catch (e) {
      _notice('Não foi possível abrir o controle remoto: $e');
    }
  }

  List<InlineSpan> _styledText() {
    final result = <InlineSpan>[];
    final text = _script.text;
    var cursor = 0;
    for (var i = 0; i < _matcher.words.length; i++) {
      final word = _matcher.words[i];
      if (word.start > cursor) result.add(TextSpan(text: text.substring(cursor, word.start)));
      result.add(TextSpan(
        text: text.substring(word.start, word.end),
        style: i == _activeIndex
            ? const TextStyle(color: Colors.black, backgroundColor: Color(0xFF4AE4CA))
            : i < _activeIndex
                ? const TextStyle(color: Colors.white60)
                : null,
      ));
      cursor = word.end;
    }
    if (cursor < text.length) result.add(TextSpan(text: text.substring(cursor)));
    return result;
  }

  Widget _reader() => LayoutBuilder(
        builder: (context, constraints) {
          _viewerWidth = constraints.maxWidth;
          _viewerHeight = constraints.maxHeight;
          final cameraReady = _mode == PrompterMode.camera &&
              _camera != null && _camera!.value.isInitialized;
          return Stack(fit: StackFit.expand, children: [
            if (cameraReady) CameraPreview(_camera!),
            if (_mode == PrompterMode.camera)
              Container(color: Colors.black.withValues(alpha: .34)),
            if (_mode == PrompterMode.camera && !cameraReady)
              Center(child: Text(_cameraError ?? 'Preparando câmera...',
                  textAlign: TextAlign.center)),
            Transform.flip(
              flipX: _mirror,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(24, _viewerHeight * .3, 24, _viewerHeight * .75),
                child: Text.rich(
                  TextSpan(style: _readingStyle(), children: _styledText()),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            IgnorePointer(
              child: Align(
                alignment: const Alignment(0, -.25),
                child: Container(height: 2, color: Colors.tealAccent.withValues(alpha: .45)),
              ),
            ),
            if (_recording)
              const Positioned(
                top: 12, left: 12,
                child: Row(children: [Icon(Icons.fiber_manual_record, color: Colors.redAccent),
                  SizedBox(width: 6), Text('GRAVANDO')]),
              ),
          ]);
        },
      );

  Widget _readerControls() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: SegmentedButton<ScrollMode>(
              segments: const [
                ButtonSegment(value: ScrollMode.speed, label: Text('Velocidade'), icon: Icon(Icons.speed)),
                ButtonSegment(value: ScrollMode.voice, label: Text('Voz'), icon: Icon(Icons.mic)),
              ],
              selected: {_scrollMode},
              onSelectionChanged: _recording ? null : (value) {
                _changeScrollMode(value.first);
              },
            )),
            IconButton(
              tooltip: 'Modo espelho',
              isSelected: _mirror,
              onPressed: () { setState(() => _mirror = !_mirror); _broadcast(); },
              icon: const Icon(Icons.flip),
            ),
          ]),
          if (_scrollMode == ScrollMode.voice) ...[
            Text(_mode == PrompterMode.camera
                    ? 'Voz offline (Whisper + filtro de silêncio): $_voiceStatus'
                    : 'Voz offline, com fallback nativo: $_voiceStatus',
                maxLines: 2, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            if (_lastRecognizedText.isNotEmpty)
              Text('Ouvido: $_lastRecognizedText',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
          ],
          Row(children: [
            const Text('A'),
            Expanded(child: Slider(
              min: 20, max: 72, value: _fontSize,
              onChanged: (value) { setState(() => _fontSize = value); _broadcast(); },
            )),
            Text('${_fontSize.round()}'),
            const SizedBox(width: 8),
            const Icon(Icons.speed, size: 18),
            Expanded(child: Slider(
              min: 10, max: 140, value: _speed,
              onChanged: _scrollMode == ScrollMode.speed ? (value) {
                setState(() => _speed = value);
                _broadcast();
              } : null,
            )),
          ]),
          Row(children: [
            IconButton(tooltip: 'Voltar 12 palavras',
                onPressed: () => _seek(-12), icon: const Icon(Icons.fast_rewind)),
            Expanded(child: FilledButton.icon(
              onPressed: () async {
                if (_playing) {
                  await _pause();
                } else {
                  try { await _play(); } catch (_) { /* mensagem já exibida */ }
                }
              },
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              label: Text(_playing ? 'Pausar' : 'Iniciar'),
            )),
            IconButton(tooltip: 'Avançar 12 palavras',
                onPressed: () => _seek(12), icon: const Icon(Icons.fast_forward)),
            IconButton(tooltip: 'Reiniciar', onPressed: _restart,
                icon: const Icon(Icons.restart_alt)),
            if (_mode == PrompterMode.camera)
              IconButton(
                tooltip: _recording ? 'Parar gravação' : 'Gravar vídeo',
                icon: Icon(_recording ? Icons.stop_circle : Icons.fiber_manual_record,
                    color: Colors.redAccent),
                onPressed: _recordingBusy ? null : () async {
                  try {
                    if (_recording) {
                      await _stopRecording();
                    } else {
                      await _startRecording();
                    }
                  } catch (_) { /* erro detalhado via SnackBar */ }
                },
              ),
          ]),
          if (_latestVideo != null)
            TextButton.icon(
              onPressed: _shareVideo,
              icon: const Icon(Icons.ios_share),
              label: const Text('Exportar última gravação'),
            ),
        ]),
      );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // O MVP é concebido para uso em primeiro plano. Não inicia gravação
    // ou reconhecimento a partir do segundo plano.
    if (state == AppLifecycleState.paused) {
      if (_recording) {
        _stopRecording().catchError((Object _) {});
      } else {
        _pause().catchError((Object _) {});
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _saveTimer?.cancel();
    _speech.dispose();
    _capture.discard().catchError((Object _) {});
    _host?.stop();
    _camera?.dispose();
    _script.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Teleprompter AI'),
          actions: [
            if (_remoteConnected)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.cast_connected, color: Colors.greenAccent)),
            PopupMenuButton<String>(
              tooltip: 'Controle remoto',
              icon: const Icon(Icons.settings_remote),
              onSelected: (action) {
                if (action == 'host') {
                  _showHostPairing();
                } else {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const RemoteControllerPage(),
                  ));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'host', child: Text('Exibir QR para ser controlado')),
                PopupMenuItem(value: 'controller', child: Text('Ser controle de outro aparelho')),
              ],
            ),
            IconButton(
              tooltip: _editing ? 'Abrir leitor' : 'Editar roteiro',
              icon: Icon(_editing ? Icons.chrome_reader_mode : Icons.edit_note),
              onPressed: _recording ? null : () async {
                await _pause();
                if (mounted) setState(() => _editing = !_editing);
              },
            ),
          ],
        ),
        body: SafeArea(child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              Expanded(child: ChoiceChip(
                label: const Text('Leitor externo'),
                selected: _mode == PrompterMode.external,
                onSelected: _recording || _recordingBusy ? null : (_) => _changeMode(PrompterMode.external),
              )),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(
                label: const Text('Câmera integrada'),
                selected: _mode == PrompterMode.camera,
                onSelected: _recording || _recordingBusy ? null : (_) => _changeMode(PrompterMode.camera),
              )),
              if (_mode == PrompterMode.camera)
                IconButton(
                  tooltip: 'Trocar câmera',
                  onPressed: _recording || _recordingBusy || _cameraBusy ? null : () => _initCamera(changeLens: true),
                  icon: const Icon(Icons.cameraswitch),
                ),
            ]),
          ),
          Expanded(
            child: _editing
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _script,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Edite seu roteiro (salvo automaticamente)',
                        alignLabelWithHint: true,
                      ),
                    ),
                  )
                : _reader(),
          ),
          if (_editing)
            Padding(
              padding: const EdgeInsets.all(14),
              child: FilledButton.icon(
                onPressed: () => setState(() => _editing = false),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Abrir teleprompter'),
              ),
            )
          else
            _readerControls(),
        ])),
      );
}
