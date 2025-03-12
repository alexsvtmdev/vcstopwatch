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

/// TimerPage – главная страница с таймером, голосовым управлением и индикатором распознавания.
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
    timer = Timer.periodic(const Duration(milliseconds: 10), (Timer t) {
      _handleTick();
    });
    flutterTts.setVolume(volume);
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

  /// Инициализирует RhinoManager в режиме inference-only (без wake word).
  Future<void> _initRhino() async {
    try {
      debugPrint("Initializing RhinoManager (inference-only mode)...");
      // Замените эту строку на ваш реальный access key.
      final String accessKey =
          "P780lAn7uY/24n6Ns7KDEiMu/FguauqQWLSwG99l2P8c0N3Ymtmlig==";
      // Путь к контекстному файлу из ассетов.
      final String contextAsset =
          "assets/picovoice/voice_control_timer_en_android_v3_0_0.rhn";
      debugPrint("AccessKey: $accessKey");
      debugPrint("ContextAsset: $contextAsset");
      // Передаём три позиционных аргумента: accessKey, contextAsset и _inferenceCallback.
      _rhinoManager = await RhinoManager.create(
        accessKey,
        contextAsset,
        _inferenceCallback,
      );
      // Запускаем аудиозахват и инференс.
      await _rhinoManager!.process();
      debugPrint("RhinoManager processing started successfully");
    } on RhinoException catch (err) {
      debugPrint("RhinoException: ${err.toString()}");
      setState(() {
        _rhinoManager = null;
      });
    }
  }

  /// Callback, вызываемый при получении inference.
  void _inferenceCallback(RhinoInference inference) {
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
      _restartRhino();
    } else {
      debugPrint("Command not understood");
      _restartRhino();
    }
  }

  /// Перезапускает процесс аудиозахвата для непрерывного прослушивания.
  Future<void> _restartRhino() async {
    try {
      await _rhinoManager?.process();
      debugPrint("RhinoManager process restarted successfully");
    } on RhinoException catch (err) {
      debugPrint("Failed to restart RhinoManager process: ${err.toString()}");
    }
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
          // Отображает состояние голосового распознавания: зелёный, если _rhinoManager != null, иначе красный.
          Icon(
            voiceRecognitionEnabled && _rhinoManager != null
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

/// Страница настроек для регулировки громкости, интервала оповещений и включения/выключения голосового распознавания.
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
