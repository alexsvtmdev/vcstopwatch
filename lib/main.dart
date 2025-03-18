import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

/// Класс, представляющий запись круга.
class LapRecord {
  final int lapNumber;
  final Duration lapTime;
  final Duration overallTime;
  LapRecord({
    required this.lapNumber,
    required this.lapTime,
    required this.overallTime,
  });
}

/// Результат распознавания голоса с флагом, является ли он командой.
class VoiceCommandResult {
  final String text;
  final bool isCommand;
  VoiceCommandResult({required this.text, required this.isCommand});
}

/// Сервис голосовых команд.
class VoiceCommandService {
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  final ModelLoader _modelLoader = ModelLoader();
  Model? model;
  Recognizer? recognizer;
  SpeechService? speechService;
  final _controller = StreamController<VoiceCommandResult>.broadcast();

  // Список слов, по которым реагировать.
  static const List<String> commandWords = [
    "start",
    "go",
    "begin",
    "stop",
    "end",
    "pause",
    "reset",
    "clear",
    "restart",
    "renew",
    "resume",
    "lap",
    "split",
  ];

  // Список слов, которые будут распознаны, но не вызовут реакцию.
  static const List<String> ignoreWords = [
    "minute",
    "minutes",
    "seconds",
    "stopwatch", // заменили "timer" на "stopwatch"
    "zero",
    "completed",
    "one",
    "two",
    "three",
    "four",
    "five",
    "six",
    "seven",
    "eight",
    "nine",
    "ten",
    "twenty",
    "thirty",
    "forty",
    "fifty",
    "circle",
  ];

  // grammarList – объединение commandWords и ignoreWords.
  List<String> get grammarList => [...commandWords, ...ignoreWords];

  Stream<VoiceCommandResult> get commandStream => _controller.stream;

  Future<void> initialize() async {
    const modelName = 'vosk-model-small-en-us-0.15';
    const sampleRate = 16000;
    try {
      developer.log("Loading model list...", name: "VoiceCommandService");
      final modelsList = await _modelLoader.loadModelsList();
      final modelDescription = modelsList.firstWhere(
        (m) => m.name == modelName,
      );
      developer.log(
        "Loading model from: ${modelDescription.url}",
        name: "VoiceCommandService",
      );
      final modelPath = await _modelLoader.loadFromNetwork(
        modelDescription.url,
      );
      model = await _vosk.createModel(modelPath);
      developer.log("Model successfully created.", name: "VoiceCommandService");

      recognizer = await _vosk.createRecognizer(
        model: model!,
        sampleRate: sampleRate,
      );
      developer.log(
        "Recognizer successfully created.",
        name: "VoiceCommandService",
      );

      await recognizer!.setGrammar(grammarList);
      developer.log(
        "Grammar set to: $grammarList",
        name: "VoiceCommandService",
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
        if (recognized.isEmpty) recognized = "-";
        bool isCommand = false;
        if (!ignoreWords.contains(recognized)) {
          for (var word in commandWords) {
            if (recognized.contains(word)) {
              isCommand = true;
              break;
            }
          }
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
      title: 'VoiceControl Stopwatch',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF001F3F),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF001F3F)),
      ),
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
  Duration _accumulated = Duration.zero;
  DateTime? _startTime;
  DateTime? _lapStartTime;
  bool isActive = false;
  double volume = 1.0;
  int intervalSeconds = 30;
  bool voiceControlEnabled = true;
  bool voiceRecognitionActive = false;

  String? _displayedVoiceText;
  bool _displayedVoiceIsCommand = false;
  Timer? _clearVoiceTextTimer;

  int _lastIntervalAnnounced = -1;
  final List<LapRecord> _lapRecords = [];

  late VoiceCommandService voiceService;
  StreamSubscription<VoiceCommandResult>? _voiceSub;

  Duration get elapsed {
    if (isActive && _startTime != null) {
      return _accumulated + DateTime.now().difference(_startTime!);
    }
    return _accumulated;
  }

