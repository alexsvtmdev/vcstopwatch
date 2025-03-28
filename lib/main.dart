import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:path_provider/path_provider.dart';

// Глобальный флаг для включения/отключения логирования.
// Для продакшена можно установить false, для отладки — true.
const bool kLoggingEnabled = true;

const Map<String, String> languageNames = {
  "en-us": "English",
  "ru": "Russian",
  "fr": "French",
  "de": "German",
  "es": "Spanish",
  "cn": "Chinese",
  "it": "Italian",
  "pt": "Portuguese",
  "nl": "Dutch",
  "uk": "Ukrainian",
  "ja": "Japanese",
  "ko": "Korean",
  "ar": "Arabic",
  "hi": "Hindi",
  "fa": "Farsi",
  "pl": "Polish",
  "cs": "Czech",
  "tr": "Turkish",
  "el-gr": "Greek",
  "tl-ph": "Filipino",
  "ca": "Catalan",
};

/// Функция для извлечения имени языка из пути модели.
String extractLanguageNameFromModelPath(String path) {
  final regex = RegExp(r'(vosk-model(?:-small)?-)([a-z\-]+)(?:-[^/\\]*)?$');
  final match = regex.firstMatch(path.toLowerCase());
  if (match != null && match.groupCount >= 2) {
    final langCode = match.group(2)!;
    return languageNames[langCode] ?? langCode;
  }
  return "unknown";
}

