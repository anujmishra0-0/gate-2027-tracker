import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// GATE 2027 PRO — pubspec.yaml dependencies needed:
//   flutter:
//     sdk: flutter
//   cupertino_icons: ^1.0.6
//   shared_preferences: ^2.2.2
// ============================================================

void main() {
  runApp(const GateProApp());
}

class GateProApp extends StatelessWidget {
  const GateProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GATE 2027 Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
        ),
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      home: const MainLayout(),
    );
  }
}

// ============================================================
// PERSISTENCE / STREAK ENGINE
// Tracks daily activity (tasks done, pomodoro sessions, mock
// tests) so the dashboard can show a GitHub-style heatmap and
// a running streak — this is the thing that actually keeps
// aspirants coming back every day.
// ============================================================
class StorageService {
  static const _kTasks = 'gp_tasks';
  static const _kActivity = 'gp_activity'; // { "2026-09-21": 3 }
  static const _kStreak = 'gp_streak';
  static const _kBestStreak = 'gp_best_streak';
  static const _kLastDate = 'gp_last_date';
  static const _kPomodoroMinutes = 'gp_pomo_minutes';
  static const _kPomodoroSessions = 'gp_pomo_sessions';
  static const _kMockResults = 'gp_mock_results'; // list of result maps

  static String _today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static Future<List<Map<String, dynamic>>> loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTasks);
    if (raw == null) {
      return [
        {'title': 'Complete Linear Algebra Notes', 'done': false, 'subject': 'Math'},
        {'title': 'Solve 50 Aptitude PYQs', 'done': true, 'subject': 'Apti'},
        {'title': 'Revise Operating Systems', 'done': false, 'subject': 'Core'},
      ];
    }
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> saveTasks(List<Map<String, dynamic>> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTasks, jsonEncode(tasks));
  }

  static Future<void> recordActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kActivity);
    final Map<String, dynamic> activity = raw == null ? {} : jsonDecode(raw);
    final today = _today();
    activity[today] = (activity[today] ?? 0) + 1;
    await prefs.setString(_kActivity, jsonEncode(activity));
    await _recalcStreak(prefs);
  }

  static Future<void> _recalcStreak(SharedPreferences prefs) async {
    final today = _today();
    final lastDate = prefs.getString(_kLastDate);
    int streak = prefs.getInt(_kStreak) ?? 0;
    int best = prefs.getInt(_kBestStreak) ?? 0;

    if (lastDate == today) {
      // already counted today
    } else {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yStr = '${yesterday.year.toString().padLeft(4, '0')}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      if (lastDate == yStr) {
        streak += 1;
      } else {
        streak = 1;
      }
      await prefs.setString(_kLastDate, today);
      await prefs.setInt(_kStreak, streak);
      if (streak > best) {
        best = streak;
        await prefs.setInt(_kBestStreak, best);
      }
    }
  }

  static Future<Map<String, dynamic>> loadStreakSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kActivity);
    final Map<String, dynamic> activity = raw == null ? {} : jsonDecode(raw);
    return {
      'streak': prefs.getInt(_kStreak) ?? 0,
      'best': prefs.getInt(_kBestStreak) ?? 0,
      'activity': activity,
    };
  }

  static Future<void> addPomodoroSession(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final total = (prefs.getInt(_kPomodoroMinutes) ?? 0) + minutes;
    final sessions = (prefs.getInt(_kPomodoroSessions) ?? 0) + 1;
    await prefs.setInt(_kPomodoroMinutes, total);
    await prefs.setInt(_kPomodoroSessions, sessions);
    await recordActivity();
  }

  static Future<Map<String, int>> loadPomodoroStats() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'minutes': prefs.getInt(_kPomodoroMinutes) ?? 0,
      'sessions': prefs.getInt(_kPomodoroSessions) ?? 0,
    };
  }

  static Future<void> saveMockResult(Map<String, dynamic> result) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMockResults);
    final List list = raw == null ? [] : jsonDecode(raw);
    list.insert(0, result);
    if (list.length > 20) list.removeRange(20, list.length);
    await prefs.setString(_kMockResults, jsonEncode(list));
    await recordActivity();
  }

  static Future<List<Map<String, dynamic>>> loadMockResults() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kMockResults);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }
}

// ============================================================
// MAIN NAVIGATION
// ============================================================
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    TaskScreen(),
    MockTestHomeScreen(),
    FormulaScreen(),
    PomodoroScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey(_currentIndex), child: _screens[_currentIndex]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF1E293B),
        indicatorColor: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Syllabus'),
          NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Mock Test'),
          NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: 'Cards'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: 'Focus'),
        ],
      ),
    );
  }
}

