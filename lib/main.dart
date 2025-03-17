import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

/// Результат распознавания голоса с флагом, является ли он командой
class VoiceCommandResult {
  final String text;
  final bool isCommand;
  VoiceCommandResult({required this.text, required this.isCommand});
}

/// Сервис голосовых команд: инициализация модели, распознавание и передача результатов через поток.
class VoiceCommandService {
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  final ModelLoader _modelLoader = ModelLoader();
  Model? model;
  Recognizer? recognizer;
  SpeechService? speechService;
  final _controller = StreamController<VoiceCommandResult>.broadcast();

  Stream<VoiceCommandResult> get commandStream => _controller.stream;

  Future<void> initialize() async {
    const modelName = 'vosk-model-small-en-us-0.15';
    const sampleRate = 16000;
    try {
      final modelsList = await _modelLoader.loadModelsList();
      final modelDescription = modelsList.firstWhere(
        (m) => m.name == modelName,
      );
      // Можно заменить загрузку по сети на локальную модель (если положена в assets)
      final modelPath = await _modelLoader.loadFromNetwork(
        modelDescription.url,
      );
      model = await _vosk.createModel(modelPath);
      recognizer = await _vosk.createRecognizer(
        model: model!,
        sampleRate: sampleRate,
      );
      if (Platform.isAndroid) {
        speechService = await _vosk.initSpeechService(recognizer!);
        speechService!.onResult().listen((result) {
          processResult(result);
        });
      }
      developer.log(
        "VoiceCommandService initialized.",
        name: "VoiceCommandService",
      );
    } catch (e) {
      developer.log(
        "Error in VoiceCommandService.initialize: $e",
        name: "VoiceCommandService",
      );
    }
  }

  void processResult(String resultJson) {
    developer.log("Raw voice result: $resultJson", name: "VoiceCommandService");
    try {
      final result = jsonDecode(resultJson);
      if (result.containsKey('text')) {
        String recognized = result['text'].toLowerCase().trim();
        // Если пустой результат, заменяем на тире
        if (recognized.isEmpty) {
          recognized = "-";
        }
        bool isCommand = false;
        if (recognized.contains("start") ||
            recognized.contains("stop") ||
            recognized.contains("reset") ||
            recognized.contains("clear") ||
            recognized.contains("restart") ||
            recognized.contains("renew")) {
          isCommand = true;
        }
        _controller.add(
          VoiceCommandResult(text: recognized, isCommand: isCommand),
        );
        developer.log(
          "Processed voice result: $recognized, isCommand: $isCommand",
          name: "VoiceCommandService",
        );
      }
    } catch (e) {
      developer.log(
        "Error processing voice result: $e",
        name: "VoiceCommandService",
      );
    }
  }

  Future<void> startListening() async {
    if (speechService != null) {
      await speechService!.start();
      developer.log("Voice recognition started.", name: "VoiceCommandService");
    }
  }

  Future<void> stopListening() async {
    if (speechService != null) {
      await speechService!.stop();
      developer.log("Voice recognition stopped.", name: "VoiceCommandService");
    }
  }

