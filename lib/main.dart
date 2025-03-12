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
  bool isInitializingRhino = false;

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
    // Отложенная инициализация Rhino через 1 секунду.
    Future.delayed(const Duration(seconds: 1), () {
      if (voiceRecognitionEnabled) {
        _initRhino();
      } else {
        debugPrint("Voice recognition отключено по настройкам");
      }
      _debugCheckFiles();
    });
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

  /// Копирует файл ассета во временную директорию и возвращает абсолютный путь.
  Future<String> _loadAssetToFile(String assetPath, String fileName) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    debugPrint("Файл '$fileName' сохранён: ${file.path}");
    return file.path;
  }

  /// Отладочная функция: проверяет наличие файлов и их размеры.
  Future<void> _debugCheckFiles() async {
    try {
      String contextPath = await _loadAssetToFile(
        "assets/picovoice/voice_control_timer_en_android_v3_0_0.rhn",
        "voice_control_timer_en_android_v3_0_0.rhn",
      );
      String keywordPath = await _loadAssetToFile(
        "assets/picovoice/Ok-Timer_en_android_v3_0_0.ppn",
        "Ok-Timer_en_android_v3_0_0.ppn",
      );
      String porcupinePath = await _loadAssetToFile(
        "assets/picovoice/porcupine_params.pv",
        "porcupine_params.pv",
      );

      File contextFile = File(contextPath);
      bool contextExists = await contextFile.exists();
      int contextSize = contextExists ? await contextFile.length() : 0;
      debugPrint(
        "Контекстный файл: существует=$contextExists, размер=$contextSize байт",
      );

      File keywordFile = File(keywordPath);
      bool keywordExists = await keywordFile.exists();
      int keywordSize = keywordExists ? await keywordFile.length() : 0;
      debugPrint(
        "Файл ключевого слова: существует=$keywordExists, размер=$keywordSize байт",
      );

      File porcupineFile = File(porcupinePath);
      bool porcupineExists = await porcupineFile.exists();
      int porcupineSize = porcupineExists ? await porcupineFile.length() : 0;
      debugPrint(
        "Файл porcupine_params.pv: существует=$porcupineExists, размер=$porcupineSize байт",
      );
    } catch (e) {
      debugPrint("Ошибка проверки файлов: $e");
    }
  }

  /// Копирует модель porcupine из ассетов в директорию файлов приложения.
  Future<String> _copyPorcupineModel() async {
    final byteData = await rootBundle.load(
      "assets/picovoice/porcupine_params.pv",
    );
    final appDir = await getApplicationDocumentsDirectory();
    final file = File('${appDir.path}/porcupine_params.pv');
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    debugPrint("Файл porcupine_params.pv скопирован: ${file.path}");
    return file.path;
  }

  Future<void> _initRhino() async {
    if (isInitializingRhino) return;
    setState(() {
      isInitializingRhino = true;
    });
    try {
      debugPrint("Initializing Rhino с wake word...");
      // Замените на ваш действительный access key.
      String accessKey =
          "P780lAn7uY/24n6Ns7KDEiMu/FguauqWLSwG99l2P8c0N3Ymtmlig==";
      String assetContextPath =
          "assets/picovoice/voice_control_timer_en_android_v3_0_0.rhn";
      String assetKeywordPath =
          "assets/picovoice/Ok-Timer_en_android_v3_0_0.ppn";

      String contextPath = await _loadAssetToFile(
        assetContextPath,
        "voice_control_timer_en_android_v3_0_0.rhn",
      );
      String keywordPath = await _loadAssetToFile(
        assetKeywordPath,
        "Ok-Timer_en_android_v3_0_0.ppn",
      );
      await _copyPorcupineModel(); // Копируем модель porcupine_params.pv в файловую систему

      debugPrint("AccessKey: $accessKey");
      debugPrint("ContextPath (temp): $contextPath");
      debugPrint("KeywordPath (temp): $keywordPath");

      _picovoiceManager = await PicovoiceManager.create(
        accessKey,
        keywordPath, // Файл ключевого слова
        _wakeWordCallback, // Callback для wake word
        contextPath, // Файл контекста
        _inferenceCallback, // Callback для inference
      );
      await _picovoiceManager!.start();
      debugPrint("Rhino with wake word started successfully");
      setState(() {});
    } catch (e) {
      debugPrint("Failed to initialize Rhino: ${e.toString()}");
      setState(() {
        _picovoiceManager = null;
      });
    } finally {
      setState(() {
        isInitializingRhino = false;
      });
    }
  }

  void _wakeWordCallback() {
    debugPrint("Wake word detected!");
    flutterTts.speak("Wake word detected");
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
            ElevatedButton(
              onPressed: _initRhino,
              child:
                  isInitializingRhino
                      ? const CircularProgressIndicator()
                      : const Text("Init Rhino"),
            ),
            const SizedBox(height: 20),
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
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
