import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'upload_service.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  // Android emulator can use 10.0.2.2 to access host machine.
  final _service = UploadService(
    apiBaseUrl: 'http://106.13.175.215',
    userId: 'u1001',
  );
  final _picker = ImagePicker();

  File? _pickedFile;
  bool _isVideo = false;
  double _progress = 0;
  bool _uploading = false;
  String _status = '请先选择图片或视频';
  String? _uploadedObjectKey;
  String _debugInfo = '';

  void _appendDebug(String line) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _debugInfo = '[$time] $line\n$_debugInfo';
    });
  }

  String _formatError(Object error) {
    if (error is DioException) {
      final uri = error.requestOptions.uri.toString();
      final code = error.response?.statusCode;
      return 'DioException(type: ${error.type}, code: $code, uri: $uri, message: ${error.message})';
    }
    return error.toString();
  }

  Future<void> _pickMedia() async {
    final xFile = await _picker.pickMedia();
    if (xFile == null) return;
    final lowerPath = xFile.path.toLowerCase();
    final isVideo = lowerPath.endsWith('.mp4') ||
        lowerPath.endsWith('.mov') ||
        lowerPath.endsWith('.m4v');
    setState(() {
      _pickedFile = File(xFile.path);
      _isVideo = isVideo;
      _progress = 0;
      _uploadedObjectKey = null;
      _status = '已选择${isVideo ? "视频" : "图片"}: ${xFile.name}';
      _debugInfo = '';
    });
    _appendDebug('API Base URL: ${_service.apiBaseUrl}');
    _appendDebug('已选择文件: ${xFile.path}');
  }

  Future<void> _uploadFile() async {
    final file = _pickedFile;
    if (file == null || _uploading) return;

    setState(() {
      _uploading = true;
      _status = '正在请求上传凭证...';
    });

    try {
      _appendDebug('开始请求预签名: ${_service.apiBaseUrl}/api/upload/presign');
      final presign = await _service.requestPresign(file);
      _appendDebug('预签名成功: bucket=${presign.bucket}, objectKey=${presign.objectKey}');
      _appendDebug('uploadUrl: ${presign.uploadUrl}');
      setState(() {
        _status = '上传中...';
      });

      await _service.uploadByPresignedUrl(
        file: file,
        presign: presign,
        onProgress: (value) {
          setState(() {
            _progress = value;
          });
        },
      );

      setState(() {
        _uploadedObjectKey = '${presign.bucket}/${presign.objectKey}';
        _status = '上传成功';
      });
      _appendDebug('上传完成: $_uploadedObjectKey');
    } catch (e) {
      setState(() {
        _status = '上传失败: ${_formatError(e)}';
      });
      _appendDebug('上传失败: ${_formatError(e)}');
    } finally {
      setState(() {
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickedFile = _pickedFile;
    return Scaffold(
      appBar: AppBar(title: const Text('MinIO 文件上传 MVP')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: pickedFile == null
                    ? const Center(child: Text('未选择文件'))
                    : _isVideo
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.videocam, size: 56),
                                const SizedBox(height: 8),
                                Text(
                                  '视频文件: ${pickedFile.path.split(Platform.pathSeparator).last}',
                                  textAlign: TextAlign.center,
                                )
                              ],
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(pickedFile, fit: BoxFit.cover),
                          ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_status),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _uploading ? _progress : (_progress == 0 ? null : _progress),
            ),
            const SizedBox(height: 12),
            if (_uploadedObjectKey != null)
              SelectableText('Object Key: $_uploadedObjectKey'),
            const SizedBox(height: 12),
            if (_debugInfo.isNotEmpty) ...[
              const Text('诊断信息（可截图）'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxHeight: 140),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _debugInfo,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _uploading ? null : _pickMedia,
                    child: const Text('选择图片/视频'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (_pickedFile == null || _uploading) ? null : _uploadFile,
                    child: const Text('上传到 MinIO'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
