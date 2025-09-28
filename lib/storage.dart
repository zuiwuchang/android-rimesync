import 'package:flutter/services.dart';

class StorageAccess {
  static const MethodChannel _platform = MethodChannel(
    'com.king011.android.rimesync/storage_access',
  );

  /// 使用 SAF 選取一個目錄，返回 uri
  static Future<String?> pickFolder() async {
    final String? folder = await _platform.invokeMethod('pickFolder');
    return folder;
  }

  /// 列舉目錄下的直接子目錄
  static Future<List<String>> listDir(
    String rootUri, {
    List<String>? path,
  }) async {
    final names = await _platform.invokeMethod('listDir', {
      'rootUri': rootUri,
      "path": path,
    });
    return names.cast<String>() ?? [];
  }

  /// 列舉目錄下的直接子檔案
  static Future<List<String>> listFile(
    String rootUri, {
    List<String>? path,
  }) async {
    final names = await _platform.invokeMethod('listFile', {
      'rootUri': rootUri,
      "path": path,
    });
    return names.cast<String>() ?? [];
  }

  /// 在 rootUri 下創建子目錄
  static Future<String> mkdir(String rootUri, {List<String>? path}) async {
    final String? uri = await _platform.invokeMethod('mkdir', {
      "rootUri": rootUri,
      "path": path,
    });
    return uri!;
  }

  /// 讀取一個檔案, 如果檔案不存在返回 null
  static Future<Uint8List?> readFile(String rootUri, {List<String>? path}) {
    return _platform.invokeMethod('readFile', {
      "rootUri": rootUri,
      "path": path,
    });
  }

  /// 寫入一個檔案, 如果檔案已經存在則覆蓋
  static Future<void> writeFile(
    String rootUri, {
    List<String>? path,
    Uint8List? data,
  }) {
    return _platform.invokeMethod('writeFile', {
      "rootUri": rootUri,
      "path": path,
      "data": data,
    });
  }
}
