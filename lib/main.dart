import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:system_tray/system_tray.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Инициализация window_manager для управления окном
  await windowManager.ensureInitialized();

  // Настройка окна
  WindowOptions windowOptions = const WindowOptions(
    size: Size(600, 700),
    minimumSize: Size(400, 500),
    center: true,
    title: 'PhpStorm Watcher',
    skipTaskbar: false,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const PhpStormWatcherApp());
}

class PhpStormWatcherApp extends StatelessWidget {
  const PhpStormWatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PhpStorm Watcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      darkTheme: ThemeData.dark(),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WindowListener {
  final _watcher = PhpStormWatcher();
  Timer? _updateTimer;
  List<ProjectActivity> _activities = [];
  bool _isMonitoring = false;
  String _status = 'Остановлено';
  Color _statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWatcher();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _watcher.stop();
    windowManager.removeListener(this);
    super.dispose();
  }

  void _initWatcher() async {
    await _watcher.init(() {
      if (mounted) {
        setState(() {});
      }
    });

    setState(() {
      _isMonitoring = _watcher.isMonitoring;
      _status = _watcher.isMonitoring ? 'Мониторинг активен' : 'Остановлено';
      _statusColor = _watcher.isMonitoring ? Colors.green : Colors.grey;
    });
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        setState(() {
          _activities = _watcher.recentActivities;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PhpStorm Watcher'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _selectFolder,
          ),
        ],
      ),
      body: Column(
        children: [
          // Статус панель
          _buildStatusPanel(),

          // Статистика
          _buildStatsPanel(),

          // Список активностей
          Expanded(child: _buildActivityList()),

          // Панель управления
          _buildControlPanel(),
        ],
      ),
    );
  }

  Widget _buildStatusPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[900],
      child: Row(
        children: [
          Icon(
            _isMonitoring ? Icons.check_circle : Icons.pause_circle,
            color: _statusColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _watcher.watchPath.isNotEmpty
                      ? _watcher.watchPath
                      : 'Папка не выбрана',
                  style: TextStyle(color: Colors.grey[300], fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _buildStatusBadge(),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isMonitoring ? Colors.green[900] : Colors.grey[800],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _isMonitoring ? 'АКТИВЕН' : 'ПАУЗА',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatsPanel() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard(
            'Сегодня',
            _watcher.todayCount.toString(),
            Icons.today,
            Colors.blue,
          ),
          _buildStatCard(
            'Всего',
            _watcher.totalCount.toString(),
            Icons.stacked_line_chart,
            Colors.green,
          ),
          _buildStatCard(
            'Проектов',
            _watcher.trackedProjects.toString(),
            Icons.folder,
            Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityList() {
    if (_activities.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Активности не найдены', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _activities.length,
      itemBuilder: (context, index) {
        final activity = _activities[index];
        return _buildActivityItem(activity);
      },
    );
  }

  Widget _buildActivityItem(ProjectActivity activity) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.folder, color: Colors.blue),
        ),
        title: Text(
          activity.projectName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _formatTime(activity.timestamp),
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: Text(
          _formatDate(activity.timestamp),
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        onTap: () => _showActivityDetails(activity),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            icon: Icon(_isMonitoring ? Icons.pause : Icons.play_arrow),
            label: Text(_isMonitoring ? 'Пауза' : 'Старт'),
            onPressed: _toggleMonitoring,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isMonitoring ? Colors.orange : Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Обновить'),
            onPressed: _refreshData,
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.receipt_long_sharp),
            label: const Text('Логи'),
            onPressed: _showLogs,
          ),
        ],
      ),
    );
  }

  void _toggleMonitoring() {
    setState(() {
      _isMonitoring = !_isMonitoring;
      if (_isMonitoring) {
        _watcher.start();
        _status = 'Мониторинг активен';
        _statusColor = Colors.green;
      } else {
        _watcher.stop();
        _status = 'Остановлено';
        _statusColor = Colors.grey;
      }
    });
  }

  void _selectFolder() async {
    final result = await _watcher.chooseWatchPath();
    if (result && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Папка выбрана: ${_watcher.watchPath}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _refreshData() {
    _watcher.refreshData();
    setState(() {
      _activities = _watcher.recentActivities;
    });
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Настройки'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Автозапуск'),
                subtitle: const Text('Запускать при старте системы'),
                value: _watcher.autoStart,
                onChanged: (value) {
                  _watcher.autoStart = value;
                  setState(() {});
                },
              ),
              SwitchListTile(
                title: const Text('Уведомления'),
                subtitle: const Text('Показывать системные уведомления'),
                value: _watcher.showNotifications,
                onChanged: (value) {
                  _watcher.showNotifications = value;
                  setState(() {});
                },
              ),
              ListTile(
                title: const Text('Интервал сканирования'),
                subtitle: Text('${_watcher.scanInterval} секунд'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () {
                        if (_watcher.scanInterval > 1) {
                          _watcher.scanInterval--;
                          setState(() {});
                        }
                      },
                    ),
                    Text(_watcher.scanInterval.toString()),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        _watcher.scanInterval++;
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _showLogs() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => LogsScreen(watcher: _watcher)),
    );
  }

  void _showActivityDetails(ProjectActivity activity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Детали активности'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Проект: ${activity.projectName}'),
            const SizedBox(height: 8),
            Text('Время: ${_formatDateTime(activity.timestamp)}'),
            const SizedBox(height: 8),
            Text('Путь: ${activity.projectPath}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime time) {
    return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime time) {
    return '${_formatDate(time)} ${_formatTime(time)}';
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Подтверждение выхода'),
          content: const Text(
            'Вы действительно хотите выйти? Программа продолжит работу в трее.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                windowManager.destroy();
              },
              child: const Text('Выйти'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                windowManager.hide();
              },
              child: const Text('Свернуть в трей'),
            ),
          ],
        ),
      );
    }
  }
}

