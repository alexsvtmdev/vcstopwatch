import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // Используем super параметры и const конструктор

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
  const TimerPage({
    super.key,
  }); // Используем super параметры и const конструктор

  @override
  TimerPageState createState() => TimerPageState();
}

class TimerPageState extends State<TimerPage> {
  static const duration = Duration(milliseconds: 10); // Убрано лишнее const
  int timeMilliseconds = 0;
  bool isActive = false;
  Timer? timer;

  void handleTick() {
    if (isActive) {
      setState(() {
        timeMilliseconds += 10;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(duration, (Timer t) {
      handleTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    double seconds = (timeMilliseconds / 1000) % 60;
    int minutes = (timeMilliseconds / (1000 * 60)).floor();
    String formattedTime =
        "${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}";

    return Scaffold(
      appBar: AppBar(title: Text('VoiceControl Timer')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              formattedTime,
              style: TextStyle(fontSize: 48, color: Colors.white),
            ),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ElevatedButton(
                  style: ElevatedButton.styleFrom(shape: StadiumBorder()),
                  onPressed: () {
                    setState(() {
                      isActive = !isActive;
                    });
                  },
                  child: Text(isActive ? 'Pause' : 'Start'),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(shape: StadiumBorder()),
                  onPressed: () {
                    setState(() {
                      isActive = false;
                      timeMilliseconds = 0;
                    });
                  },
                  child: Text('Reset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
