import 'recorded_audio.dart';

/// Stub para plataformas não-web.
class AudioRecorder {
  Future<bool> start() async => false;
  Future<RecordedAudio?> stop() async => null;
  void cancel() {}
}