  Duration get currentLapElapsed {
    if (isActive && _lapStartTime != null) {
      return DateTime.now().difference(_lapStartTime!);
    }
    return Duration.zero;
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
    flutterTts.setVolume(volume);

    _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (isActive && _startTime != null) {
        setState(() {});
        Duration currentElapsed = elapsed;
        int totalSeconds = currentElapsed.inSeconds;
        if (intervalSeconds != 0 &&
            totalSeconds > 0 &&
            totalSeconds % intervalSeconds == 0 &&
            totalSeconds != _lastIntervalAnnounced) {
          String announcement = _formatIntervalAnnouncement(currentElapsed);
          flutterTts.speak(announcement);
          _lastIntervalAnnounced = totalSeconds;
          developer.log("Announced interval: $announcement", name: "TimerPage");
        }
      }
    });

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
        setState(() {
          _displayedVoiceText = result.text;
          _displayedVoiceIsCommand = result.isCommand;
        });
        _clearVoiceTextTimer?.cancel();
        _clearVoiceTextTimer = Timer(const Duration(seconds: 3), () {
          setState(() {
            _displayedVoiceText = " ";
          });
        });
        if (result.isCommand) {
          _handleVoiceCommand(result.text);
        }
      });
    });

    _maybeShowHelpDialog();
  }

  Future<void> _maybeShowHelpDialog() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool helpShown = prefs.getBool('helpShown') ?? false;
    if (!helpShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showHelpDialog();
      });
      await prefs.setBool('helpShown', true);
    }
  }

  String _formatIntervalAnnouncement(Duration duration) {
    int totalSeconds = duration.inSeconds;
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    if (minutes > 0 && seconds == 0) {
      return "$minutes minute${minutes != 1 ? "s" : ""}";
    } else if (minutes > 0) {
      return "$minutes minute${minutes != 1 ? "s" : ""} and $seconds second${seconds != 1 ? "s" : ""}";
    } else {
      return "$seconds second${seconds != 1 ? "s" : ""}";
    }
  }

  String _formatTime(Duration duration) {
    int minutes = duration.inMinutes;
    int seconds = duration.inSeconds % 60;
    int centiseconds = ((duration.inMilliseconds % 1000) / 10).floor();
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${centiseconds.toString().padLeft(2, '0')}";
  }

  String _formatAnnouncement(Duration duration) {
    int minutes = duration.inMinutes;
    int seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return "$minutes minute${minutes != 1 ? "s" : ""} and $seconds second${seconds != 1 ? "s" : ""}";
    } else {
      return "$seconds second${seconds != 1 ? "s" : ""}";
    }
  }

  void _handleLap() {
    if (isActive && _lapStartTime != null) {
      Duration currentLap = DateTime.now().difference(_lapStartTime!);
      Duration overall = elapsed;
      int lapNumber = _lapRecords.length + 1;
      flutterTts.speak("circle $lapNumber");
      LapRecord lapRecord = LapRecord(
        lapNumber: lapNumber,
        lapTime: currentLap,
        overallTime: overall,
      );
      _lapRecords.insert(0, lapRecord);
      _lapStartTime = DateTime.now();
      developer.log(
        "Lap recorded: Circle $lapNumber, lap time: $currentLap, overall: $overall",
        name: "TimerPage",
      );
      setState(() {});
    }
  }

  void _handleVoiceCommand(String commandText) {
    developer.log("Voice command received: $commandText", name: "TimerPage");
    if (commandText.contains("start") ||
        commandText.contains("go") ||
        commandText.contains("begin") ||
        commandText.contains("resume")) {
      if (!isActive) {
        flutterTts.speak("Stopwatch started");
        setState(() {
          isActive = true;
          _startTime = DateTime.now();
          _lapStartTime = DateTime.now();
        });
        developer.log(
          "Voice command executed: start/go/begin/resume",
          name: "TimerPage",
        );
      }
    } else if (commandText.contains("stop") ||
        commandText.contains("end") ||
        commandText.contains("pause")) {
      if (isActive && _startTime != null) {
        Duration currentRun = DateTime.now().difference(_startTime!);
        Duration total = _accumulated + currentRun;
        final formatted = _formatAnnouncement(total);
        flutterTts.speak("completed $formatted");
        setState(() {
          isActive = false;
          _accumulated = total;
          _startTime = null;
        });
        developer.log(
          "Voice command executed: stop/go/pause",
          name: "TimerPage",
        );
      }
    } else if (commandText.contains("lap") || commandText.contains("split")) {
      if (isActive && _lapStartTime != null) {
        _handleLap();
      }
    } else if (commandText.contains("reset") ||
        commandText.contains("clear") ||
        commandText.contains("restart") ||
        commandText.contains("renew")) {
      flutterTts.speak("Stopwatch in zero");
      setState(() {
        isActive = false;
        _accumulated = Duration.zero;
        _startTime = null;
        _lapStartTime = null;
        _lapRecords.clear();
      });
      developer.log(
        "Voice command executed: reset/clear/restart/renew",
        name: "TimerPage",
      );
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

  // В ландшафтном режиме с записями фиксированно располагаем кнопки в нижней области.
  Widget _buildFixedButtons() {
    return Container(
      height: 80, // фиксированная высота для кнопок
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLapOrResetButton(),
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
                flutterTts.speak('Stopwatch started');
                setState(() {
                  isActive = true;
                  _startTime = DateTime.now();
                  _lapStartTime = DateTime.now();
                });
                developer.log("Manual: Stopwatch started", name: "TimerPage");
              } else if (isActive && _startTime != null) {
                Duration currentRun = DateTime.now().difference(_startTime!);
                Duration total = _accumulated + currentRun;
                final formatted = _formatAnnouncement(total);
                flutterTts.speak("completed $formatted");
                setState(() {
                  isActive = false;
                  _accumulated = total;
                  _startTime = null;
                });
                developer.log("Manual: Stopwatch stopped", name: "TimerPage");
              }
            },
            child: Text(
              isActive
                  ? 'Stop'
                  : (elapsed > Duration.zero ? 'Resume' : 'Start'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLapTable() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white, width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Expanded(
                  child: Text(
                    "Lap",
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    "Lap times",
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    "Overall time",
                    style: TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: List.generate(_lapRecords.length, (index) {
                  final lap = _lapRecords[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            lap.lapNumber.toString(),
                            style: const TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _formatTime(lap.lapTime),
                            style: const TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _formatTime(lap.overallTime),
                            style: const TextStyle(fontSize: 18),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLapOrResetButton() {
    if (isActive) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(150, 60),
          shape: const StadiumBorder(),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
        onPressed: _handleLap,
        child: const Text('Lap'),
      );
    } else {
      if (elapsed > Duration.zero) {
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(150, 60),
            shape: const StadiumBorder(),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: _handleReset,
          child: const Text('Reset'),
        );
      } else {
        return ElevatedButton(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(150, 60),
            shape: const StadiumBorder(),
            backgroundColor: Colors.grey,
            foregroundColor: Colors.white,
          ),
          onPressed: null,
          child: const Text('Lap'),
        );
      }
    }
  }

  void _handleReset() {
    flutterTts.speak("Stopwatch in zero");
    setState(() {
      isActive = false;
      _accumulated = Duration.zero;
      _startTime = null;
      _lapStartTime = null;
      _lapRecords.clear();
    });
    developer.log("Manual: Stopwatch reset", name: "TimerPage");
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
    final orientation = MediaQuery.of(context).orientation;
    Widget bodyContent;

    if (orientation == Orientation.portrait || _lapRecords.isEmpty) {
      // Одноколоночный макет (как в портретном режиме или если нет записей)
      Widget upperGroup;
      if (_lapRecords.isEmpty) {
        upperGroup = Container(
          height: MediaQuery.of(context).size.height * 0.33,
          alignment: Alignment.bottomCenter,
          child: Text(
            _formatTime(elapsed),
            style: const TextStyle(fontSize: 80, color: Colors.white),
          ),
        );
        upperGroup = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            upperGroup,
            const SizedBox(height: 0),
            Icon(
              voiceRecognitionActive ? Icons.mic : Icons.mic_off,
              color: voiceRecognitionActive ? Colors.green : Colors.red,
              size: 40,
            ),
            const SizedBox(height: 8), // уменьшили с 10 до 8 пикселей
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
          ],
        );
      } else {
        upperGroup = Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              _formatTime(elapsed),
              style: const TextStyle(fontSize: 80, color: Colors.white),
            ),
            if (isActive && _lapStartTime != null)
              Text(
                _formatTime(DateTime.now().difference(_lapStartTime!)),
                style: const TextStyle(fontSize: 40, color: Colors.white70),
              ),
            const SizedBox(height: 0),
            Icon(
              voiceRecognitionActive ? Icons.mic : Icons.mic_off,
              color: voiceRecognitionActive ? Colors.green : Colors.red,
              size: 40,
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),
            _buildLapTable(),
          ],
        );
      }
      bodyContent = Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: upperGroup),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLapOrResetButton(),
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
                    flutterTts.speak('Stopwatch started');
                    setState(() {
                      isActive = true;
                      _startTime = DateTime.now();
                      _lapStartTime = DateTime.now();
                    });
                    developer.log(
                      "Manual: Stopwatch started",
                      name: "TimerPage",
                    );
                  } else if (isActive && _startTime != null) {
                    Duration currentRun = DateTime.now().difference(
                      _startTime!,
                    );
                    Duration total = _accumulated + currentRun;
                    final formatted = _formatAnnouncement(total);
                    flutterTts.speak("completed $formatted");
                    setState(() {
                      isActive = false;
                      _accumulated = total;
                      _startTime = null;
                    });
                    developer.log(
                      "Manual: Stopwatch stopped",
                      name: "TimerPage",
                    );
                  }
                },
                child: Text(
                  isActive
                      ? 'Stop'
                      : (elapsed > Duration.zero ? 'Resume' : 'Start'),
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      // Ландшафтный режим с записями: делим экран на две колонки.
      // Левая колонка: все элементы кроме таблицы, с уменьшенными размерами.
      Widget leftColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Подтягиваем часы к верхнему краю, уменьшаем размер шрифта.
          Text(
            _formatTime(elapsed),
            style: const TextStyle(fontSize: 60, color: Colors.white),
          ),
          if (isActive && _lapStartTime != null)
            Text(
              _formatTime(DateTime.now().difference(_lapStartTime!)),
              style: const TextStyle(
                fontSize: 30,
                color: Colors.white70,
                height: 0.8,
              ),
            ),
          const SizedBox(height: 0),
          Icon(
            voiceRecognitionActive ? Icons.mic : Icons.mic_off,
            color: voiceRecognitionActive ? Colors.green : Colors.red,
            size: 30,
          ),
          // Если нужно уменьшить отступ между иконкой и следующим элементом, можно изменить SizedBox:
          const SizedBox(height: 8), // вместо 10 пикселей
          SizedBox(
            height: 20,
            child: Center(
              child: Text(
                _displayedVoiceText ?? " ",
                style: TextStyle(
                  fontSize: 14,
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
          // Заполняем оставшееся пространство, чтобы кнопки были фиксированы внизу.
          const Spacer(),
          _buildFixedButtons(),
        ],
      );
      // Правая колонка – таблица кругов.
      Widget rightColumn = _buildLapTable();
      bodyContent = Row(
        children: [
          Expanded(child: leftColumn),
          const SizedBox(width: 20),
          Expanded(child: rightColumn),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('VoiceControl Stopwatch'),
        backgroundColor: const Color(0xFF001F3F),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
          ),
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
      backgroundColor: const Color(0xFF001F3F),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: bodyContent,
      ),
    );
  }

  // Единственная реализация _showHelpDialog.
  void _showHelpDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            "Help",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Available Voice Commands:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "- Start / Go / Begin / Resume: Start or resume the stopwatch.",
                  ),
                  Text(
                    "- Stop / End / Pause: Stop the stopwatch and announce the elapsed time.",
                  ),
                  Text(
                    "- Lap / Split: Record the current lap time and overall time.",
                  ),
                  Text(
                    "- Reset / Clear / Restart / Renew: Reset the stopwatch to zero.",
                  ),
                  SizedBox(height: 16),
                  Text(
                    "About the App:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "This is a VoiceControl Stopwatch app. You can control the stopwatch with voice commands.",
                  ),
                  SizedBox(height: 16),
                  Text(
                    "Requirements:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text("Android version 11 or higher is required."),
                  SizedBox(height: 16),
                  Text(
                    "Licenses:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text("Components are used under the Apache 2.0 License."),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
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
    final intervalOptions = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: 0, child: Text("Disable")),
      const DropdownMenuItem(value: 10, child: Text("10 Seconds")),
      const DropdownMenuItem(value: 20, child: Text("20 Seconds")),
      const DropdownMenuItem(value: 30, child: Text("30 Seconds")),
      const DropdownMenuItem(value: 60, child: Text("1 Minute")),
      const DropdownMenuItem(value: 300, child: Text("5 Minutes")),
      const DropdownMenuItem(value: 600, child: Text("10 Minutes")),
    ];
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 20),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: AppBar(
              title: const Text("Settings"),
              backgroundColor: const Color(0xFF001F3F),
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
      backgroundColor: const Color(0xFF001F3F),
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
