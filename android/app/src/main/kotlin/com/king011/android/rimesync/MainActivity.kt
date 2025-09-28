package com.king011.android.rimesync

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.InputStream
import java.io.OutputStream
import java.lang.Exception

class MainActivity: FlutterActivity() {
    
    // 必須與 Dart 程式碼中的 'com.king011.android.rimesync/storage_access' 一致
    private val CHANNEL = "com.king011.android.rimesync/storage_access"
    
    private val PICK_FOLDER_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null
    private val ioScope = CoroutineScope(Dispatchers.IO)

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            
            if (call.method == "pickFolder") {
                this.pendingResult = result
            }

            when (call.method) {
                "pickFolder" -> {
                    pickFolder()
                }
                "listDir" -> {
                    val rootUri = call.argument<String>("rootUri")
                    val pathList = call.argument<List<String>?>("path")
                    if (rootUri != null) {
                        listDirectory(rootUri, pathList, isFile = false, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "rootUri cannot be null.", null)
                    }
                }
                "listFile" -> {
                    val rootUri = call.argument<String>("rootUri")
                    val pathList = call.argument<List<String>?>("path")
                    if (rootUri != null) {
                        listDirectory(rootUri, pathList, isFile = true, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "rootUri cannot be null.", null)
                    }
                }
                "mkdir" -> {
                    val rootUri = call.argument<String>("rootUri")
                    val pathList = call.argument<List<String>?>("path") 

                    if (rootUri != null) {
                        mkdirImplementation(rootUri, pathList, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "rootUri cannot be null.", null)
                    }
                }
                "readFile" -> { // 注意：對應 Dart 端的 readFile
                    val rootUri = call.argument<String>("rootUri")
                    val pathList = call.argument<List<String>?>("path")

                    if (rootUri != null) {
                        readFileImplementation(rootUri, pathList, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "rootUri cannot be null.", null)
                    }
                }
                "writeFile" -> { // 🚨 新增 writeFile 處理邏輯
                    val rootUri = call.argument<String>("rootUri")
                    val pathList = call.argument<List<String>?>("path")
                    val data = call.argument<ByteArray>("data")

                    if (rootUri == null || data == null) {
                        result.error("INVALID_ARGUMENT", "rootUri and data cannot be null.", null)
                    } else {
                        writeFileImplementation(rootUri, pathList, data, result)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    // ----------------------------------------------------------------------
    // --- 1. 選取目錄 (pickFolder) 與 2. 接收 URI (onActivityResult) ---

    private fun pickFolder() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        startActivityForResult(intent, PICK_FOLDER_REQUEST_CODE)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == PICK_FOLDER_REQUEST_CODE) {
            if (pendingResult != null && resultCode == Activity.RESULT_OK) {
                val treeUri: Uri? = data?.data
                if (treeUri != null) {
                    val takeFlags: Int = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                    }
                    
                    pendingResult?.success(treeUri.toString())
                } else {
                    pendingResult?.error("PICK_FAILED", "Selected folder URI is null.", null)
                }
            } else if (pendingResult != null && resultCode == Activity.RESULT_CANCELED) {
                pendingResult?.success(null)
            } else if (pendingResult != null) {
                 pendingResult?.error("UNKNOWN_ERROR", "Unknown result code: $resultCode", null)
            }
            pendingResult = null
        }
    }
    
    // ----------------------------------------------------------------------
    // --- 3. 列出目錄內容 (listDir/listFile) ---

    private fun listDirectory(rootUri: String, path: List<String>?, isFile: Boolean, result: MethodChannel.Result) {
        val treeUri = Uri.parse(rootUri)

        ioScope.launch {
            try {
                val targetDir = navigateToDirectory(treeUri, path)
                
                if (targetDir == null || !targetDir.isDirectory) {
                    withContext(Dispatchers.Main) {
                        result.error("NOT_FOUND", "Target directory not found or is not a directory.", null)
                    }
                    return@launch
                }

                val nameList = targetDir.listFiles()
                    .filter { doc -> 
                        if (!isFile) doc.isDirectory 
                        else !doc.isDirectory 
                    }
                    .mapNotNull { it.name }
                    .toList()

                withContext(Dispatchers.Main) {
                    result.success(nameList) 
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("LIST_FAILED", "Failed to list directory: ${e.message}", e.toString())
                }
            }
        }
    }

    // --- 4. 創建目錄 (mkdir) ---
    
