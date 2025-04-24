import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AlarmApp());
}

class AlarmApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Alarm',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: AlarmSetupPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Simple alarm model
class Alarm {
  final int hour, minute;
  final List<String> days;
  Alarm({required this.hour, required this.minute, required this.days});

  Map<String, dynamic> toJson() => {
        'hour': hour,
        'minute': minute,
        'days': days,
      };

  factory Alarm.fromJson(Map<String, dynamic> j) => Alarm(
        hour: j['hour'],
        minute: j['minute'],
        days: List<String>.from(j['days']),
      );

  String get formattedTime =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Main alarm‐setup screen
class AlarmSetupPage extends StatefulWidget {
  @override
  _AlarmSetupPageState createState() => _AlarmSetupPageState();
}

class _AlarmSetupPageState extends State<AlarmSetupPage> {
  TimeOfDay? _picked;
  final List<String> _weekDays = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  final Map<String,int> _dayMap = {
    'Mon':1,'Tue':2,'Wed':3,'Thu':4,'Fri':5,'Sat':6,'Sun':7,
  };
  List<String> _selDays = [];
  List<Alarm> _alarms = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList('alarms') ?? [];
    setState(() {
      _alarms = raw.map((s) => Alarm.fromJson(json.decode(s))).toList();
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      'alarms',
      _alarms.map((a) => json.encode(a.toJson())).toList(),
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t != null) setState(() => _picked = t);
  }

  void _toggleDay(String d) {
    setState(() {
      if (_selDays.contains(d)) _selDays.remove(d);
      else _selDays.add(d);
    });
  }

  void _addAlarm() {
    if (_picked==null || _selDays.isEmpty) return;
    final alarm = Alarm(
      hour: _picked!.hour,
      minute: _picked!.minute,
      days: List.from(_selDays),
    );
    setState(() => _alarms.add(alarm));
    _save();

    final now = DateTime.now();
    for (var d in _selDays) {
      final wd = _dayMap[d]!;
      var diff = (wd - now.weekday) % 7;
      if (diff == 0) {
        final todayAt = DateTime(
          now.year, now.month, now.day,
          _picked!.hour, _picked!.minute,
        );
        if (todayAt.isBefore(now)) diff = 7;
      }
      final scheduled = DateTime(
        now.year,
        now.month,
        now.day + diff,          // << fixed: add days here
        _picked!.hour,
        _picked!.minute,
      );
      Timer(scheduled.difference(now), () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MathChallengeScreen()),
        );
      });
    }

    ScaffoldMessenger.of(context)
      ..clearMaterialBanners()
      ..showMaterialBanner(MaterialBanner(
        content: Text(
          'Alarm set for ${alarm.formattedTime} on ${alarm.days.join(", ")}'
        ),
        backgroundColor: Colors.indigo.shade100,
        actions: [
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: Text('OK'),
          )
        ],
      ));
  }

  void _delete(int i) {
    setState(() => _alarms.removeAt(i));
    _save();
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text('Set Alarm')),
      body: Column(children:[
        Expanded(child: Scrollbar(
          thumbVisibility: true,
          child: ListView.builder(
            itemCount: _alarms.length,
            itemBuilder: (_,i){
              final a = _alarms[i];
              return ListTile(
                title: Text(a.formattedTime),
                subtitle: Text('Days: ${a.days.join(", ")}'),
                trailing: IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: ()=>_delete(i),
                ),
              );
            },
          ),
        )),
        Padding(
          padding: EdgeInsets.all(16),
          child: Column(children:[
            Text(
              _picked==null
                ? 'No time selected'
                : 'Picked: ${_picked!.format(ctx)}',
              style: TextStyle(fontSize: 18),
            ),
            ElevatedButton(onPressed: _pickTime, child: Text('Pick Alarm Time')),
            Wrap(
              spacing: 8,
              children: _weekDays.map((d){
                final sel = _selDays.contains(d);
                return FilterChip(
                  label: Text(d),
                  selected: sel,
                  onSelected: (_) => _toggleDay(d),
                );
              }).toList(),
            ),
            SizedBox(height: 12),
            ElevatedButton(onPressed: _addAlarm, child: Text('Set Alarm')),
          ]),
        )
      ]),
    );
  }
}

/// Fires when the alarm goes off and loops the sound
/// until you solve 10 two-digit additions.
class MathChallengeScreen extends StatefulWidget {
  @override
  _MathChallengeScreenState createState() => _MathChallengeScreenState();
}

class _MathChallengeScreenState extends State<MathChallengeScreen> {
  final _ctrl = TextEditingController();
  final List<Map<String,int>> _probs = [];
  int _idx = 0;
  late AudioPlayer _player;

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    for (int i = 0; i < 10; i++) {
      final a = rnd.nextInt(90) + 10;
      final b = rnd.nextInt(90) + 10;
      _probs.add({'a':a,'b':b,'ans':a+b});
    }
    _player = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _player.play(AssetSource('alarm.mp3'));
    });
  }

  void _submit() {
    final n = int.tryParse(_ctrl.text.trim());
    if (n == _probs[_idx]['ans']) {
      if (_idx < 9) {
        setState(() {
          _idx++;
          _ctrl.clear();
        });
      } else {
        _player.stop();
        Navigator.of(context).pop();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wrong—try again.')),
      );
      _ctrl.clear();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    final p = _probs[_idx];
    return Scaffold(
      appBar: AppBar(title: Text('Solve 10 to Snooze')),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            Text('Problem ${_idx+1} of 10', style: TextStyle(fontSize:20)),
            SizedBox(height:16),
            Text('${p['a']} + ${p['b']} = ?', style: TextStyle(fontSize:36)),
            SizedBox(height:24),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Your answer'),
            ),
            SizedBox(height:24),
            ElevatedButton(onPressed: _submit, child: Text('Submit')),
          ],
        ),
      ),
    );
  }
}
