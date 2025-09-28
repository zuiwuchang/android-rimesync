import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

Future<bool> _requestStoragePermission() async {
  var status = await Permission.manageExternalStorage.request();
  if (status.isGranted) {
    // status = await Permission.storage.request();
    // if (status.isGranted) {
    //   return true;
    // } else {
    //   return false;
    // }
    return true;
  } else {
    return false;
  }
}

Future<String> calculateFileHash(String filepath) async {
  final file = File(filepath);
  if (!await file.exists()) {
    return '';
  }
  final fileStream = file.openRead();
  final digest = await sha256.bind(fileStream).first;
  final hashString = digest.toString();
  return hashString;
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

  Future<void> _copyFile(String dst, String src) async {
    if ((await calculateFileHash(dst)) == (await calculateFileHash(src))) {
      setState(() {
        _progress = 'notchanged $dst';
        debugPrint(_progress);
      });
    } else {
      setState(() {
        _progress = 'copy $dst';
        debugPrint(_progress);
      });
      await File(src).copy(dst);
    }
  }

  Future<void> _copyFolder(String dst, String src, String name) async {
    src = path.join(src, name);
    dst = path.join(dst, name);
    setState(() {
      _progress = 'mkdir $dst';
      debugPrint(_progress);
    });
    await Directory(dst).create(recursive: true);
    final stream = Directory(src).list(recursive: true);
    await for (var entity in stream) {
      if (entity is File) {
        await _copyFile(
          path.join(dst, path.basename(entity.path)),
          entity.path,
        );
      } else if (entity is Directory) {
        await _copyFolder(dst, src, path.basename(entity.path));
      }
    }
  }

  /// 將 rime 詞庫推送到遠端
  Future<void> _push(String remote, String rime, String id) {
    debugPrint('push $rime');
    return _copyFolder(remote, rime, id);
  }

  /// 將遠端詞庫拉回到 rime 同步檔案夾
  Future<void> _pull(String remote, String rime, String id, bool skip) async {
    debugPrint('pull $remote');
    var directory = Directory(remote);
    //  var stream = directory.list(recursive: true);
    // await for (var entity in stream) {
    //   debugPrint(entity.path);
    // }
    var stream = directory.list(recursive: false);
    await for (var entity in stream) {
      if (entity is Directory) {
        final name = path.basename(entity.path);
        if (!skip || name != id) {
          await _copyFolder(rime, remote, name);
        }
      }
    }
    return _copyFolder(remote, rime, id);
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
      final isGranted = await _requestStoragePermission();
      if (!isGranted) {
        throw Exception('request storage permission failed');
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
            id,
            false, // 第一次運行時拉取所有數據，通常用於新安裝app後恢復詞庫
          );
          break;
        default:
          mode = 'sync';
          await _push(remote, rime, id);
          await _pull(
            remote,
            rime,
            id,
            true, // 正常同步時不要拉取自己創建的詞庫檔案
          );
          break;
      }
      setState(() {
        _disabled = false;
        _progress = '$mode success';
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
      String? path = await FilePicker.platform.getDirectoryPath();
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
