import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:picovoice_flutter/picovoice_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceControl Timer',
      theme: ThemeData(primarySwatch: Colors.blue, brightness: Brightness.dark),
      home: const TimerPage(),
    );
  }
}

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});
  @override
  TimerPageState createState() => TimerPageState();
}

class TimerPageState extends State<TimerPage> {
  final FlutterTts flutterTts = FlutterTts();
  Timer? timer;
  int timeMilliseconds = 0;
  bool isActive = false;
  double volume = 0.5;
  int intervalSeconds = 10;
  // Голосовое распознавание включено по умолчанию.
  bool voiceRecognitionEnabled = true;
  PicovoiceManager? _picovoiceManager;

  @override
  void initState() {
    super.initState();
    debugPrint("initState: Начало инициализации TimerPage");
    _loadVoiceRecognitionSetting();
    timer = Timer.periodic(
      const Duration(milliseconds: 10),
      (_) => _handleTick(),
    );
    flutterTts.setVolume(volume);
    if (voiceRecognitionEnabled) {
      _initRhino();
    } else {
      debugPrint("Voice recognition отключено по настройкам");
    }
  }

  Future<void> _loadVoiceRecognitionSetting() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? enabled = prefs.getBool('voiceRecognitionEnabled');
    debugPrint("Loaded voiceRecognitionEnabled: $enabled");
    if (enabled != null) {
      setState(() {
        voiceRecognitionEnabled = enabled;
      });
    }
  }

  Future<void> _updateVoiceRecognitionSetting(bool enabled) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voiceRecognitionEnabled', enabled);
    setState(() {
      voiceRecognitionEnabled = enabled;
    });
    debugPrint("Voice recognition setting updated: $enabled");
    if (enabled) {
      _initRhino();
    } else {
      await _picovoiceManager?.stop();
      _picovoiceManager?.delete();
      setState(() {
        _picovoiceManager = null;
      });
      debugPrint("Rhino остановлен, так как голосовое распознавание выключено");
    }
  }

  /// Загружает файл ассета и сохраняет его во временной директории,
  /// возвращая абсолютный путь к файлу.
  Future<String> _loadAssetToFile(String assetPath, String fileName) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return file.path;
  }

  Future<void> _initRhino() async {
    try {
      debugPrint("Initializing Rhino...");
      // Замените на ваш реальный access key.
      String accessKey =
          "P780lAn7uY/24n6Ns7KDEiMu/FguauqQWLSwG99l2P8c0N3Ymtmlig==";
      String assetContextPath =
          "assets/picovoice/voice_control_timer_en_android_v3_0_0.rhn";
      // Копируем файл ассета во временную директорию.
      String contextPath = await _loadAssetToFile(
        assetContextPath,
        "voice_control_timer_en_android_v3_0_0.rhn",
      );
      // Проверяем, существует ли файл и его размер.
      final file = File(contextPath);
      bool exists = await file.exists();
      int size = exists ? await file.length() : 0;
      debugPrint("Файл контекста существует: $exists, размер: $size байт");

      debugPrint("AccessKey: $accessKey");
      debugPrint("ContextPath (temp): $contextPath");
      // Вызываем PicovoiceManager.create с 5 позиционными аргументами для inference-only режима.
      _picovoiceManager = await PicovoiceManager.create(
        accessKey,
        "", // keywordPath (не используется)
        () {}, // wakeWordCallback (не используется)
        contextPath,
        _inferenceCallback,
      );
      await _picovoiceManager!.start();
      debugPrint("Rhino started successfully");
      setState(() {});
    } catch (e) {
      debugPrint("Failed to initialize Rhino: $e");
      setState(() {
        _picovoiceManager = null;
      });
    }
  }

  void _inferenceCallback(dynamic inference) {
    debugPrint("Received inference callback: $inference");
    if (inference != null && inference['isUnderstood'] == true) {
      debugPrint("Recognized intent: ${inference['intent']}");
      switch (inference['intent']) {
        case "start":
          _startTimer();
          break;
        case "stop":
          _pauseTimer();
          break;
        case "reset":
          _resetTimer();
          break;
        default:
          debugPrint("Unknown command: ${inference['intent']}");
      }
    } else {
      debugPrint("Command not understood");
    }
  }

  void _handleTick() {
    if (isActive) {
      setState(() {
        timeMilliseconds += 10;
      });
      int totalSeconds = timeMilliseconds ~/ 1000;
      int minutes = totalSeconds ~/ 60;
      int seconds = totalSeconds % 60;
      if (totalSeconds > 0 && totalSeconds % intervalSeconds == 0) {
        String announcement =
            seconds == 0
                ? "$minutes minute${minutes > 1 ? "s" : ""}"
                : "${minutes > 0 ? "$minutes minute${minutes > 1 ? "s" : ""} and " : ""}$seconds second${seconds != 1 ? "s" : ""}";
        flutterTts.speak(announcement);
      }
    }
  }

  String _formattedTime() {
    double seconds = (timeMilliseconds / 1000) % 60;
    int minutes = (timeMilliseconds / (1000 * 60)).floor();
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}";
  }

  void _startTimer() {
    if (!isActive) {
      flutterTts.speak("Timer started");
      setState(() {
        isActive = true;
      });
    } else {
      flutterTts.speak("Timer is already running");
    }
  }

  void _pauseTimer() {
    if (isActive) {
      flutterTts.speak("Timer paused at ${_formattedTime()}");
      setState(() {
        isActive = false;
      });
    } else {
      flutterTts.speak("Timer is not running");
    }
  }

  void _resetTimer() {
    flutterTts.speak("Timer reset");
    setState(() {
      isActive = false;
      timeMilliseconds = 0;
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _picovoiceManager?.stop();
    _picovoiceManager?.delete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String formattedTime = _formattedTime();
    return Scaffold(
      appBar: AppBar(
        title: const Text("VoiceControl Timer"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SettingsPage(state: this)),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Если _picovoiceManager != null, значит распознавание запущено (иконка зелёная).
            if (voiceRecognitionEnabled && _picovoiceManager != null)
              const Icon(Icons.mic, color: Colors.green, size: 40)
            else
              const Icon(Icons.mic_off, color: Colors.red, size: 40),
            const SizedBox(height: 10),
            Text(
              formattedTime,
              style: const TextStyle(fontSize: 60, color: Colors.white),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _resetTimer,
                  child: const Text("Reset"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => isActive ? _pauseTimer() : _startTimer(),
                  child: Text(isActive ? "Pause" : "Start"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  final TimerPageState state;
  const SettingsPage({Key? key, required this.state}) : super(key: key);
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          ListTile(
            title: const Text("Volume Control"),
            subtitle: Slider(
              value: widget.state.volume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: "${(widget.state.volume * 100).toInt()}%",
              onChanged: (value) {
                setState(() {
                  widget.state.volume = value;
                  widget.state.flutterTts.setVolume(value);
                });
              },
            ),
          ),
          ListTile(
            title: const Text("Speech Interval"),
            trailing: DropdownButton<int>(
              value: widget.state.intervalSeconds,
              items: const [
                DropdownMenuItem(value: 10, child: Text("10 Seconds")),
                DropdownMenuItem(value: 20, child: Text("20 Seconds")),
                DropdownMenuItem(value: 30, child: Text("30 Seconds")),
                DropdownMenuItem(value: 60, child: Text("1 Minute")),
              ],
              onChanged: (newValue) {
                if (newValue != null) {
                  setState(() {
                    widget.state.intervalSeconds = newValue;
                  });
                }
              },
            ),
          ),
          SwitchListTile(
            title: const Text("Voice Recognition"),
            value: widget.state.voiceRecognitionEnabled,
            onChanged: (value) {
              widget.state._updateVoiceRecognitionSetting(value);
              setState(() {}); // Обновляем UI
            },
          ),
        ],
      ),
    );
  }
}
