import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:picovoice_flutter/picovoice.dart'; // Используем класс Picovoice, как в документации
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

/// Основное приложение.
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

/// Главная страница с таймером, голосовым управлением и отображением состояния распознавания.
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
  // Приватная переменная для экземпляра Picovoice.
  Picovoice? _picovoice;

  @override
  void initState() {
    super.initState();
    _loadVoiceRecognitionSetting();
    // Запускаем таймер, который обновляет время каждые 10 мс.
    timer = Timer.periodic(const Duration(milliseconds: 10), (Timer t) {
      handleTick();
    });
    flutterTts.setVolume(volume);
    // Если распознавание включено, инициализируем его.
    if (voiceRecognitionEnabled) {
      _initPicovoice();
    }
  }

  Future<void> _loadVoiceRecognitionSetting() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? enabled = prefs.getBool("voiceRecognitionEnabled");
    debugPrint("Loaded voiceRecognitionEnabled: $enabled");
    if (enabled != null) {
      setState(() {
        voiceRecognitionEnabled = enabled;
      });
    }
  }

  Future<void> _updateVoiceRecognitionSetting(bool enabled) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool("voiceRecognitionEnabled", enabled);
    setState(() {
      voiceRecognitionEnabled = enabled;
    });
    debugPrint("Voice recognition setting updated: $enabled");
    if (enabled) {
      _initPicovoice();
    } else {
      // Если выключаем распознавание, освобождаем ресурсы.
      await _picovoice?.delete();
      setState(() {
        _picovoice = null;
      });
      debugPrint("Picovoice deleted, voice recognition disabled");
    }
  }

  void handleTick() {
    if (isActive) {
      setState(() {
        timeMilliseconds += 10;
      });
      int totalSeconds = timeMilliseconds ~/ 1000;
      int minutes = totalSeconds ~/ 60;
      int seconds = totalSeconds % 60;
      // Каждые intervalSeconds секунд произносится время.
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
    int minutes = (timeMilliseconds / 60000).floor();
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

  /// Инициализирует Picovoice в режиме inference-only (без wake word).
  Future<void> _initPicovoice() async {
    try {
      debugPrint("Initializing Picovoice (inference-only mode)...");
      // Замените на ваш реальный access key.
      final String accessKey =
          "P780lAn7uY/24n6Ns7KDEiMu/FguauqQWLSwG99l2P8c0N3Ymtmlig==";
      // Пути к ассетам, как они указаны в pubspec.yaml.
      final String keywordAsset =
          ""; // В режиме inference-only не используется.
      final String contextAsset =
          "assets/picovoice/voice_control_timer_en_android_v3_0_0.rhn";
      debugPrint("AccessKey: $accessKey");
      debugPrint("ContextAsset: $contextAsset");
      _picovoice = await Picovoice.create(
        accessKey,
        keywordAsset,
        () {}, // Пустой callback для wake word.
        contextAsset,
        _inferenceCallback,
      );
      debugPrint("Picovoice (inference-only) created successfully");
    } catch (e) {
      debugPrint("Failed to initialize Picovoice: ${e.toString()}");
      setState(() {
        _picovoice = null;
      });
    }
  }

  /// Callback, вызываемый при получении inference.
  void _inferenceCallback(dynamic inference) {
    debugPrint("Inference callback: $inference");
    if (inference != null && inference['isUnderstood'] == true) {
      String intent = inference['intent'] ?? "unknown";
      debugPrint("Recognized intent: $intent");
      flutterTts.speak("Command: $intent");
      switch (intent.toLowerCase()) {
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
          debugPrint("Unknown command: $intent");
      }
    } else {
      debugPrint("Command not understood");
    }
  }

  @override
  void dispose() {
    // Освобождаем ресурсы Picovoice.
    _picovoice?.delete();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String formattedTime = _formattedTime();
    return Scaffold(
      appBar: AppBar(
        title: const Text("VoiceControl Timer"),
        actions: [
          // Пиктограмма, показывающая состояние голосового распознавания.
          Icon(
            voiceRecognitionEnabled && _picovoice != null
                ? Icons.mic
                : Icons.mic_off,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsPage(state: this),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              formattedTime,
              style: const TextStyle(fontSize: 60, color: Colors.white),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      isActive = false;
                      timeMilliseconds = 0;
                    });
                    flutterTts.speak("Timer reset");
                  },
                  child: const Text("Reset"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (!isActive) {
                      flutterTts.speak("Timer started");
                    } else {
                      flutterTts.speak("Timer paused at $formattedTime");
                    }
                    setState(() {
                      isActive = !isActive;
                    });
                  },
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

/// Страница настроек, где можно регулировать громкость, интервал оповещений и включать/выключать голосовое распознавание.
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
              onChanged: (double value) {
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
              onChanged: (int? newValue) {
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
            onChanged: (bool value) {
              widget.state._updateVoiceRecognitionSetting(value);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