// ============================================================
// 1. DASHBOARD — countdown, streak heatmap, weightage-based
//    smart revision planner, quick link to virtual calculator
// ============================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _streakData;
  Map<String, int>? _pomoStats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await StorageService.loadStreakSummary();
    final p = await StorageService.loadPomodoroStats();
    if (mounted) {
      setState(() {
        _streakData = s;
        _pomoStats = p;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetDate = DateTime(2027, 2, 6);
    final today = DateTime.now();
    final daysLeft = targetDate.difference(today).inDays;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome, Aspirant!', style: TextStyle(color: Colors.grey[400], fontSize: 16)),
                    const Text('Crush GATE 2027 🚀', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  ],
                ),
                InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GateCalculatorScreen())),
                  child: const CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFF8B5CF6),
                    child: Icon(Icons.calculate_outlined, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            TweenAnimationBuilder(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              builder: (context, val, child) {
                return Transform.scale(
                  scale: val,
                  child: Opacity(
                    opacity: val,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 8))],
                      ),
                      child: Column(
                        children: [
                          const Text('TIME TO EXAM', style: TextStyle(color: Colors.white70, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Text('$daysLeft', style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, color: Colors.white, height: 1)),
                          const Text('DAYS REMAINING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // ---- Streak + Heatmap ----
            _StreakCard(streakData: _streakData),
            const SizedBox(height: 24),

            // ---- Pomodoro quick stats ----
            Row(
              children: [
                Expanded(child: _StatChip(label: 'Focus Sessions', value: '${_pomoStats?['sessions'] ?? 0}', icon: Icons.local_fire_department, color: const Color(0xFF10B981))),
                const SizedBox(width: 12),
                Expanded(child: _StatChip(label: 'Focus Minutes', value: '${_pomoStats?['minutes'] ?? 0}', icon: Icons.hourglass_bottom, color: const Color(0xFF8B5CF6))),
              ],
            ),
            const SizedBox(height: 24),

            const Text('Smart Revision Planner', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Prioritized by approx. GATE CS marks weightage', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            const SizedBox(height: 12),
            const SmartRevisionWidget(),
            const SizedBox(height: 24),

            const Text('Daily Motivation', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.format_quote, color: Color(0xFF10B981), size: 36),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Success is the sum of small efforts, repeated day in and day out.",
                      style: TextStyle(fontStyle: FontStyle.italic, fontSize: 15),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final Map<String, dynamic>? streakData;
  const _StreakCard({required this.streakData});

  @override
  Widget build(BuildContext context) {
    final streak = streakData?['streak'] ?? 0;
    final best = streakData?['best'] ?? 0;
    final Map<String, dynamic> activity = streakData?['activity'] ?? {};

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              Text('$streak day streak', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('Best: $best', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
          const SizedBox(height: 14),
          _Heatmap(activity: activity),
        ],
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  final Map<String, dynamic> activity;
  const _Heatmap({required this.activity});

  Color _colorFor(int count) {
    if (count <= 0) return Colors.white10;
    if (count == 1) return const Color(0xFF10B981).withValues(alpha: 0.35);
    if (count <= 3) return const Color(0xFF10B981).withValues(alpha: 0.65);
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    // 12 weeks back, aligned to weeks (columns), 7 rows (days)
    final start = today.subtract(Duration(days: 83));
    final firstMonday = start.subtract(Duration(days: (start.weekday - 1)));

    List<Widget> columns = [];
    for (int w = 0; w < 12; w++) {
      List<Widget> days = [];
      for (int d = 0; d < 7; d++) {
        final date = firstMonday.add(Duration(days: w * 7 + d));
        if (date.isAfter(today)) {
          days.add(const SizedBox(width: 11, height: 11));
        } else {
          final key = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          final count = (activity[key] ?? 0) as int;
          days.add(Container(
            width: 11,
            height: 11,
            margin: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(color: _colorFor(count), borderRadius: BorderRadius.circular(3)),
          ));
        }
      }
      columns.add(Column(mainAxisSize: MainAxisSize.min, children: days));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(children: columns),
    );
  }
}

// ============================================================
// SMART REVISION — subject weightage table (approximate, based
// on recent-year GATE CS trends) used to rank what to revise
// ============================================================
class SubjectWeight {
  final String subject;
  final int approxMarks; // out of 100, approx trend
  final String tip;
  const SubjectWeight(this.subject, this.approxMarks, this.tip);
}

const List<SubjectWeight> kSubjectWeights = [
  SubjectWeight('Algorithms & Data Structures', 13, 'Focus: DP, graph algorithms, complexity analysis'),
  SubjectWeight('Programming (C) & Aptitude', 15, 'Practice trace-the-code + General Aptitude PYQs daily'),
  SubjectWeight('Operating Systems', 9, 'Deadlock, scheduling, memory management, paging'),
  SubjectWeight('DBMS', 8, 'Normalization, transactions, SQL, indexing'),
  SubjectWeight('Computer Networks', 8, 'Subnetting, TCP/IP, routing algorithms'),
  SubjectWeight('Theory of Computation', 7, 'DFA/NFA, CFG, decidability'),
  SubjectWeight('Computer Organization & Architecture', 8, 'Pipelining, cache, memory hierarchy'),
  SubjectWeight('Discrete Mathematics', 9, 'Graph theory, relations, combinatorics'),
  SubjectWeight('Engineering Mathematics', 11, 'Linear algebra, probability, calculus'),
  SubjectWeight('Compiler Design', 5, 'Parsing, syntax-directed translation'),
  SubjectWeight('Digital Logic', 5, 'K-maps, number systems, sequential circuits'),
];

class SmartRevisionWidget extends StatelessWidget {
  const SmartRevisionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final sorted = [...kSubjectWeights]..sort((a, b) => b.approxMarks.compareTo(a.approxMarks));
    final maxMarks = sorted.first.approxMarks;

    return Column(
      children: sorted.take(6).map((s) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.subject, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(s.tip, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: s.approxMarks / maxMarks,
                        minHeight: 5,
                        backgroundColor: Colors.white10,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('~${s.approxMarks}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ============================================================
// 2. SYLLABUS / TASK SCREEN — now persisted
// ============================================================
class TaskScreen extends StatefulWidget {
  const TaskScreen({super.key});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  List<Map<String, dynamic>> _tasks = [];
  final _controller = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final t = await StorageService.loadTasks();
    setState(() {
      _tasks = t;
      _loaded = true;
    });
  }

  void _persist() => StorageService.saveTasks(_tasks);

  void _addTask() {
    if (_controller.text.isNotEmpty) {
      setState(() {
        _tasks.insert(0, {'title': _controller.text, 'done': false, 'subject': 'New'});
        _controller.clear();
      });
      _persist();
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _tasks.where((t) => t['done'] == true).length;
    final pct = _tasks.isEmpty ? 0.0 : done / _tasks.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Syllabus Tracker', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_loaded && _tasks.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: Colors.white10, color: const Color(0xFF10B981)),
              ),
              const SizedBox(height: 4),
              Text('${(pct * 100).toStringAsFixed(0)}% complete ($done/${_tasks.length})', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Add new task...',
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: _addTask,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                )
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _tasks.length,
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: task['done'] ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.5) : Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: task['done'] ? const Color(0xFF10B981).withValues(alpha: 0.3) : Colors.transparent),
                          ),
                          child: CheckboxListTile(
                            activeColor: const Color(0xFF10B981),
                            title: Text(
                              task['title'],
                              style: TextStyle(
                                decoration: task['done'] ? TextDecoration.lineThrough : null,
                                color: task['done'] ? Colors.grey : Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(task['subject'], style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                            value: task['done'],
                            onChanged: (val) {
                              setState(() => _tasks[index]['done'] = val);
                              _persist();
                              if (val == true) StorageService.recordActivity();
                            },
                            secondary: IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.red.shade400),
                              onPressed: () {
                                setState(() => _tasks.removeAt(index));
                                _persist();
                              },
                            ),
                          ),
                        );
                      },
                    ),
            )
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 3. MOCK TEST / CBT SIMULATOR
// Mimics the real GATE computer-based test interface: question
// palette (answered / not answered / marked for review), a
// countdown timer, and official-style negative marking. This is
// the single most requested feature by GATE aspirants because
// practicing under exam-like conditions matters more than just
// reading notes.
// ============================================================
class MCQuestion {
  final String subject;
  final String question;
  final List<String> options; // empty for NAT
  final int correctIndex; // -1 for NAT
  final String? natAnswer;
  final bool isNat;
  final double marks;
  final double negMarks;

  const MCQuestion({
    required this.subject,
    required this.question,
    this.options = const [],
    this.correctIndex = -1,
    this.natAnswer,
    this.isNat = false,
    this.marks = 1,
    this.negMarks = 0.33,
  });
}

final List<MCQuestion> kQuestionBank = [
  const MCQuestion(
    subject: 'Algorithms',
    question: 'What is the worst-case time complexity of QuickSort?',
    options: ['O(n log n)', 'O(n^2)', 'O(n)', 'O(log n)'],
    correctIndex: 1,
  ),
  const MCQuestion(
    subject: 'Algorithms',
    question: 'Which algorithm is used to find the shortest path in a graph with non-negative edge weights?',
    options: ['Bellman-Ford', 'Dijkstra', 'Kruskal', 'Prim'],
    correctIndex: 1,
  ),
  const MCQuestion(
    subject: 'Data Structures',
    question: 'A complete binary tree with n nodes has a height of approximately:',
    options: ['O(n)', 'O(log n)', 'O(n log n)', 'O(sqrt n)'],
    correctIndex: 1,
  ),
  const MCQuestion(
    subject: 'Operating Systems',
    question: 'Which scheduling algorithm can cause starvation?',
    options: ['Round Robin', 'FCFS', 'Priority Scheduling', 'SJF (non-preemptive) — no starvation guaranteed'],
    correctIndex: 2,
  ),
  const MCQuestion(
    subject: 'Operating Systems',
    question: 'A system is in a safe state if:',
    options: [
      'It can never enter a deadlock',
      'There exists at least one safe sequence to allocate resources to all processes',
      'All resources are currently free',
      'No process is waiting'
    ],
    correctIndex: 1,
  ),
  const MCQuestion(
    subject: 'DBMS',
    question: 'A relation is in 2NF if it is in 1NF and:',
    options: [
      'has no transitive dependency',
      'every non-prime attribute is fully functionally dependent on every candidate key',
      'has no multivalued dependency',
      'all attributes are atomic'
    ],
    correctIndex: 1,
  ),
  const MCQuestion(
    subject: 'Computer Networks',
    question: 'Which layer of the OSI model is responsible for routing?',
    options: ['Data Link', 'Network', 'Transport', 'Session'],
    correctIndex: 1,
  ),
  const MCQuestion(
    subject: 'Theory of Computation',
    question: 'Which of the following languages is NOT regular?',
    options: ['a*b*', '(ab)*', 'a^n b^n', 'strings with even number of a\'s'],
    correctIndex: 2,
  ),
  const MCQuestion(
    subject: 'COA',
    question: 'In a direct-mapped cache, a given main memory block can be placed:',
    options: ['Anywhere in cache', 'Only in one specific cache line', 'In any of a set of lines', 'Only in the first line'],
    correctIndex: 1,
  ),
  const MCQuestion(
    subject: 'Discrete Math',
    question: 'A simple graph with n vertices and more than n(n-1)/2 edges is:',
    options: ['Impossible', 'A tree', 'Bipartite', 'Disconnected'],
    correctIndex: 0,
  ),
  const MCQuestion(
    subject: 'Engineering Math',
    question: 'The rank of a 3x3 identity matrix is:',
    options: ['0', '1', '2', '3'],
    correctIndex: 3,
  ),
  const MCQuestion(
    subject: 'Algorithms',
    question: 'NAT: What is the time complexity exponent for Strassen\'s matrix multiplication? (n^__)',
    isNat: true,
    natAnswer: '2.81',
    marks: 2,
    negMarks: 0,
  ),
  const MCQuestion(
    subject: 'Data Structures',
    question: 'NAT: In a min-heap with 15 elements, what is the maximum possible height (0-indexed root)?',
    isNat: true,
    natAnswer: '3',
    marks: 1,
    negMarks: 0,
  ),
  const MCQuestion(
    subject: 'Digital Logic',
    question: 'The 2\'s complement of the 4-bit binary number 0110 is:',
    options: ['1001', '1010', '0110', '1111'],
    correctIndex: 1,
  ),
  const MCQuestion(
    subject: 'Compiler Design',
    question: 'Which phase of a compiler performs type checking?',
    options: ['Lexical Analysis', 'Syntax Analysis', 'Semantic Analysis', 'Code Generation'],
    correctIndex: 2,
  ),
];

class MockTestHomeScreen extends StatefulWidget {
  const MockTestHomeScreen({super.key});

  @override
  State<MockTestHomeScreen> createState() => _MockTestHomeScreenState();
}

class _MockTestHomeScreenState extends State<MockTestHomeScreen> {
  int _numQuestions = 10;
  int _durationMin = 20;
  List<Map<String, dynamic>> _pastResults = [];

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    final r = await StorageService.loadMockResults();
    setState(() => _pastResults = r);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Mock Test (CBT)', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          Text('Simulates the real GATE exam interface with negative marking', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Questions'),
                    DropdownButton<int>(
                      value: _numQuestions,
                      items: {5, 10, kQuestionBank.length}.map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                      onChanged: (v) => setState(() => _numQuestions = v!),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Duration (min)'),
                    DropdownButton<int>(
                      value: _durationMin,
                      items: [10, 20, 30, 60].map((e) => DropdownMenuItem(value: e, child: Text('$e'))).toList(),
                      onChanged: (v) => setState(() => _durationMin = v!),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final rng = Random();
                      final pool = [...kQuestionBank]..shuffle(rng);
                      final selected = pool.take(_numQuestions.clamp(1, kQuestionBank.length)).toList();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MockTestScreen(questions: selected, durationSeconds: _durationMin * 60),
                        ),
                      ).then((_) => _loadResults());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Test', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text('Past Attempts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_pastResults.isEmpty)
            Text('No attempts yet — start your first mock test above.', style: TextStyle(color: Colors.grey[500]))
          else
            ..._pastResults.map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events_outlined, color: Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Score: ${r['score']} / ${r['maxScore']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('${r['correct']} correct · ${r['wrong']} wrong · ${r['unattempted']} skipped', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(r['date'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

class MockTestScreen extends StatefulWidget {
  final List<MCQuestion> questions;
  final int durationSeconds;
  const MockTestScreen({super.key, required this.questions, required this.durationSeconds});

  @override
  State<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends State<MockTestScreen> {
  late int _secondsLeft;
  Timer? _timer;
  int _current = 0;
  late List<int?> _selectedMcq; // index chosen per question
  late List<TextEditingController> _natControllers;
  late List<bool> _markedForReview;
  late List<bool> _visited;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.durationSeconds;
    _selectedMcq = List.filled(widget.questions.length, null);
    _natControllers = List.generate(widget.questions.length, (_) => TextEditingController());
    _markedForReview = List.filled(widget.questions.length, false);
    _visited = List.filled(widget.questions.length, false);
    _visited[0] = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
        _submit();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _natControllers) {
      c.dispose();
    }
    super.dispose();
  }

  String get _timeStr {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _goTo(int index) {
    setState(() {
      _current = index;
      _visited[index] = true;
    });
  }

  Future<void> _submit() async {
    _timer?.cancel();
    int correct = 0, wrong = 0, unattempted = 0;
    double score = 0, maxScore = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      maxScore += q.marks;
      if (q.isNat) {
        final ans = _natControllers[i].text.trim();
        if (ans.isEmpty) {
          unattempted++;
        } else if (ans == q.natAnswer) {
          correct++;
          score += q.marks;
        } else {
          wrong++; // NAT: no negative marking per GATE convention
        }
      } else {
        final sel = _selectedMcq[i];
        if (sel == null) {
          unattempted++;
        } else if (sel == q.correctIndex) {
          correct++;
          score += q.marks;
        } else {
          wrong++;
          score -= q.negMarks;
        }
      }
    }
    if (score < 0) score = 0;

    final result = {
      'score': score.toStringAsFixed(2),
      'maxScore': maxScore.toStringAsFixed(2),
      'correct': correct,
      'wrong': wrong,
      'unattempted': unattempted,
      'date': '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
    };
    await StorageService.saveMockResult(result);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MockResultScreen(result: result)),
    );
  }

  Color _paletteColor(int i) {
    final q = widget.questions[i];
    final answered = q.isNat ? _natControllers[i].text.trim().isNotEmpty : _selectedMcq[i] != null;
    if (_markedForReview[i]) return Colors.amber;
    if (answered) return const Color(0xFF10B981);
    if (_visited[i]) return Colors.redAccent.withValues(alpha: 0.7);
    return Colors.white10;
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[_current];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text('Leave test?'),
            content: const Text('Your progress in this attempt will be lost.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
            ],
          ),
        );
        if (leave ?? false) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          title: Text('Q${_current + 1} / ${widget.questions.length}'),
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
              child: Row(children: [const Icon(Icons.timer, size: 16, color: Colors.redAccent), const SizedBox(width: 6), Text(_timeStr, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))]),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 8, children: [
                      Chip(label: Text(q.subject), backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.25)),
                      Chip(label: Text('+${q.marks} ${q.isNat ? "· no neg." : "/ -${q.negMarks}"}'), backgroundColor: Colors.white10),
                    ]),
                    const SizedBox(height: 16),
                    Text(q.question, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4)),
                    const SizedBox(height: 24),
                    if (q.isNat)
                      TextField(
                        controller: _natControllers[_current],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Enter numerical answer',
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      )
                    else
                      ...List.generate(q.options.length, (i) {
                        final selected = _selectedMcq[_current] == i;
                        return InkWell(
                          onTap: () => setState(() => _selectedMcq[_current] = i),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF8B5CF6).withValues(alpha: 0.25) : Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: selected ? const Color(0xFF8B5CF6) : Colors.white10, width: selected ? 2 : 1),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: selected ? const Color(0xFF8B5CF6) : Colors.white10,
                                  child: Text(String.fromCharCode(65 + i), style: const TextStyle(fontSize: 12, color: Colors.white)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(q.options[i])),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => setState(() => _markedForReview[_current] = !_markedForReview[_current]),
                      icon: Icon(_markedForReview[_current] ? Icons.bookmark : Icons.bookmark_border, color: Colors.amber),
                      label: Text(_markedForReview[_current] ? 'Marked for review' : 'Mark for review', style: const TextStyle(color: Colors.amber)),
                    ),
                  ],
                ),
              ),
            ),
            // Question palette
            Container(
              color: const Color(0xFF1E293B),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              child: SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.questions.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      onTap: () => _goTo(i),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: _paletteColor(i),
                        child: Text('${i + 1}', style: TextStyle(color: i == _current ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _current > 0 ? () => _goTo(_current - 1) : null,
                        child: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white),
                        onPressed: _current < widget.questions.length - 1
                            ? () => _goTo(_current + 1)
                            : () => _confirmSubmit(),
                        child: Text(_current < widget.questions.length - 1 ? 'Next' : 'Submit'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSubmit() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Submit test?'),
        content: Text('You have answered ${_selectedMcq.where((e) => e != null).length + _natControllers.where((c) => c.text.trim().isNotEmpty).length} of ${widget.questions.length} questions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Review again')),
          TextButton(onPressed: () { Navigator.pop(context); _submit(); }, child: const Text('Submit')),
        ],
      ),
    );
  }
}

