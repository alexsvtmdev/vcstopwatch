import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
  Timer? listeningChecker;
  int timeMilliseconds = 0;
  bool isActive = false;
  double volume = 1.0;
  int intervalSeconds = 30;
  bool voiceControlEnabled = true;

  // Speech-to-text объект
  late stt.SpeechToText _speech;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    flutterTts.setVolume(volume);
    timer = Timer.periodic(const Duration(milliseconds: 10), (Timer t) {
      handleTick();
    });
    _initSpeech();
    // Проверка прослушивания каждые 10 секунд
    listeningChecker = Timer.periodic(const Duration(seconds: 10), (Timer t) {
      if (voiceControlEnabled && !_isListening) {
        debugPrint("ListeningChecker: Not listening, restarting...");
        _startListening();
      }
    });
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    bool available = await _speech.initialize(
      onError: (error) {
        debugPrint("SpeechToText error: $error");
      },
    );
    debugPrint("SpeechToText initialized: available = $available");
    if (voiceControlEnabled && available) {
      _startListening();
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
    debugPrint(
      "Settings loaded: volume=$volume, intervalSeconds=$intervalSeconds, voiceControlEnabled=$voiceControlEnabled",
    );
  }

  Future<void> _saveSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('volume', volume);
    await prefs.setInt('intervalSeconds', intervalSeconds);
    await prefs.setBool('voiceControlEnabled', voiceControlEnabled);
    debugPrint(
      "Settings saved: volume=$volume, intervalSeconds=$intervalSeconds, voiceControlEnabled=$voiceControlEnabled",
    );
  }

  void handleTick() {
    if (isActive) {
      setState(() {
        timeMilliseconds += 10;
      });
      int totalSeconds = timeMilliseconds ~/ 1000;
      int minutes = totalSeconds ~/ 60;
      int seconds = totalSeconds % 60;
      if (totalSeconds > 0 && totalSeconds % intervalSeconds == 0) {
        String timeAnnouncement =
            seconds == 0
                ? "$minutes minute${minutes != 1 ? "s" : ""}"
                : "${minutes > 0 ? "$minutes minute${minutes != 1 ? "s" : ""} and " : ""}$seconds second${seconds != 1 ? "s" : ""}";
        debugPrint("Timer announcement: $timeAnnouncement");
        flutterTts.speak(timeAnnouncement);
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
      debugPrint("Voice command: Timer started.");
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
      debugPrint("Voice command: Timer paused at ${_formattedTime()}.");
      flutterTts.speak("Timer paused at ${_formattedTime()}");
      setState(() {
        isActive = false;
      });
    } else {
      flutterTts.speak("Timer is not running");
    }
  }

  void _resetTimer() {
    debugPrint("Voice command: Timer reset.");
    flutterTts.speak("Timer reset");
    setState(() {
      isActive = false;
      timeMilliseconds = 0;
    });
  }

  void _startListening() async {
    if (!voiceControlEnabled) {
      debugPrint("Voice control is disabled, not starting listening.");
      return;
    }
    debugPrint("Starting speech recognition for 2 hours...");
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
      });
      _speech.listen(
        onResult: (result) {
          debugPrint("Speech result: ${result.recognizedWords}");
          String recognized = result.recognizedWords.toLowerCase();
          if (recognized.contains("start")) {
            debugPrint("Voice command 'start' detected.");
            _startTimer();
          } else if (recognized.contains("stop")) {
            debugPrint("Voice command 'stop' detected.");
            _pauseTimer();
          } else if (recognized.contains("reset")) {
            debugPrint("Voice command 'reset' detected.");
            _resetTimer();
          } else {
            debugPrint("No valid command found in: $recognized");
          }
          // Не вызываем _speech.stop(), чтобы продолжить прослушивание.
        },
        listenFor: const Duration(hours: 2),
        pauseFor: const Duration(hours: 2),
        partialResults: false,
        localeId: "en_US",
      );
      debugPrint("Speech recognition started.");
    } else {
      debugPrint("Speech recognition not available.");
    }
  }

  void _toggleListening() {
    if (!voiceControlEnabled) {
      debugPrint("Voice control is disabled.");
      return;
    }
    if (!_isListening) {
      _startListening();
    } else {
      _speech.stop();
      debugPrint("Speech recognition manually stopped.");
      setState(() {
        _isListening = false;
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    listeningChecker?.cancel();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String formattedTime = _formattedTime();
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Иконка состояния голосового распознавания над таймером.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isListening ? Icons.mic : Icons.mic_off,
                  size: 40,
                  color: _isListening ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 10),
                Text(
                  _isListening ? "Listening..." : "Not listening",
                  style: const TextStyle(fontSize: 18, color: Colors.white),
                ),
              ],
            ),
            Text(
              formattedTime,
              style: const TextStyle(fontSize: 80, color: Colors.white),
            ),
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
                    debugPrint("Timer reset command executed.");
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
                      debugPrint("Timer started command executed.");
                      setState(() {
                        isActive = true;
                      });
                    } else {
                      int totalSeconds = timeMilliseconds ~/ 1000;
                      int displayMinutes = totalSeconds ~/ 60;
                      int displaySeconds = totalSeconds % 60;
                      String announcement =
                          "Timer stopped at $displayMinutes minute${displayMinutes != 1 ? "s" : ""} and $displaySeconds second${displaySeconds != 1 ? "s" : ""}";
                      flutterTts.speak(announcement);
                      debugPrint(
                        "Timer stopped command executed: $announcement",
                      );
                      setState(() {
                        isActive = false;
                      });
                    }
                  },
                  child: Text(isActive ? 'Stop' : 'Start'),
                ),
              ],
            ),
            // Кнопка для управления голосовым распознаванием.
            FloatingActionButton(
              onPressed: _toggleListening,
              child: Icon(_isListening ? Icons.mic : Icons.mic_none),
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
                  debugPrint("Volume changed to: $value");
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
                    debugPrint("Speech interval changed to: $newValue seconds");
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
                });
                debugPrint("Voice control setting changed to: $value");
              },
            ),
          ],
        ),
      ),
    );
  }
}
