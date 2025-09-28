import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './storage.dart';

void main() {
  runApp(const MyApp());
}

class Statistical {
  int dir = 0;
  int copy = 0;
  int notchanged = 0;
  reset() {
    dir = 0;
    copy = 0;
    notchanged = 0;
  }

  @override
  String toString() {
    final strs = <String>[];
    switch (dir) {
      case 0:
        break;
      case 1:
        strs.add('1 dir');
        break;
      default:
        strs.add('$dir dirs');
        break;
    }
    switch (copy) {
      case 0:
        break;
      case 1:
        strs.add('1 file copied');
        break;
      default:
        strs.add('$copy files copied');
        break;
    }
    switch (notchanged) {
      case 0:
        break;
      case 1:
        strs.add('1 file not changed');
        break;
      default:
        strs.add('$notchanged files not changed');
        break;
    }
    switch (strs.length) {
      case 0:
        return '';
      case 1:
        return '${strs[0]}.';
      default:
        return '${strs.join(", ")}.';
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rime sync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Rime sync'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

Future<String> getString(String key) async {
  try {
    final SharedPreferences db = await SharedPreferences.getInstance();
    final val = db.getString(key) ?? '';
    debugPrint('getString("$key")="$val"');
    return val;
  } catch (e) {
    debugPrint('getString("$key") failed: $e');
  }
  return '';
}

Future<bool> setString(String key, String val) async {
  try {
    final SharedPreferences db = await SharedPreferences.getInstance();
    if (val == '') {
      return db.remove(key);
    }
    debugPrint('setString("$key")="$val"');
    return db.setString(key, val);
  } catch (e) {
    debugPrint('setString("$key") failed: $e');
    return false;
  }
}

class _MyHomePageState extends State<MyHomePage> {
  final _id = TextEditingController();
  final _rime = TextEditingController();
  final _remote = TextEditingController();
  String? _mode = 'sync';
  String? _progress;
  bool _disabled = true;
  get isDisabled => _disabled;
  String? _error;
  final _statistical = Statistical();
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    String mode = 'sync';
    try {
      mode = await getString('mode');
      _id.text = await getString('id');
      _rime.text = await getString('rime');
      _remote.text = await getString('remote');
    } finally {
      setState(() {
        switch (mode) {
          case 'pull':
          case 'push':
            _mode = mode;
            break;
          default:
            _mode = 'sync';
            break;
        }

        _disabled = false;
      });
    }
  }

  Future<void> _copyFile(String dst, String src, List<String> path) async {
    setState(() {
      _progress = 'read $path';
      debugPrint(_progress);
    });
    final data = await StorageAccess.readFile(src, path: path);
    final old = await StorageAccess.readFile(dst, path: path);
    if (listEquals(data, old)) {
      setState(() {
        _statistical.notchanged++;
        _progress = 'notchanged $path';
        debugPrint(_progress);
      });
    } else {
      setState(() {
        _statistical.copy++;
        _progress = 'copy $path';
        debugPrint(_progress);
      });
      await StorageAccess.writeFile(dst, path: path, data: data);
    }
  }

  Future<void> _copyFolder(String dst, String src, List<String> path) async {
    setState(() {
      _statistical.dir++;
      _progress = 'mkdir $path';
      debugPrint(_progress);
    });
    await StorageAccess.mkdir(dst, path: path);
    var names = await StorageAccess.listFile(src, path: path);
    for (var name in names) {
      await _copyFile(dst, src, List.from(path)..add(name));
    }
    names = await StorageAccess.listDir(src, path: path);
    for (var name in names) {
      await _copyFolder(dst, src, List.from(path)..add(name));
    }
  }

  /// 將 rime 詞庫推送到遠端
  Future<void> _push(String remote, String rime, String id) {
    debugPrint('push $rime');
    _statistical.reset();
    return _copyFolder(remote, rime, [id]);
  }

  /// 將遠端詞庫拉回到 rime 同步檔案夾
  Future<void> _pull(String remote, String rime, String? skip) async {
    debugPrint('pull $remote');
    _statistical.reset();
    final names = await StorageAccess.listDir(remote);
    for (var name in names) {
      if (skip == name) {
        continue;
      }
      await _copyFolder(remote, rime, [name]);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _disabled = true;
      _progress = null;
      _error = null;
    });
    try {
      final id = _id.text.trim();
      if (id == '') {
        throw Exception('id empty');
      }
      await setString('id', id);
      final rime = _rime.text;
      if (rime == '') {
        throw Exception('rime empty');
      }
      final remote = _remote.text;
      if (remote == '') {
        throw Exception('remote empty');
      }
      String mode;
      switch (_mode) {
        case 'push':
          mode = 'push';
          await _push(remote, rime, id);
          break;
        case 'pull':
          mode = 'pull';
          await _pull(
            remote,
            rime,
            null, // 第一次運行時拉取所有數據，通常用於新安裝app後恢復詞庫
          );
          break;
        default:
          mode = 'sync';
          await _push(remote, rime, id);
          await _pull(
            remote,
            rime,
            id, // 正常同步時不要拉取自己創建的詞庫檔案
          );
          break;
      }
      setState(() {
        _disabled = false;
        _progress = '$mode success, $_statistical';
        debugPrint(_progress);
      });
    } catch (e) {
      debugPrint('sync failed: $e');
      setState(() {
        _disabled = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickFolder(bool rime) async {
    if (_disabled) {
      return;
    }
    setState(() {
      _disabled = true;
      _error = null;
    });
    try {
      String? path = await StorageAccess.pickFolder();
      if (path != null) {
        if (rime) {
          _rime.text = path;
          await setString('rime', path);
          debugPrint('pick rime: $path');
        } else {
          _remote.text = path;
          await setString('remote', path);
          debugPrint('pick remote: $path');
        }
      }
      setState(() => _disabled = false);
    } catch (e) {
      setState(() {
        _disabled = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Container(
        padding: EdgeInsets.all(8),
        child: ListView(
          children: [
            TextField(
              readOnly: isDisabled,
              decoration: InputDecoration(label: Text("Rime id")),
              controller: _id,
            ),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                label: Text("Rime sync folder"),
                suffixIcon: IconButton(
                  tooltip: "pick folder",
                  onPressed: isDisabled ? null : () => _pickFolder(true),
                  icon: const Icon(Icons.folder_open),
                ),
              ),
              controller: _rime,
            ),
            TextField(
              readOnly: true,
              decoration: InputDecoration(
                label: Text("Remote sync folder"),
                suffixIcon: IconButton(
                  tooltip: "pick folder",
                  onPressed: isDisabled ? null : () => _pickFolder(false),
                  icon: const Icon(Icons.folder_open),
                ),
              ),
              controller: _remote,
            ),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Select Mode'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _mode,
                  icon: const Icon(Icons.arrow_drop_down),

                  iconSize: 24,
                  elevation: 16,
                  style: const TextStyle(
                    color: Colors.deepPurple,
                    fontSize: 16,
                  ),
                  underline: Container(
                    height: 2,
                    color: Colors.deepPurpleAccent,
                  ),

                  onChanged: isDisabled
                      ? null
                      : (String? newValue) async {
                          try {
                            setState(() {
                              _disabled = true;
                            });
                            final mode = newValue ?? 'sync';
                            await setString('mode', mode);
                            setState(() {
                              _disabled = false;
                              _mode = mode;
                            });
                          } catch (e) {
                            setState(() {
                              _disabled = false;
                              _error = '$e';
                            });
                          }
                        },
                  items: [
                    DropdownMenuItem<String>(
                      value: 'sync',
                      child: Text('sync'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'push',
                      child: Text('copy rime to remote'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'pull',
                      child: Text('copy remote to rime'),
                    ),
                  ],
                ),
              ),
            ),
            _progress == null ? Container() : Text('$_progress'),
            _error == null
                ? Container()
                : Text(
                    '$_error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: isDisabled ? null : _sync,
        tooltip: 'Sync',
        child: isDisabled
            ? MyRotation(child: const Icon(Icons.sync))
            : const Icon(Icons.sync),
      ),
    );
  }
}

class MyRotation extends StatefulWidget {
  const MyRotation({super.key, required this.child});
  final Widget child;
  @override
  State<MyRotation> createState() => _MyRotationState();
}

class _MyRotationState extends State<MyRotation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(turns: _controller, child: widget.child);
  }
}