class MockResultScreen extends StatelessWidget {
  final Map<String, dynamic> result;
  const MockResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: const Color(0xFF1E293B), title: const Text('Result')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)]),
                  shape: BoxShape.circle,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${result['score']}', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
                    Text('/ ${result['maxScore']}', style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ResultStat(label: 'Correct', value: '${result['correct']}', color: const Color(0xFF10B981)),
                  _ResultStat(label: 'Wrong', value: '${result['wrong']}', color: Colors.redAccent),
                  _ResultStat(label: 'Skipped', value: '${result['unattempted']}', color: Colors.grey),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                  child: const Text('Back to Dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ResultStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    );
  }
}

// ============================================================
// 4. FORMULA FLASHCARDS
// ============================================================
class FormulaScreen extends StatefulWidget {
  const FormulaScreen({super.key});

  @override
  State<FormulaScreen> createState() => _FormulaScreenState();
}

class _FormulaScreenState extends State<FormulaScreen> {
  final List<Map<String, String>> formulas = const [
    {'title': 'Eigenvalues', 'front': 'Sum of Eigenvalues = ?\nProduct of Eigenvalues = ?', 'back': 'Sum = Trace of Matrix\nProduct = Determinant'},
    {'title': 'Bayes Theorem', 'front': 'P(A|B) Formula', 'back': 'P(A|B) = [P(B|A) * P(A)] / P(B)'},
    {'title': 'Calculus', 'front': 'Integration by Parts', 'back': '∫u dv = uv - ∫v du'},
    {'title': 'Master Theorem', 'front': 'T(n) = aT(n/b) + f(n)\nWhen is case 1 used?', 'back': 'If f(n) = O(n^(log_b a - ε)) then T(n) = Θ(n^log_b a)'},
    {'title': 'Amdahl\'s Law', 'front': 'Speedup formula for parallel systems', 'back': 'Speedup = 1 / [(1-P) + P/S]'},
    {'title': 'B-Tree', 'front': 'Minimum degree t → min/max keys per node?', 'back': 'Min = t-1 keys, Max = 2t-1 keys'},
    {'title': 'TCP', 'front': '3-way handshake steps', 'back': 'SYN → SYN-ACK → ACK'},
  ];

  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = formulas.where((f) => f['title']!.toLowerCase().contains(_query.toLowerCase())).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Formula Vault', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const Text('Tap a card to flip and reveal the answer.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 14),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search formulas...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(height: 150, child: FlashcardWidget(data: filtered[index])),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class FlashcardWidget extends StatefulWidget {
  final Map<String, String> data;
  const FlashcardWidget({super.key, required this.data});

  @override
  State<FlashcardWidget> createState() => _FlashcardWidgetState();
}