    private fun mkdirImplementation(rootUri: String, path: List<String>?, result: MethodChannel.Result) {
        val treeUri = Uri.parse(rootUri)

        ioScope.launch {
            try {
                var currentDir: DocumentFile? = DocumentFile.fromTreeUri(applicationContext, treeUri)
                
                if (currentDir == null || !currentDir.isDirectory) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_ROOT_URI", "The provided root URI is not a valid directory.", null)
                    }
                    return@launch
                }
                
                if (path.isNullOrEmpty()) {
                    withContext(Dispatchers.Main) {
                        result.success(rootUri)
                    }
                    return@launch
                }

                for (dirName in path) {
                    var nextDir = currentDir?.findFile(dirName)

                    if (nextDir == null || !nextDir.isDirectory) {
                        nextDir = currentDir?.createDirectory(dirName)
                    }
                    
                    if (nextDir == null) {
                        withContext(Dispatchers.Main) {
                            result.error("MKDIR_FAILED", "Failed to create directory: $dirName", null)
                        }
                        return@launch
                    }
                    
                    currentDir = nextDir
                }

                withContext(Dispatchers.Main) {
                    result.success(currentDir?.uri.toString()) 
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("MKDIR_EXCEPTION", "Error during directory creation: ${e.message}", e.toString())
                }
            }
        }
    }

    // --- 5. 讀取檔案 (readFile) ---

    private fun readFileImplementation(rootUri: String, path: List<String>?, result: MethodChannel.Result) {
        val treeUri = Uri.parse(rootUri)

        ioScope.launch {
            try {
                val targetFile = navigateToDirectory(treeUri, path, isFile = true)
                
                if (targetFile == null || !targetFile.isFile) {
                    withContext(Dispatchers.Main) {
                        result.success(null) 
                    }
                    return@launch
                }

                var inputStream: InputStream? = null
                try {
                    inputStream = applicationContext.contentResolver.openInputStream(targetFile.uri)
                    val bytes = inputStream?.readBytes()

                    withContext(Dispatchers.Main) {
                        result.success(bytes) 
                    }
                } finally {
                    inputStream?.close()
                }

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("READ_FAILED", "Failed to read file: ${e.message}", e.toString())
                }
            }
        }
    }

    // --- 6. 寫入檔案 (writeFile) ---

    private fun writeFileImplementation(rootUri: String, path: List<String>?, data: ByteArray, result: MethodChannel.Result) {
        val treeUri = Uri.parse(rootUri)

        ioScope.launch {
            var outputStream: OutputStream? = null
            try {
                // 1. 導航到目標父目錄
                val parentPath = path?.dropLast(1)
                val fileName = path?.lastOrNull()
                
                if (fileName.isNullOrEmpty()) {
                    withContext(Dispatchers.Main) {
                        result.error("INVALID_PATH", "Path must contain a file name.", null)
                    }
                    return@launch
                }

                val parentDir = navigateToDirectory(treeUri, parentPath)
                
                if (parentDir == null || !parentDir.isDirectory) {
                    withContext(Dispatchers.Main) {
                        result.error("PARENT_NOT_FOUND", "The parent directory does not exist.", null)
                    }
                    return@launch
                }

                // 2. 查找或創建檔案
                var targetFile = parentDir.findFile(fileName)
                
                if (targetFile == null) {
                    // 如果檔案不存在，使用 "application/octet-stream" 創建一個新的檔案
                    // 這裡的 MIME type 可以根據實際需求調整，但 octet-stream 是通用的二進制類型
                    targetFile = parentDir.createFile("application/octet-stream", fileName)
                }

                if (targetFile == null || !targetFile.isFile) {
                    withContext(Dispatchers.Main) {
                        result.error("CREATE_FAILED", "Failed to create or find target file.", null)
                    }
                    return@launch
                }

                // 3. 寫入數據
                outputStream = applicationContext.contentResolver.openOutputStream(targetFile.uri)
                outputStream?.write(data)

                // 4. 成功回傳 null (void)
                withContext(Dispatchers.Main) {
                    result.success(null) 
                }

            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("WRITE_FAILED", "Failed to write file: ${e.message}", e.toString())
                }
            } finally {
                outputStream?.close() // 確保關閉資源
            }
        }
    }
    
    // ----------------------------------------------------------------------
    // --- 輔助函數 ---
    
    private fun navigateToDirectory(rootUri: Uri, path: List<String>?, isFile: Boolean = false): DocumentFile? {
        var currentDir: DocumentFile? = DocumentFile.fromTreeUri(applicationContext, rootUri)

        if (path.isNullOrEmpty()) {
            return currentDir
        }
        
        val (dirPath, fileName) = if (isFile && path.size > 0) {
            path.dropLast(1) to path.last()
        } else {
            path to null
        }

        for (dirName in dirPath) {
            val nextDir = currentDir?.findFile(dirName)

            if (nextDir == null || !nextDir.isDirectory) {
                return null
            }
            
            currentDir = nextDir
        }
        
        return if (fileName != null) {
            currentDir?.findFile(fileName)
        } else {
            currentDir
        }
    }
}