import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:rhino_flutter/rhino_manager.dart';
import 'package:rhino_flutter/rhino_error.dart';
import 'package:rhino_flutter/rhino.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

/// MyApp – корневой виджет приложения.
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

/// TimerPage – главная страница с таймером, голосовым управлением и индикатором состояния голосового распознавания.
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
  // Приватная переменная для хранения экземпляра RhinoManager.
  RhinoManager? _rhinoManager;

  @override
  void initState() {
    super.initState();
    _loadVoiceRecognitionSetting();
    // Таймер обновляет время каждую 10 мс.
    timer = Timer.periodic(const Duration(milliseconds: 10), (Timer t) {
      _handleTick();
    });
    flutterTts.setVolume(volume);
    debugPrint("TTS initialized with volume: $volume");
    if (voiceRecognitionEnabled) {
      _initRhino();
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
      _initRhino();
    } else {
      await _rhinoManager?.delete();
      setState(() {
        _rhinoManager = null;
      });
      debugPrint("RhinoManager deleted, voice recognition disabled");
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
        debugPrint("Announcing time: $announcement");
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
      debugPrint("Starting timer...");
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
      debugPrint("Pausing timer at ${_formattedTime()}");
      flutterTts.speak("Timer paused at ${_formattedTime()}");
      setState(() {
        isActive = false;
      });
    } else {
      flutterTts.speak("Timer is not running");
    }
  }

  void _resetTimer() {
    debugPrint("Resetting timer...");
    flutterTts.speak("Timer reset");
    setState(() {
      isActive = false;
      timeMilliseconds = 0;
    });
  }

  /// Инициализирует RhinoManager в режиме inference-only (без wake word).
  Future<void> _initRhino() async {
    try {
      debugPrint("Initializing RhinoManager (inference-only mode)...");
      // Замените эту строку на ваш реальный access key.
      final String accessKey =
          "P780lAn7uY/24n6Ns7KDEiMu/FguauqQWLSwG99l2P8c0N3Ymtmlig==";
      // Путь к контекстному файлу (добавленному в ассеты).
      final String contextAsset =
          "assets/picovoice/voice_control_timer_en_android_v3_0_0.rhn";
      debugPrint("AccessKey: $accessKey");
      debugPrint("ContextAsset: $contextAsset");
      // Три позиционных аргумента: accessKey, contextAsset, _inferenceCallback.
      _rhinoManager = await RhinoManager.create(
        accessKey,
        contextAsset,
        _inferenceCallback,
      );
      debugPrint("RhinoManager created successfully");
      // Запускаем процесс аудиозахвата и инференса один раз.
      await _rhinoManager!.process();
      debugPrint("RhinoManager process started successfully");
    } on RhinoException catch (err) {
      debugPrint("RhinoException during initialization: ${err.toString()}");
      setState(() {
        _rhinoManager = null;
      });
    }
  }

  /// Callback, вызываемый при получении inference.
  void _inferenceCallback(RhinoInference inference) {
    debugPrint("Inference callback received: $inference");
    if (inference.isUnderstood == true) {
      String intent = inference.intent ?? "unknown";
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
    // Не перезапускаем процесс каждый раз – оставляем его запуск только один раз в _initRhino().
  }

  @override
  void dispose() {
    timer?.cancel();
    _rhinoManager?.delete();
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
            // Иконка состояния голосового распознавания над таймером.
            Icon(
              voiceRecognitionEnabled && _rhinoManager != null
                  ? Icons.mic
                  : Icons.mic_off,
              size: 40,
              color:
                  voiceRecognitionEnabled && _rhinoManager != null
                      ? Colors.green
                      : Colors.red,
            ),
            const SizedBox(height: 10),
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

/// Страница настроек для регулировки громкости, интервала оповещений и включения/выключения голосового распознавания.
/// Значение переключателя сохраняется в SharedPreferences.
class SettingsPage extends StatefulWidget {
  final TimerPageState state;
  const SettingsPage({Key? key, required this.state}) : super(key: key);
  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
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