class _FlashcardWidgetState extends State<FlashcardWidget> {
  bool isFlipped = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => isFlipped = !isFlipped),
      child: TweenAnimationBuilder(
        tween: Tween<double>(begin: 0, end: isFlipped ? 180 : 0),
        duration: const Duration(milliseconds: 500),
        builder: (context, value, child) {
          final isBack = value >= 90;
          final rotation = value * pi / 180;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(rotation),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isBack ? [const Color(0xFF10B981), const Color(0xFF059669)] : [const Color(0xFF334155), const Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(isBack ? pi : 0),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!isBack) Text(widget.data['title']!, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        const SizedBox(height: 12),
                        Text(
                          isBack ? widget.data['back']! : widget.data['front']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================
// 5. POMODORO / FOCUS HUB — now logs sessions for the streak
// ============================================================
class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  int workMinutes = 25;
  int breakMinutes = 5;

  late int secondsRemaining;
  bool isStudy = true;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    secondsRemaining = workMinutes * 60;
  }

  void _toggleTimer() {
    if (timer != null && timer!.isActive) {
      timer!.cancel();
      setState(() {});
    } else {
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (secondsRemaining > 0) {
          setState(() => secondsRemaining--);
        } else {
          t.cancel();
          if (isStudy) {
            StorageService.addPomodoroSession(workMinutes);
          }
          setState(() {
            isStudy = !isStudy;
            secondsRemaining = (isStudy ? workMinutes : breakMinutes) * 60;
          });
        }
      });
      setState(() {});
    }
  }

  void _resetTimer() {
    timer?.cancel();
    setState(() {
      secondsRemaining = (isStudy ? workMinutes : breakMinutes) * 60;
    });
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Timer Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Study Duration (min)', style: TextStyle(fontSize: 16)),
                    DropdownButton<int>(
                      value: workMinutes,
                      items: [15, 25, 45, 60].map((e) => DropdownMenuItem(value: e, child: Text('$e min'))).toList(),
                      onChanged: (val) {
                        setModalState(() => workMinutes = val!);
                        setState(() {
                          workMinutes = val!;
                          if (isStudy) _resetTimer();
                        });
                      },
                    )
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Break Duration (min)', style: TextStyle(fontSize: 16)),
                    DropdownButton<int>(
                      value: breakMinutes,
                      items: [5, 10, 15].map((e) => DropdownMenuItem(value: e, child: Text('$e min'))).toList(),
                      onChanged: (val) {
                        setModalState(() => breakMinutes = val!);
                        setState(() {
                          breakMinutes = val!;
                          if (!isStudy) _resetTimer();
                        });
                      },
                    )
                  ],
                )
              ],
            ),
          );
        });
      },
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = timer?.isActive ?? false;
    final totalSeconds = (isStudy ? workMinutes : breakMinutes) * 60;
    final progress = 1 - (secondsRemaining / totalSeconds);

    final mins = (secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final secs = (secondsRemaining % 60).toString().padLeft(2, '0');

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Focus Hub', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.settings, color: Colors.white70), onPressed: _openSettings),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 250,
                        height: 250,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: progress),
                          duration: const Duration(milliseconds: 500),
                          builder: (context, value, child) {
                            return CircularProgressIndicator(
                              value: value,
                              strokeWidth: 12,
                              backgroundColor: Theme.of(context).colorScheme.surface,
                              color: isStudy ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.secondary,
                              strokeCap: StrokeCap.round,
                            );
                          },
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            isStudy ? 'Deep Work' : 'Break Time',
                            style: TextStyle(color: isStudy ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 8),
                          Text('$mins:$secs', style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w900)),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 50),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _toggleTimer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRunning ? Colors.redAccent : const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: Text(isRunning ? 'PAUSE' : 'START', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      ),
                      const SizedBox(width: 20),
                      IconButton(
                        onPressed: _resetTimer,
                        icon: const Icon(Icons.refresh, size: 30),
                        style: IconButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surface, padding: const EdgeInsets.all(14)),
                      )
                    ],
                  ),
                  const SizedBox(height: 30),
                  TextButton.icon(
                    onPressed: () {
                      timer?.cancel();
                      setState(() {
                        isStudy = !isStudy;
                        secondsRemaining = (isStudy ? workMinutes : breakMinutes) * 60;
                      });
                    },
                    icon: const Icon(Icons.skip_next),
                    label: Text(isStudy ? 'Skip to Break' : 'Skip to Study', style: const TextStyle(fontSize: 16)),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// 6. GATE VIRTUAL CALCULATOR — replica of the on-screen scientific
// calculator used in the actual GATE CBT exam. Practicing with a
// look-alike interface (instead of a phone calculator) is one of
// the most useful "recent trend" prep habits for GATE aspirants.
// ============================================================
class GateCalculatorScreen extends StatefulWidget {
  const GateCalculatorScreen({super.key});

  @override
  State<GateCalculatorScreen> createState() => _GateCalculatorScreenState();
}

class _GateCalculatorScreenState extends State<GateCalculatorScreen> {
  String _display = '0';
  String _expression = '';
  bool _radMode = true;

  void _input(String value) {
    setState(() {
      if (_display == '0' || _display == 'Error') _display = '';
      _display += value;
      _expression += value;
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _expression = '';
    });
  }

  void _backspace() {
    setState(() {
      if (_display.isNotEmpty) {
        _display = _display.substring(0, _display.length - 1);
        if (_display.isEmpty) _display = '0';
      }
    });
  }

  void _applyFunction(String fn) {
    try {
      final val = double.parse(_display);
      double result;
      final rad = _radMode ? val : val * pi / 180;
      switch (fn) {
        case 'sin':
          result = sin(rad);
          break;
        case 'cos':
          result = cos(rad);
          break;
        case 'tan':
          result = tan(rad);
          break;
        case 'log':
          result = log(val) / ln10;
          break;
        case 'ln':
          result = log(val);
          break;
        case 'sqrt':
          result = sqrt(val);
          break;
        case 'sq':
          result = val * val;
          break;
        case '1/x':
          result = 1 / val;
          break;
        case 'exp':
          result = exp(val);
          break;
        default:
          result = val;
      }
      setState(() {
        _display = _trim(result);
        _expression = _display;
      });
    } catch (_) {
      setState(() => _display = 'Error');
    }
  }

  String _trim(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    if (v == v.roundToDouble() && v.abs() < 1e12) return v.toStringAsFixed(0);
    return v.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  void _evaluate() {
    try {
      final result = _evalExpression(_expression);
      setState(() {
        _display = _trim(result);
        _expression = _display;
      });
    } catch (_) {
      setState(() => _display = 'Error');
    }
  }

  // Minimal shunting-yard evaluator for + - * / ( ) and decimals —
  // enough for GATE-style arithmetic without external packages.
  double _evalExpression(String expr) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (int i = 0; i < expr.length; i++) {
      final c = expr[i];
      if ('+-*/()'.contains(c)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(c);
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());

    final output = <String>[];
    final ops = <String>[];
    int prec(String op) => (op == '+' || op == '-') ? 1 : 2;

    for (final t in tokens) {
      if (double.tryParse(t) != null) {
        output.add(t);
      } else if (t == '(') {
        ops.add(t);
      } else if (t == ')') {
        while (ops.isNotEmpty && ops.last != '(') {
          output.add(ops.removeLast());
        }
        if (ops.isNotEmpty) ops.removeLast();
      } else {
        while (ops.isNotEmpty && ops.last != '(' && prec(ops.last) >= prec(t)) {
          output.add(ops.removeLast());
        }
        ops.add(t);
      }
    }
    while (ops.isNotEmpty) {
      output.add(ops.removeLast());
    }

    final stack = <double>[];
    for (final t in output) {
      final n = double.tryParse(t);
      if (n != null) {
        stack.add(n);
      } else {
        final b = stack.removeLast();
        final a = stack.removeLast();
        switch (t) {
          case '+':
            stack.add(a + b);
            break;
          case '-':
            stack.add(a - b);
            break;
          case '*':
            stack.add(a * b);
            break;
          case '/':
            stack.add(a / b);
            break;
        }
      }
    }
    return stack.isEmpty ? 0 : stack.last;
  }

  Widget _btn(String label, {VoidCallback? onTap, Color? bg, Color? fg}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AspectRatio(
          aspectRatio: 1.3,
          child: Material(
            color: bg ?? const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Center(child: Text(label, style: TextStyle(fontSize: 16, color: fg ?? Colors.white, fontWeight: FontWeight.w600))),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Virtual Calculator'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _radMode = !_radMode),
            child: Text(_radMode ? 'RAD' : 'DEG', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              alignment: Alignment.centerRight,
              child: Text(_display, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),
            Row(children: [
              _btn('sin', onTap: () => _applyFunction('sin'), bg: const Color(0xFF334155)),
              _btn('cos', onTap: () => _applyFunction('cos'), bg: const Color(0xFF334155)),
              _btn('tan', onTap: () => _applyFunction('tan'), bg: const Color(0xFF334155)),
              _btn('log', onTap: () => _applyFunction('log'), bg: const Color(0xFF334155)),
            ]),
            Row(children: [
              _btn('ln', onTap: () => _applyFunction('ln'), bg: const Color(0xFF334155)),
              _btn('√', onTap: () => _applyFunction('sqrt'), bg: const Color(0xFF334155)),
              _btn('x²', onTap: () => _applyFunction('sq'), bg: const Color(0xFF334155)),
              _btn('1/x', onTap: () => _applyFunction('1/x'), bg: const Color(0xFF334155)),
            ]),
            Row(children: [
              _btn('C', onTap: _clear, bg: Colors.redAccent.withValues(alpha: 0.2), fg: Colors.redAccent),
              _btn('(', onTap: () => _input('(')),
              _btn(')', onTap: () => _input(')')),
              _btn('⌫', onTap: _backspace, bg: Colors.orangeAccent.withValues(alpha: 0.2), fg: Colors.orangeAccent),
            ]),
            Row(children: [
              _btn('7', onTap: () => _input('7')),
              _btn('8', onTap: () => _input('8')),
              _btn('9', onTap: () => _input('9')),
              _btn('÷', onTap: () => _input('/'), bg: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
            ]),
            Row(children: [
              _btn('4', onTap: () => _input('4')),
              _btn('5', onTap: () => _input('5')),
              _btn('6', onTap: () => _input('6')),
              _btn('×', onTap: () => _input('*'), bg: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
            ]),
            Row(children: [
              _btn('1', onTap: () => _input('1')),
              _btn('2', onTap: () => _input('2')),
              _btn('3', onTap: () => _input('3')),
              _btn('−', onTap: () => _input('-'), bg: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
            ]),
            Row(children: [
              _btn('0', onTap: () => _input('0')),
              _btn('.', onTap: () => _input('.')),
              _btn('=', onTap: _evaluate, bg: const Color(0xFF10B981)),
              _btn('+', onTap: () => _input('+'), bg: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
            ]),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}