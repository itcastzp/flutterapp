import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

class PresignResult {
  PresignResult({
    required this.bucket,
    required this.objectKey,
    required this.uploadUrl,
    required this.expireSeconds,
  });

  final String bucket;
  final String objectKey;
  final String uploadUrl;
  final int expireSeconds;

  factory PresignResult.fromJson(Map<String, dynamic> json) {
    return PresignResult(
      bucket: json['bucket'] as String,
      objectKey: json['objectKey'] as String,
      uploadUrl: json['uploadUrl'] as String,
      expireSeconds: (json['expireSeconds'] as num).toInt(),
    );
  }
}

class UploadService {
  UploadService({
    required this.apiBaseUrl,
    required this.userId,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final String apiBaseUrl;
  final String userId;
  final Dio _dio;

  Future<PresignResult> requestPresign(File file) async {
    final fileName = p.basename(file.path);
    final contentType = _contentTypeByExt(fileName);
    final fileSize = await file.length();

    final response = await _dio.post<Map<String, dynamic>>(
      '$apiBaseUrl/api/upload/presign',
      data: {
        'fileName': fileName,
        'contentType': contentType,
        'fileSize': fileSize,
      },
      options: Options(headers: {'x-user-id': userId}),
    );

    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Invalid presign response');
    }
    return PresignResult.fromJson(data);
  }

  Future<void> uploadByPresignedUrl({
    required File file,
    required PresignResult presign,
    required void Function(double progress) onProgress,
  }) async {
    final contentType = _contentTypeByExt(file.path);
    final total = await file.length();

    await _dio.put<void>(
      presign.uploadUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          'Content-Type': contentType,
          Headers.contentLengthHeader: total,
        },
      ),
      onSendProgress: (sent, totalBytes) {
        final base = totalBytes > 0 ? totalBytes : total;
        if (base <= 0) {
          onProgress(0);
          return;
        }
        onProgress(sent / base);
      },
    );
  }

  String _contentTypeByExt(String name) {
    final ext = p.extension(name).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        // Keep client aligned with backend whitelist.
        return 'application/octet-stream';
    }
  }
}