class LogsScreen extends StatelessWidget {
  final PhpStormWatcher watcher;

  const LogsScreen({super.key, required this.watcher});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Логи')),
      body: FutureBuilder<List<LogEntry>>(
        future: watcher.getLogEntries(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError ||
              !snapshot.hasData ||
              snapshot.data!.isEmpty) {
            return const Center(child: Text('Логи не найдены'));
          }

          final logs = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            log.date,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text('${log.activities.length} проектов'),
                            backgroundColor: Colors.blue[100],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...log.activities.map(
                        (activity) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• $activity'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// Модели данных
class ProjectActivity {
  final String projectName;
  final String projectPath;
  final DateTime timestamp;

  ProjectActivity({
    required this.projectName,
    required this.projectPath,
    required this.timestamp,
  });
}

class LogEntry {
  final String date;
  final List<String> activities;

  LogEntry({required this.date, required this.activities});
}

// Основной класс мониторинга
class PhpStormWatcher {
  static const String appName = "PhpStormWatcher";
  static const String configFileName = "config.json";

  String watchPath = '';
  final Set<String> seenFolders = {};
  final Map<String, double> atimeTracker = {};
  final List<ProjectActivity> recentActivities = [];
  Timer? scanTimer;

  // Настройки
  bool autoStart = false;
  bool showNotifications = true;
  int scanInterval = 3;
  bool isMonitoring = false;

  // Callback для обновления UI
  VoidCallback? onUpdate;

  // Конфиг файл
  File get configFile => File(p.join(Directory.current.path, configFileName));

  Future<void> init(VoidCallback? updateCallback) async {
    onUpdate = updateCallback;

    // Загрузка конфига
    await _loadConfig();

    // Инициализация уведомлений
    await localNotifier.setup(
      appName: appName,
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );

    if (watchPath.isNotEmpty && Directory(watchPath).existsSync()) {
      initTracker();
      start();
    }
  }

  Future<void> _loadConfig() async {
    if (await configFile.exists()) {
      try {
        final content = await configFile.readAsString();
        final config = jsonDecode(content) as Map<String, dynamic>;
        watchPath = config['watch_path']?.toString() ?? '';
        autoStart = config['auto_start'] ?? false;
        showNotifications = config['show_notifications'] ?? true;
        scanInterval = config['scan_interval'] ?? 3;
      } catch (e) {
        print("Ошибка чтения конфига: $e");
      }
    }
  }

  Future<void> _saveConfig() async {
    final config = {
      'watch_path': watchPath,
      'auto_start': autoStart,
      'show_notifications': showNotifications,
      'scan_interval': scanInterval,
    };

    await configFile.writeAsString(jsonEncode(config), encoding: utf8);
  }

  // Future<bool> chooseWatchPath() async {
  //   try {
  //     final selectedPath = await FilePicker.platform.getDirectoryPath(
  //       dialogTitle: 'Выберите папку с проектами PhpStorm',
  //     );

  //     if (selectedPath != null && selectedPath.isNotEmpty) {
  //       watchPath = selectedPath;
  //       await _saveConfig();
  //       initTracker();
  //       start();

  //       if (onUpdate != null) onUpdate!();
  //       return true;
  //     }
  //   } catch (e) {
  //     print("Ошибка выбора папки: $e");
  //   }

  //   return false;
  // }

  Future<bool> chooseWatchPath() async {
    try {
      // Для macOS используем нативный диалог через file_selector
      String? selectedPath;

      if (Platform.isMacOS) {
        // Альтернативный способ для macOS
        selectedPath = await _showMacOSFolderDialog();
      } else {
        selectedPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Выберите папку с проектами PhpStorm',
        );
      }

      if (selectedPath != null && selectedPath.isNotEmpty) {
        watchPath = selectedPath;
        await _saveConfig();
        initTracker();
        start();

        if (onUpdate != null) onUpdate!();
        return true;
      }
    } catch (e) {
      print("Ошибка выбора папки: $e");
      // Показываем fallback диалог
      return await _showFallbackDialog();
    }

    return false;
  }

  Future<String?> _showMacOSFolderDialog() async {
    // Используем Process для вызова нативного диалога macOS
    try {
      final result = await Process.run('osascript', [
        '-e',
        'POSIX path of (choose folder with prompt "Выберите папку с проектами PhpStorm")',
      ]);

      if (result.exitCode == 0) {
        return result.stdout.toString().trim();
      }
    } catch (e) {
      print("Ошибка macOS диалога: $e");
    }
    return null;
  }

  Future<bool> _showFallbackDialog() async {
    // Fallback: ввод пути вручную
    final completer = Completer<bool>();

    // Здесь нужно будет показать диалог для ручного ввода пути
    // Для примера, возвращаем false
    return false;
  }

  void initTracker() {
    final dir = Directory(watchPath);
    if (!dir.existsSync()) return;

    atimeTracker.clear();
    final dirs = dir.listSync();

    for (final entity in dirs) {
      if (entity is Directory) {
        final ideaFile = File(p.join(entity.path, ".idea", "workspace.xml"));
        if (ideaFile.existsSync()) {
          try {
            final stat = ideaFile.statSync();
            atimeTracker[entity.path] =
                stat.accessed.millisecondsSinceEpoch / 1000;
          } catch (e) {
            print("Ошибка инициализации трекера: $e");
          }
        }
      }
    }
  }

  void start() {
    if (scanTimer != null) scanTimer!.cancel();

    scanTimer = Timer.periodic(Duration(seconds: scanInterval), (timer) {
      _scanFolders();
    });

    isMonitoring = true;
    if (onUpdate != null) onUpdate!();
  }

  void stop() {
    scanTimer?.cancel();
    scanTimer = null;
    isMonitoring = false;
    if (onUpdate != null) onUpdate!();
  }

  void _scanFolders() {
    if (watchPath.isEmpty) return;

    final dir = Directory(watchPath);
    if (!dir.existsSync()) return;

    final dirs = dir.listSync();
    for (final entity in dirs) {
      if (entity is Directory) {
        final ideaFile = File(p.join(entity.path, ".idea", "workspace.xml"));
        if (ideaFile.existsSync()) {
          try {
            final stat = ideaFile.statSync();
            final atime = stat.accessed.millisecondsSinceEpoch / 1000;
            final lastKnown = atimeTracker[entity.path];

            if (lastKnown != null && atime != lastKnown) {
              if (!seenFolders.contains(entity.path)) {
                _handleProjectOpen(entity.path);
                seenFolders.add(entity.path);
              }
            }

            atimeTracker[entity.path] = atime;
          } catch (e) {
            print("Ошибка сканирования: $e");
          }
        }
      }
    }
  }

  Future<void> _handleProjectOpen(String projectPath) async {
    final projectName = p.basename(projectPath);
    final now = DateTime.now();

    // Добавляем в активность
    final activity = ProjectActivity(
      projectName: projectName,
      projectPath: projectPath,
      timestamp: now,
    );

    recentActivities.insert(0, activity);
    if (recentActivities.length > 50) {
      recentActivities.removeLast();
    }

    // Записываем в лог
    await _writeToLog(projectName, now);

    // Показываем уведомление
    if (showNotifications) {
      final notification = LocalNotification(
        title: 'PhpStorm открыт',
        body: projectName,
      );
      await notification.show();
    }

    if (onUpdate != null) onUpdate!();
  }

  Future<void> _writeToLog(String projectName, DateTime timestamp) async {
    final today =
        "${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}";
    final logDir = Directory(p.join(Directory.current.path, "logs"));
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }

    final logFile = File(p.join(logDir.path, "${today}_log.txt"));
    final prefix = timestamp.weekday == 5
        ? "Делал в пятницу\n"
        : "Делал вчера\n";

    if (!await logFile.exists()) {
      await logFile.writeAsString(prefix, encoding: utf8);
    }

    final content = await logFile.readAsString(encoding: utf8);
    if (!content.contains(projectName)) {
      await logFile.writeAsString(
        "— $projectName\n",
        mode: FileMode.append,
        encoding: utf8,
      );
    }
  }

  // Геттеры для статистики
  int get todayCount {
    final today = DateTime.now();
    return recentActivities
        .where(
          (a) =>
              a.timestamp.year == today.year &&
              a.timestamp.month == today.month &&
              a.timestamp.day == today.day,
        )
        .length;
  }

  int get totalCount => recentActivities.length;

  int get trackedProjects => atimeTracker.length;

  Future<List<LogEntry>> getLogEntries() async {
    final logDir = Directory(p.join(Directory.current.path, "logs"));
    if (!logDir.existsSync()) return [];

    final logFiles = logDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_log.txt'))
        .toList();

    logFiles.sort((a, b) => b.path.compareTo(a.path));

    final List<LogEntry> entries = [];

    for (final file in logFiles.take(30)) {
      try {
        final content = await file.readAsString(encoding: utf8);
        final lines = content
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();

        if (lines.isNotEmpty) {
          final date = p.basename(file.path).replaceAll('_log.txt', '');
          final activities = lines
              .where((line) => line.startsWith('— '))
              .map((line) => line.substring(2))
              .toList();

          if (activities.isNotEmpty) {
            entries.add(LogEntry(date: date, activities: activities));
          }
        }
      } catch (e) {
        print("Ошибка чтения лога: $e");
      }
    }

    return entries;
  }

  void refreshData() {
    initTracker();
    if (onUpdate != null) onUpdate!();
  }
}
