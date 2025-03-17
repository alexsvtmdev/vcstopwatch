import 'dart:async';
import 'dart:convert';
import 'dart:io'; // для проверки платформы
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart'; // Обратите внимание на правильный импорт

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
  double volume = 1.0;
  int intervalSeconds = 30;
  bool voiceControlEnabled = true;

  // Параметры для VoskFlutter2
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();
  Model? model;
  Recognizer? recognizer;
  SpeechService? speechService;
  String? error;
  bool recognitionStarted = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    flutterTts.setVolume(volume);
    // Таймер обновляется каждые 10 мс; увеличиваем время на 20 мс для ускорения в 2 раза.
    timer = Timer.periodic(const Duration(milliseconds: 10), (Timer t) {
      handleTick();
    });
    initVosk();
  }

  Future<void> initVosk() async {
    const modelName = 'vosk-model-small-en-us-0.15';
    const sampleRate = 16000;
    try {
      // Загружаем список моделей и выбираем нужную
      final modelsList = await _modelLoader.loadModelsList();
      final modelDescription = modelsList.firstWhere(
        (m) => m.name == modelName,
      );
      // Загрузка модели по сети (можно заменить на локальную, если модель положена в assets)
      final modelPath = await _modelLoader.loadFromNetwork(
        modelDescription.url,
      );
      model = await _vosk.createModel(modelPath);
      // Создаем распознающий объект
      recognizer = await _vosk.createRecognizer(
        model: model!,
        sampleRate: sampleRate,
      );

      // Для Android и других платформ с микрофоном инициализируем службу распознавания
      if (Platform.isAndroid) {
        speechService = await _vosk.initSpeechService(recognizer!);
        // Подписываемся на поток результатов.
        speechService!.onResult().listen((result) {
          processVoskResult(result);
        });
        print("Speech service initialized and listening.");
        // Запускаем распознавание сразу, если voiceControlEnabled = true.
        if (voiceControlEnabled) {
          await speechService!.start();
          setState(() {
            recognitionStarted = true;
          });
          print("Voice recognition started automatically.");
        }
      }
    } catch (e) {
      setState(() {
        error = e.toString();
      });
      print("Error initializing Vosk: $error");
    }
  }

  void handleTick() {
    if (isActive) {
      // Увеличиваем время на 20 мс (в два раза быстрее)
      setState(() {
        timeMilliseconds += 20;
      });
      int totalSeconds = timeMilliseconds ~/ 1000;
      int minutes = totalSeconds ~/ 60;
      int seconds = totalSeconds % 60;
      // Произношение времени через заданный интервал
      if (totalSeconds > 0 && totalSeconds % intervalSeconds == 0) {
        String timeAnnouncement;
        if (seconds == 0) {
          timeAnnouncement = "$minutes minute${minutes != 1 ? "s" : ""}";
        } else {
          timeAnnouncement =
              "${minutes > 0 ? "$minutes minute${minutes != 1 ? "s" : ""} and " : ""}$seconds second${seconds != 1 ? "s" : ""}";
        }
        flutterTts.speak(timeAnnouncement);
        print("Announced time: $timeAnnouncement");
      }
    }
  }

  void processVoskResult(String resultJson) {
    print("Raw recognition result: $resultJson");
    final result = jsonDecode(resultJson);
    if (result.containsKey('text')) {
      String recognized = result['text'].toLowerCase();
      print("Recognized text: $recognized");
      if (recognized.contains("start")) {
        if (!isActive) {
          flutterTts.speak("Timer started");
          setState(() {
            isActive = true;
          });
          print("Command recognized: start");
        }
      } else if (recognized.contains("stop")) {
        if (isActive) {
          int totalSeconds = timeMilliseconds ~/ 1000;
          int displayMinutes = totalSeconds ~/ 60;
          int displaySeconds = totalSeconds % 60;
          String announcement =
              "Timer stopped at $displayMinutes minute${displayMinutes != 1 ? "s" : ""} and $displaySeconds second${displaySeconds != 1 ? "s" : ""}";
          flutterTts.speak(announcement);
          setState(() {
            isActive = false;
          });
          print("Command recognized: stop");
        }
      } else if (recognized.contains("reset")) {
        setState(() {
          isActive = false;
          timeMilliseconds = 0;
        });
        flutterTts.speak("Timer reset");
        print("Command recognized: reset");
      }
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
    timer?.cancel();
    speechService?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('VoiceControl Timer')),
        body: Center(
          child: Text(
            "Error: $error",
            style: const TextStyle(color: Colors.red, fontSize: 20),
          ),
        ),
      );
    }

    double displaySeconds = (timeMilliseconds / 1000) % 60;
    int displayMinutes = (timeMilliseconds / (1000 * 60)).floor();
    String formattedTime =
        "${displayMinutes.toString().padLeft(2, '0')}:${displaySeconds.toStringAsFixed(2).padLeft(5, '0')}";

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
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Отображаем время и индикатор работы распознавания
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formattedTime,
                  style: const TextStyle(fontSize: 80, color: Colors.white),
                ),
                const SizedBox(width: 20),
                Icon(
                  recognitionStarted ? Icons.mic : Icons.mic_off,
                  color: recognitionStarted ? Colors.green : Colors.red,
                  size: 40,
                ),
              ],
            ),
            const SizedBox(height: 40),
            // Кнопки управления таймером
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(150, 60),
                    shape: const StadiumBorder(),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      isActive = false;
                      timeMilliseconds = 0;
                    });
                    flutterTts.speak('Timer reset');
                    print("Timer reset manually");
                  },
                  child: const Text('Reset'),
                ),
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
                      });
                      print("Timer started manually");
                    } else {
                      int totalSeconds = timeMilliseconds ~/ 1000;
                      int displayMinutes = totalSeconds ~/ 60;
                      int displaySeconds = totalSeconds % 60;
                      String announcement =
                          "Timer stopped at $displayMinutes minute${displayMinutes != 1 ? "s" : ""} and $displaySeconds second${displaySeconds != 1 ? "s" : ""}";
                      flutterTts.speak(announcement);
                      setState(() {
                        isActive = false;
                      });
                      print("Timer stopped manually");
                    }
                  },
                  child: Text(isActive ? 'Stop' : 'Start'),
                ),
              ],
            ),
          ],
        ),
      ),
      // Убрана кнопка микрофона, так как распознавание работает постоянно, если включено в настройках.
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
                  // Если голосовое управление включено, запустить распознавание,
                  // иначе остановить службу.
                  if (value && !widget.state.recognitionStarted) {
                    widget.state.speechService?.start();
                    widget.state.recognitionStarted = true;
                    print("Voice recognition enabled via settings.");
                  } else if (!value && widget.state.recognitionStarted) {
                    widget.state.speechService?.stop();
                    widget.state.recognitionStarted = false;
                    print("Voice recognition disabled via settings.");
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
