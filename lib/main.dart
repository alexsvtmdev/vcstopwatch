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

      if (totalSeconds % intervalSeconds == 0) {
        String toSpeak = '';
        if (minutes > 0) {
          toSpeak += '$minutes minute${minutes > 1 ? "s" : ""} ';
        }
        toSpeak += '$seconds second${seconds != 1 ? "s" : ""}';
        flutterTts.speak(toSpeak);
      }
    }
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
                      flutterTts.speak('Timer reset');
                    });
                  },
                  child: const Text('Reset'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (!isActive) {
                      flutterTts.speak('Timer started');
                    } else {
                      int totalSeconds = timeMilliseconds ~/ 1000;
                      int minutes = totalSeconds ~/ 60;
                      int seconds = totalSeconds % 60;
                      String timeSpoken =
                          "${minutes > 0 ? "$minutes minutes and " : ""}$seconds seconds";
                      flutterTts.speak("Timer stopped at $timeSpoken");
                    }
                    setState(() {
                      isActive = !isActive;
                    });
                  },
                  child: Text(isActive ? 'Pause' : 'Start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  final TimerPageState state;

  SettingsPage({required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Volume Control'),
            subtitle: Slider(
              value: state.volume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: "${(state.volume * 100).toInt()}%",
              onChanged: (double value) {
                state.setState(() {
                  state.volume = value;
                });
              },
            ),
          ),
          ListTile(
            title: const Text('Speech Interval'),
            trailing: DropdownButton<int>(
              value: state.intervalSeconds,
              items: const [
                DropdownMenuItem(value: 10, child: Text("10 Seconds")),
                DropdownMenuItem(value: 20, child: Text("20 Seconds")),
                DropdownMenuItem(value: 30, child: Text("30 Seconds")),
                DropdownMenuItem(value: 60, child: Text("1 Minute")),
              ],
              onChanged: (int? newValue) {
                if (newValue != null) {
                  state.setState(() {
                    state.intervalSeconds = newValue;
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