void appLog(
  String message, {
  String name = 'AppLog',
  int level = 0,
  DateTime? time,
  Object? error,
  StackTrace? stackTrace,
}) {
  if (kLoggingEnabled) {
    if (kReleaseMode) {
      // В режиме релиза используем print для вывода логов
      print('[$name] $message');
    } else {
      developer.log(
        message,
        name: name,
        level: level,
        time: time,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

Future<bool> requestMicrophonePermission() async {
  final status = await Permission.microphone.status;
  if (status.isGranted) {
    appLog('🎙️ Microphone permission already granted.');
    return true;
  }
  final result = await Permission.microphone.request();
  if (result == PermissionStatus.granted) {
    appLog('✅ Microphone permission granted.');
    return true;
  } else {
    appLog('❌ Microphone permission not granted: $result');
    return false;
  }
}

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

  // Обновлённый метод initialize с новым параметром.
  Future<void> initialize({
    ValueNotifier<String>? loadingStatus,
    bool initSpeechService = true,
  }) async {
    const modelName = 'vosk-model-small-en-us-0.15';
    const sampleRate = 16000;

    try {
      loadingStatus?.value = "Initializing voice service...";
      final modelsList = await _modelLoader.loadModelsList();
      final modelDescription = modelsList.firstWhere(
        (m) => m.name == modelName,
      );

      // Проверка и загрузка модели...
      final dir = await getApplicationSupportDirectory();
      final modelFolder = Directory('${dir.path}/$modelName');
      final bool modelExists = await modelFolder.exists();
      final languageCode = extractLanguageNameFromModelPath(modelName);
      if (!modelExists) {
        loadingStatus?.value = "Downloading language: $languageCode";
        await Future.delayed(Duration(milliseconds: 10));
      }
      final modelPath = await _modelLoader.loadFromNetwork(
        modelDescription.url,
      );
      loadingStatus?.value = "Initializing voice service...";
      model = await _vosk.createModel(modelPath);
    } catch (e) {
      // Обработка ошибок загрузки модели.
      rethrow;
    }

    try {
      recognizer = await _vosk.createRecognizer(
        model: model!,
        sampleRate: sampleRate,
      );
      await recognizer!.setGrammar(grammarList);
    } catch (e) {
      rethrow;
    }

    // Если параметр initSpeechService истинен, запускаем инициализацию микрофонного сервиса.
    if (initSpeechService) {
      await initializeSpeechService();
    }

    appLog(
      "VoiceCommandService fully initialized.",
      name: "VoiceCommandService",
    );
  }

  Future<void> initializeSpeechService() async {
    try {
      if (Platform.isAndroid) {
        speechService = await _vosk.initSpeechService(recognizer!);
        speechService!.onResult().listen((result) {
          processResult(result);
        });
        appLog("Speech service initialized.", name: "VoiceCommandService");
      }
    } catch (e, stackTrace) {
      appLog(
        "Error initializing speech service: $e",
        name: "VoiceCommandService",
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void processResult(String resultJson) {
    appLog("Raw voice result: $resultJson", name: "VoiceCommandService");
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
        appLog(
          "Processed voice result: $recognized, isCommand: $isCommand",
          name: "VoiceCommandService",
        );
      }
    } catch (e) {
      appLog("Error processing voice result: $e", name: "VoiceCommandService");
    }
  }

  Future<void> startListening() async {
    if (speechService != null) {
      await speechService!.start();
      appLog("Voice recognition started.", name: "VoiceCommandService");
    }
  }

  Future<void> stopListening() async {
    if (speechService != null) {
      await speechService!.stop();
      appLog("Voice recognition stopped.", name: "VoiceCommandService");
    }
  }

  void dispose() {
    _controller.close();
  }
}

const bool kEnableSplashDelayForPromo =
    false; // 👉 переключи на true для ролика - задержка сплешскрина

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final immersiveEnabled = prefs.getBool('immersiveMode') ?? false;

  // Включаем immersive-режим, если нужно
  if (immersiveEnabled) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // Если нужно задержать сплеш-экран
  if (kEnableSplashDelayForPromo) {
    WidgetsBinding.instance.deferFirstFrame();
  }

  // Перехватываем ошибки Flutter
  FlutterError.onError = (FlutterErrorDetails details) {
    appLog(
      "FlutterError: ${details.exception}",
      name: "FlutterError",
      stackTrace: details.stack,
    );
  };

  runZonedGuarded(
    () async {
      runApp(const MyApp());

      if (kEnableSplashDelayForPromo) {
        await Future.delayed(const Duration(seconds: 4));
        WidgetsBinding.instance.allowFirstFrame();
      }
    },
    (error, stackTrace) {
      appLog(
        "Unhandled error: $error",
        name: "runZonedGuarded",
        stackTrace: stackTrace,
      );
    },
  );
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

// Константы для настройки таймаутов
const Duration kVoiceServiceTimeout = Duration(seconds: 60);
const Duration kVoicePermissionWaitTimeout = Duration(seconds: 180);

class TimerPageState extends State<TimerPage> {
  // ValueNotifier для отображения статуса загрузки голосового сервиса.
  final ValueNotifier<String> loadingStatus = ValueNotifier(
    "Initializing voice service...",
  );
  // Текущий язык синтеза речи.
  String currentLanguage = "en-US";
  // Флаг, получено ли разрешение на использование микрофона.
  // Теперь не используется для запроса – будем проверять через Permission.microphone.status.
  bool _micPermissionGranted = false;

  final FlutterTts flutterTts = FlutterTts();
  Timer? _uiTimer;
  Duration _accumulated = Duration.zero;
  DateTime? _startTime;
  DateTime? _lapStartTime;
  bool isActive = false;
  double volume = 1.0;
  int intervalSeconds = 30;
  // Опция голосового управления, которую пользователь может включать/выключать через настройки.
  bool voiceControlEnabled = true;
  // Флаг активности голосового распознавания (отражается в индикаторе).
  bool voiceRecognitionActive = false;
  bool immersiveModeEnabled = false;

  String? _displayedVoiceText;
  bool _displayedVoiceIsCommand = false;
  Timer? _clearVoiceTextTimer;
  int _lastIntervalAnnounced = -1;
  final List<LapRecord> _lapRecords = [];
  late VoiceCommandService voiceService;
  StreamSubscription<VoiceCommandResult>? _voiceSub;

  // Рассчитываем общее время с учётом накопленного времени.
  Duration get elapsed {
    if (isActive && _startTime != null) {
      return _accumulated + DateTime.now().difference(_startTime!);
    }
    return _accumulated;
  }

  // Рассчитываем время текущего круга.
  Duration get currentLapElapsed {
    if (isActive && _lapStartTime != null) {
      return DateTime.now().difference(_lapStartTime!);
    }
    return Duration.zero;
  }

  /// Инициализирует голосовой сервис с модальным окном.
  ///
  /// 1. Сначала загружается языковая модель и создаётся распознаватель (initSpeechService отключён).
  /// 2. После успешной загрузки моделью в модальном окне обновляется сообщение на
  ///    "Language model loaded. Waiting for microphone permission...".
  /// 3. Затем запрашивается разрешение на микрофон (системный диалог).
  /// 4. Если разрешение уже получено – сразу инициализируется микрофонный сервис и распознавание запускается.
  /// 5. Если статус равен denied, permanentlyDenied или restricted – окно закрывается и голосовое управление отключается.
  /// 6. Если же статус не установлен (пользователь ещё не сделал выбор) – начинается ожидание с таймаутом kVoicePermissionWaitTimeout.
  Future<void> _initializeVoiceServiceWithModal() async {
    _showLoadingModelDialog();
    loadingStatus.value = "Initializing voice service...";
    try {
      // Загружаем языковую модель и создаём распознаватель без инициализации микрофонного сервиса.
      await voiceService
          .initialize(loadingStatus: loadingStatus, initSpeechService: false)
          .timeout(kVoiceServiceTimeout);
      loadingStatus.value =
          "Language model loaded. Waiting for microphone permission...";

      // Запрашиваем разрешение на микрофон.
      // (Мы не вызывали request() в initState, чтобы сохранить неопределённое состояние.)
      final micStatus = await Permission.microphone.request();
      // Если разрешение получено – запускаем сервис.
      if (micStatus.isGranted) {
        loadingStatus.value = "Starting speech service...";
        await voiceService.initializeSpeechService();
        Navigator.of(context).pop();
        await _startSpeechService();
      }
      // Если статус явно отказан – закрываем модальное окно и отключаем голосовое управление.
      else if (micStatus == PermissionStatus.denied ||
          micStatus.isPermanentlyDenied ||
          micStatus.isRestricted) {
        Navigator.of(context).pop();
        setState(() {
          voiceControlEnabled = false;
          voiceRecognitionActive = false;
        });
        appLog(
          "Microphone permission explicitly denied; voice service disabled.",
          name: "TimerPage",
        );
      }
      // Если статус не определён (теоретически) – начинаем ожидание.
      else {
        loadingStatus.value = "Waiting for microphone permission...";
        bool granted = await _waitForPermission(kVoicePermissionWaitTimeout);
        Navigator.of(context).pop();
        if (granted) {
          loadingStatus.value = "Starting speech service...";
          await voiceService.initializeSpeechService();
          await _startSpeechService();
        } else {
          setState(() {
            voiceControlEnabled = false;
            voiceRecognitionActive = false;
          });
          appLog(
            "Microphone permission not granted within timeout; voice service disabled.",
            name: "TimerPage",
          );
        }
      }
    } catch (e) {
      loadingStatus.value = "Initialization failed: ${e.toString()}";
      appLog("Voice service initialization failed: $e", name: "TimerPage");
      await Future.delayed(const Duration(seconds: 2));
      Navigator.of(context).pop();
      setState(() {
        voiceRecognitionActive = false;
      });
    }
  }

  /// Ожидает изменения статуса разрешения микрофона в течение заданного таймаута.
  /// Периодически (каждые 500 мс) проверяет статус.
  /// Возвращает true, если разрешение получено, иначе false.
  Future<bool> _waitForPermission(Duration timeout) async {
    const int checkIntervalMs = 500;
    final int maxChecks = timeout.inMilliseconds ~/ checkIntervalMs;
    for (int i = 0; i < maxChecks; i++) {
      await Future.delayed(const Duration(milliseconds: checkIntervalMs));
      final status = await Permission.microphone.status;
      if (status.isGranted) return true;
      // Если статус явно запрещён – прекращаем ожидание.
      if (status == PermissionStatus.denied ||
          status.isPermanentlyDenied ||
          status.isRestricted)
        return false;
    }
    return false;
  }

  /// Запускает голосовой сервис для распознавания речи.
  Future<void> _startSpeechService() async {
    loadingStatus.value = "Starting speech service...";
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      setState(() {
        voiceRecognitionActive = false;
      });
      appLog(
        "Microphone permission not granted; not starting speech service.",
        name: "TimerPage",
      );
      return;
    }
    try {
      await voiceService.startListening();
      setState(() {
        voiceRecognitionActive = true;
      });
      appLog("Speech service started.", name: "TimerPage");
    } catch (e, st) {
      appLog(
        "Error starting speech service: $e",
        name: "TimerPage",
        stackTrace: st,
      );
      await _restartSpeechService();
    }
  }

  /// Перезапускает голосовой сервис.
  Future<void> _restartSpeechService() async {
    appLog("Restarting speech service...", name: "TimerPage");
    await _stopSpeechService();
    await Future.delayed(const Duration(seconds: 2));
    try {
      await voiceService.initialize(
        loadingStatus: loadingStatus,
        initSpeechService: false,
      );
      await voiceService.initializeSpeechService();
      await _startSpeechService();
      appLog("Speech service restarted.", name: "TimerPage");
    } catch (e, st) {
      appLog(
        "Error restarting speech service: $e",
        name: "TimerPage",
        stackTrace: st,
      );
    }
  }

  /// Останавливает голосовой сервис.
  Future<void> _stopSpeechService() async {
    loadingStatus.value = "Stopping speech service...";
    try {
      await voiceService.stopListening();
      setState(() {
        voiceRecognitionActive = false;
      });
      appLog("Speech service stopped.", name: "TimerPage");
    } catch (e, st) {
      appLog(
        "Error stopping speech service: $e",
        name: "TimerPage",
        stackTrace: st,
      );
    }
  }

  /// Показывает модальное окно с индикатором загрузки/ожидания.
  Future<void> _showLoadingModelDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 10),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: loadingStatus,
                    builder: (context, value, child) {
                      appLog("Loading status: $value", name: "UI STATUS");
                      return Text(value);
                    },
                  ),
                ),
              ],
            ),
          ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Здесь мы НЕ запрашиваем разрешение, чтобы не фиксировать результат заранее.
    _loadSettings();

    // Настраиваем синтез речи.
    flutterTts.setLanguage(currentLanguage);
    flutterTts.setVolume(volume);

    // Инициализируем голосовой сервис.
    voiceService = VoiceCommandService();

    // После построения UI запускаем инициализацию голосового сервиса с модальным окном.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeVoiceServiceWithModal();

      // Подписываемся на поток голосовых команд.
      _voiceSub = voiceService.commandStream.listen(
        (result) {
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
        },
        onError: (error) async {
          appLog("Speech service error: $error", name: "TimerPage");
          await _restartSpeechService();
        },
      );
      _maybeShowHelpDialog();
    });

    // UI-таймер для обновления экрана и голосового объявления интервалов.
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
          appLog("Announced interval: $announcement", name: "TimerPage");
        }
      }
    });
  }

  /// Отображает диалог помощи при первом запуске.
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

  /// Форматирует строку для голосового объявления интервала.
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

  /// Форматирует время в строку формата MM:SS:CC.
  String _formatTime(Duration duration) {
    int minutes = duration.inMinutes;
    int seconds = duration.inSeconds % 60;
    int centiseconds = ((duration.inMilliseconds % 1000) / 10).floor();
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${centiseconds.toString().padLeft(2, '0')}";
  }

  /// Форматирует время для голосового объявления (без сотых).
  String _formatAnnouncement(Duration duration) {
    int minutes = duration.inMinutes;
    int seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return "$minutes minute${minutes != 1 ? "s" : ""} and $seconds second${seconds != 1 ? "s" : ""}";
    } else {
      return "$seconds second${seconds != 1 ? "s" : ""}";
    }
  }

  /// Обрабатывает команду записи круга.
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
      appLog(
        "Lap recorded: Circle $lapNumber, lap time: $currentLap, overall: $overall",
        name: "TimerPage",
      );
      setState(() {});
    }
  }

  /// Обрабатывает голосовые команды, полученные от сервиса.
  void _handleVoiceCommand(String commandText) {
    appLog("Voice command received: $commandText", name: "TimerPage");
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
        appLog(
          "Voice command executed: start/go/begin/resume",
          name: "TimerPage",
        );
      }
    } else if (commandText.contains("stop") || commandText.contains("pause")) {
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
        appLog("Voice command executed: stop/pause", name: "TimerPage");
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
      appLog(
        "Voice command executed: reset/clear/restart/renew",
        name: "TimerPage",
      );
    }
  }

  /// Загружает настройки (громкость, интервал, голосовое управление, immersive mode).
  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      volume = prefs.getDouble('volume') ?? 1.0;
      intervalSeconds = prefs.getInt('intervalSeconds') ?? 30;
      voiceControlEnabled = prefs.getBool('voiceControlEnabled') ?? true;
      immersiveModeEnabled = prefs.getBool('immersiveMode') ?? false;
    });
    flutterTts.setVolume(volume);
  }

  /// Сохраняет настройки.
  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('volume', volume);
    await prefs.setInt('intervalSeconds', intervalSeconds);
    await prefs.setBool('voiceControlEnabled', voiceControlEnabled);
    await prefs.setBool('immersiveMode', immersiveModeEnabled);
  }

  /// Виджет для фиксированных кнопок (например, в ландшафтном режиме).
  Widget _buildFixedButtons() {
    return Container(
      height: 80,
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
                appLog("Manual: Stopwatch started", name: "TimerPage");
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
                appLog("Manual: Stopwatch stopped", name: "TimerPage");
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

  /// Таблица записей кругов.
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

  /// Возвращает кнопку "Lap" (если таймер активен) или "Reset" (если таймер остановлен).
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

  /// Обработчик кнопки сброса таймера.
  void _handleReset() {
    flutterTts.speak("Stopwatch in zero");
    setState(() {
      isActive = false;
      _accumulated = Duration.zero;
      _startTime = null;
      _lapStartTime = null;
      _lapRecords.clear();
    });
    appLog("Manual: Stopwatch reset", name: "TimerPage");
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
      // Одноколоночный макет (портрет или отсутствие записей).
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
            const SizedBox(height: 8),
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
                    appLog("Manual: Stopwatch started", name: "TimerPage");
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
                    appLog("Manual: Stopwatch stopped", name: "TimerPage");
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
      Widget leftColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
          const SizedBox(height: 8),
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
          const Spacer(),
          _buildFixedButtons(),
        ],
      );
      Widget rightColumn = _buildLapTable();
      bodyContent = Row(
        children: [
          Expanded(child: leftColumn),
          const SizedBox(width: 20),
          Expanded(child: rightColumn),
        ],
      );
    }

    return WillPopScope(
      onWillPop: () async {
        final bool exitConfirmed =
            await showDialog<bool>(
              context: context,
              builder:
                  (BuildContext context) => AlertDialog(
                    title: const Text("Confirm exit"),
                    content: const Text("Do you really want to exit the app?"),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text("No"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text("Yes"),
                      ),
                    ],
                  ),
            ) ??
            false;
        return exitConfirmed;
      },
      child: Scaffold(
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
      ),
    );
  }

  /// Показывает диалог справки.
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
                    "- Stop / Pause: Stop the stopwatch and announce the elapsed time.",
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
            // Внутри SettingsPageState.build(...), замените обработчик onChanged для SwitchListTile:
            SwitchListTile(
              title: const Text('Voice Control'),
              value: widget.state.voiceControlEnabled,
              onChanged: (bool value) async {
                if (value) {
                  // Пользователь пытается включить голосовое распознавание.
                  PermissionStatus status = await Permission.microphone.status;

                  if (status.isDenied ||
                      status.isRestricted ||
                      status.isPermanentlyDenied) {
                    // Показываем диалог с предложением открыть настройки
                    final shouldOpenSettings = await showDialog<bool>(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text(
                              "Microphone permission not granted",
                            ),
                            content: const Text(
                              "To use voice control, please allow microphone access in the app settings.",
                            ),
                            actions: [
                              TextButton(
                                onPressed:
                                    () => Navigator.of(context).pop(false),
                                child: const Text("Отмена"),
                              ),
                              TextButton(
                                onPressed:
                                    () => Navigator.of(context).pop(true),
                                child: const Text("Открыть настройки"),
                              ),
                            ],
                          ),
                    );

                    if (shouldOpenSettings == true) {
                      // Открываем системные настройки приложения
                      await openAppSettings();
                    }

                    // Отключаем переключатель обратно
                    setState(() {
                      widget.state.voiceControlEnabled = false;
                      widget.state.voiceRecognitionActive = false;
                    });
                    await widget.state._saveSettings();
                    return;
                  }

                  // Разрешение уже есть или только что получено
                  final micGranted = await requestMicrophonePermission();
                  if (!micGranted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Microphone permission not granted. Voice recognition disabled.",
                        ),
                      ),
                    );
                    setState(() {
                      widget.state.voiceControlEnabled = false;
                      widget.state.voiceRecognitionActive = false;
                    });
                    await widget.state._saveSettings();
                    return;
                  }

                  // Всё в порядке — включаем
                  setState(() {
                    widget.state.voiceControlEnabled = true;
                  });
                  await widget.state._saveSettings();
                  appLog(
                    "Voice control enabled. Starting initialization...",
                    name: "SettingsPage",
                  );
                  widget.state
                      ._initializeVoiceServiceWithModal()
                      .then((_) {
                        appLog(
                          "Voice service started via settings.",
                          name: "SettingsPage",
                        );
                      })
                      .catchError((error, stackTrace) {
                        appLog(
                          "Error during voice service initialization: $error",
                          name: "SettingsPage",
                          stackTrace: stackTrace,
                        );
                      });
                } else {
                  // Выключение распознавания
                  setState(() {
                    widget.state.voiceControlEnabled = false;
                  });
                  await widget.state._saveSettings();
                  appLog(
                    "Voice control disabled. Stopping voice service...",
                    name: "SettingsPage",
                  );
                  widget.state
                      ._stopSpeechService()
                      .then((_) {
                        appLog(
                          "Voice service stopped via settings.",
                          name: "SettingsPage",
                        );
                      })
                      .catchError((error, stackTrace) {
                        appLog(
                          "Error stopping voice service: $error",
                          name: "SettingsPage",
                          stackTrace: stackTrace,
                        );
                      });
                }
              },
            ),
            SwitchListTile(
              title: const Text("Full screen mode (immersive)"),
              value: widget.state.immersiveModeEnabled,
              onChanged: (bool value) {
                // Мгновенно обновляем UI
                setState(() {
                  widget.state.immersiveModeEnabled = value;
                });

                // Сохраняем в настройки
                widget.state._saveSettings();

                // Показываем Flushbar после перерисовки, чтобы не мешать переключателю
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Flushbar(
                    message:
                        "The new display mode will take effect after restarting the app.",
                    duration: const Duration(seconds: 2),
                    margin: const EdgeInsets.all(12),
                    borderRadius: BorderRadius.circular(8),
                    backgroundColor: Colors.black87,
                    flushbarPosition: FlushbarPosition.BOTTOM,
                  ).show(context);
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
