import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  @override
  void initState() {
    super.initState();
    // Создаем таймер один раз, который каждые 10 мс вызывает handleTick()
    timer = Timer.periodic(const Duration(milliseconds: 10), (Timer t) {
      handleTick();
    });
    flutterTts.setVolume(volume);
  }

  void handleTick() {
    if (isActive) {
      setState(() {
        timeMilliseconds += 10;
      });
      int totalSeconds = timeMilliseconds ~/ 1000;
      int minutes = totalSeconds ~/ 60;
      int seconds = totalSeconds % 60;

      // Голосовое оповещение происходит во время работы таймера, на заданном интервале.
      if (totalSeconds > 0 && totalSeconds % intervalSeconds == 0) {
        String timeAnnouncement;
        if (seconds == 0) {
          timeAnnouncement = "$minutes minute${minutes > 1 ? "s" : ""}";
        } else {
          timeAnnouncement =
              "${minutes > 0 ? "$minutes minute${minutes > 1 ? "s" : ""} and " : ""}$seconds second${seconds != 1 ? "s" : ""}";
        }
        flutterTts.speak(timeAnnouncement);
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double seconds = (timeMilliseconds / 1000) % 60;
    int minutes = (timeMilliseconds / (1000 * 60)).floor();
    String formattedTime =
        "${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}";

    return Scaffold(
      appBar: AppBar(
        title: const Text('VoiceControl Timer'),
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
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // Отображение времени с увеличенным шрифтом
            Text(
              formattedTime,
              style: const TextStyle(fontSize: 80, color: Colors.white),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
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
                    } else {
                      // При нажатии на кнопку Stop произносится общее количество минут и секунд
                      int totalSeconds = timeMilliseconds ~/ 1000;
                      int displayMinutes = totalSeconds ~/ 60;
                      int displaySeconds = totalSeconds % 60;
                      String announcement =
                          "Timer stopped at $displayMinutes minute${displayMinutes != 1 ? "s" : ""} and $displaySeconds second${displaySeconds != 1 ? "s" : ""}";
                      flutterTts.speak(announcement);
                      setState(() {
                        isActive = false;
                      });
                    }
                  },
                  // Если таймер активен, кнопка отображает "Stop", иначе "Start"
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
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