  void dispose() {
    _controller.close();
  }
}

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
  Timer? _uiTimer;
  // Используем _elapsed для накопленного времени (время до последнего запуска)
  Duration _elapsed = Duration.zero;
  // _startTime хранит момент последнего запуска (для вычисления продолжения)
  DateTime? _startTime;
  bool isActive = false;
  double volume = 1.0;
  // Интервал произношения в секундах; значение 0 означает отключить интервал.
  int intervalSeconds = 30;
  bool voiceControlEnabled = true;
  // Индикатор работы голосового распознавания
  bool voiceRecognitionActive = false;

  // Для отображения распознанного текста под иконкой (фиксированная высота)
  String? _displayedVoiceText;
  bool _displayedVoiceIsCommand = false;
  Timer? _clearVoiceTextTimer;

  late VoiceCommandService voiceService;
  StreamSubscription<VoiceCommandResult>? _voiceSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    flutterTts.setVolume(volume);
    // UI таймер: обновляем экран каждые 50 мс, используя системное время.
    _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (isActive && _startTime != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_startTime!) + _elapsed;
          // Здесь можно скорректировать, если нужно аккумулировать время при паузах.
          // Но мы обновляем _startTime при запуске, чтобы продолжить с накопленного _elapsed.
        });
      }
    });
    // Инициализируем сервис голосовых команд.
    voiceService = VoiceCommandService();
    voiceService.initialize().then((_) {
      if (voiceControlEnabled) {
        voiceService.startListening().then((_) {
          setState(() {
            voiceRecognitionActive = true;
          });
          developer.log(
            "Voice recognition started automatically.",
            name: "TimerPage",
          );
        });
      }
      _voiceSub = voiceService.commandStream.listen((result) {
        // Обновляем UI для отображения распознанного текста.
        setState(() {
          _displayedVoiceText = result.text;
          _displayedVoiceIsCommand = result.isCommand;
        });
        _clearVoiceTextTimer?.cancel();
        _clearVoiceTextTimer = Timer(const Duration(seconds: 3), () {
          setState(() {
            _displayedVoiceText = " "; // пробел вместо пустой строки
          });
        });
        // Если результат является командой – выполняем её.
        if (result.isCommand) {
          _handleVoiceCommand(result.text);
        }
      });
    });
  }

  // Форматирование для голосового объявления при остановке.
  String _formatAnnouncement(Duration duration) {
    int minutes = duration.inMinutes;
    int seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return "$minutes minute${minutes != 1 ? "s" : ""} and $seconds second${seconds != 1 ? "s" : ""}";
    } else {
      return "$seconds second${seconds != 1 ? "s" : ""}";
    }
  }

  // Форматирование для отображения времени с сотыми долями: MM:SS:CS
  String _formatTime(Duration duration) {
    int minutes = duration.inMinutes;
    int seconds = duration.inSeconds % 60;
    int centiseconds = ((duration.inMilliseconds % 1000) / 10).floor();
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${centiseconds.toString().padLeft(2, '0')}";
  }

  void _handleVoiceCommand(String commandText) {
    developer.log("Voice command received: $commandText", name: "TimerPage");
    if (commandText.contains("start")) {
      if (!isActive) {
        flutterTts.speak("Timer started");
        setState(() {
          isActive = true;
          // При возобновлении таймера, _startTime = текущее время минус уже накопленное время.
          _startTime = DateTime.now().subtract(_elapsed);
        });
        developer.log("Voice command executed: start", name: "TimerPage");
      }
    } else if (commandText.contains("stop")) {
      if (isActive) {
        // При остановке – останавливаем таймер, не сбрасывая _elapsed.
        flutterTts.speak(_formatAnnouncement(_elapsed));
        setState(() {
          isActive = false;
        });
        developer.log("Voice command executed: stop", name: "TimerPage");
      }
    } else if (commandText.contains("reset") ||
        commandText.contains("clear") ||
        commandText.contains("restart") ||
        commandText.contains("renew")) {
      flutterTts.speak("Timer reset");
      setState(() {
        isActive = false;
        _elapsed = Duration.zero;
        _startTime = null;
      });
      developer.log("Voice command executed: reset", name: "TimerPage");
    }
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      volume = prefs.getDouble('volume') ?? 1.0;
      intervalSeconds = prefs.getInt('intervalSeconds') ?? 30;
      voiceControlEnabled = prefs.getBool('voiceControlEnabled') ?? true;
    });
    flutterTts.setVolume(volume);
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('volume', volume);
    await prefs.setInt('intervalSeconds', intervalSeconds);
    await prefs.setBool('voiceControlEnabled', voiceControlEnabled);
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _voiceSub?.cancel();
    _clearVoiceTextTimer?.cancel();
    voiceService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String formattedTime = _formatTime(_elapsed);
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoiceControl Timer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (context) => SettingsPage(state: this),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              formattedTime,
              style: const TextStyle(fontSize: 80, color: Colors.white),
            ),
            const SizedBox(height: 20),
            // Индикатор голосового распознавания
            Icon(
              voiceRecognitionActive ? Icons.mic : Icons.mic_off,
              color: voiceRecognitionActive ? Colors.green : Colors.red,
              size: 40,
            ),
            const SizedBox(height: 10),
            // Фиксированное место для отображения распознанного текста
            SizedBox(
              height: 20,
              child: Center(
                child: Text(
                  _displayedVoiceText ?? " ",
                  style: TextStyle(
                    fontSize: 16,
                    color:
                        _displayedVoiceIsCommand ? Colors.green : Colors.orange,
                    fontWeight:
                        _displayedVoiceIsCommand
                            ? FontWeight.bold
                            : FontWeight.normal,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
            // Ручное управление таймером
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(150, 60),
                    shape: const StadiumBorder(),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    flutterTts.speak('Timer reset');
                    setState(() {
                      isActive = false;
                      _elapsed = Duration.zero;
                      _startTime = null;
                    });
                    developer.log("Manual: Timer reset", name: "TimerPage");
                  },
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(150, 60),
                    shape: const StadiumBorder(),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (!isActive) {
                      flutterTts.speak('Timer started');
                      setState(() {
                        isActive = true;
                        // Если _elapsed уже накоплено, продолжаем отсчёт
                        _startTime = DateTime.now().subtract(_elapsed);
                      });
                      developer.log("Manual: Timer started", name: "TimerPage");
                    } else {
                      flutterTts.speak(_formatAnnouncement(_elapsed));
                      setState(() {
                        isActive = false;
                      });
                      developer.log("Manual: Timer stopped", name: "TimerPage");
                    }
                  },
                  child: Text(isActive ? 'Stop' : 'Start'),
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
  const SettingsPage({super.key, required this.state});
  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    // Дополнительная опция "Disable" для Speech Interval (значение 0 означает отключение)
    final intervalOptions = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: 0, child: Text("Disable")),
      const DropdownMenuItem(value: 10, child: Text("10 Seconds")),
      const DropdownMenuItem(value: 20, child: Text("20 Seconds")),
      const DropdownMenuItem(value: 30, child: Text("30 Seconds")),
      const DropdownMenuItem(value: 60, child: Text("1 Minute")),
    ];
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 20),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: AppBar(
              title: const Text("Settings"),
              leading: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
              toolbarHeight: kToolbarHeight + 20,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              title: const Text('Volume Control'),
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
                    widget.state._saveSettings();
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Speech Interval'),
              trailing: DropdownButton<int>(
                value: widget.state.intervalSeconds,
                items: intervalOptions,
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    setState(() {
                      widget.state.intervalSeconds = newValue;
                      widget.state._saveSettings();
                    });
                  }
                },
              ),
            ),
            SwitchListTile(
              title: const Text('Voice Control'),
              value: widget.state.voiceControlEnabled,
              onChanged: (bool value) {
                setState(() {
                  widget.state.voiceControlEnabled = value;
                  widget.state._saveSettings();
                  widget.state.voiceRecognitionActive = value;
                  if (value) {
                    widget.state.voiceService.startListening().then((_) {
                      developer.log(
                        "Voice recognition enabled via settings.",
                        name: "SettingsPage",
                      );
                    });
                  } else {
                    widget.state.voiceService.stopListening().then((_) {
                      developer.log(
                        "Voice recognition disabled via settings.",
                        name: "SettingsPage",
                      );
                    });
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
