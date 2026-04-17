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

class MultipartInitResult {
  MultipartInitResult({
    required this.uploadId,
    required this.objectKey,
    required this.partSizeBytes,
    required this.useMultipart,
  });

  final String uploadId;
  final String objectKey;
  final int partSizeBytes;
  final bool useMultipart;

  factory MultipartInitResult.fromJson(Map<String, dynamic> json) {
    return MultipartInitResult(
      uploadId: json['uploadId'] as String,
      objectKey: json['objectKey'] as String,
      partSizeBytes: (json['partSizeBytes'] as num).toInt(),
      useMultipart: json['useMultipart'] as bool,
    );
  }
}

class MultipartPart {
  MultipartPart({required this.partNumber, required this.etag});
  final int partNumber;
  final String etag;

  Map<String, dynamic> toJson() => {'partNumber': partNumber, 'etag': etag};
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

  Future<MultipartInitResult> initMultipartUpload(File file) async {
    final fileName = p.basename(file.path);
    final contentType = _contentTypeByExt(fileName);
    final fileSize = await file.length();

    final response = await _dio.post<Map<String, dynamic>>(
      '$apiBaseUrl/api/upload/multipart/init',
      data: {
        'fileName': fileName,
        'contentType': contentType,
        'fileSize': fileSize,
      },
      options: Options(headers: {'x-user-id': userId}),
    );

    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Invalid multipart init response');
    }
    return MultipartInitResult.fromJson(data);
  }

  Future<String> signMultipartPart({
    required String uploadId,
    required String objectKey,
    required int partNumber,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$apiBaseUrl/api/upload/multipart/sign-part',
      data: {
        'uploadId': uploadId,
        'objectKey': objectKey,
        'partNumber': partNumber,
      },
      options: Options(headers: {'x-user-id': userId}),
    );

    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null || data['uploadUrl'] == null) {
      throw Exception('Invalid sign-part response');
    }
    return data['uploadUrl'] as String;
  }

  Future<void> completeMultipartUpload({
    required String uploadId,
    required String objectKey,
    required List<MultipartPart> parts,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$apiBaseUrl/api/upload/multipart/complete',
      data: {
        'uploadId': uploadId,
        'objectKey': objectKey,
        'parts': parts.map((e) => e.toJson()).toList(),
      },
      options: Options(headers: {'x-user-id': userId}),
    );
  }

  Future<void> abortMultipartUpload({
    required String uploadId,
    required String objectKey,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '$apiBaseUrl/api/upload/multipart/abort',
      data: {
        'uploadId': uploadId,
        'objectKey': objectKey,
      },
      options: Options(headers: {'x-user-id': userId}),
    );
  }

  Future<String> uploadMultipart({
    required File file,
    int maxConcurrent = 3,
    required void Function(double progress) onProgress,
  }) async {
    final initRes = await initMultipartUpload(file);
    final totalSize = await file.length();

    if (!initRes.useMultipart) {
      // 降级为普通长连接上传
      final presign = await requestPresign(file);
      await uploadByPresignedUrl(
        file: file,
        presign: presign,
        onProgress: onProgress,
      );
      return '${presign.bucket}/${presign.objectKey}';
    }

    final partSize = initRes.partSizeBytes;
    final totalParts = (totalSize / partSize).ceil();
    final parts = <MultipartPart>[];
    
    final partChunks = List.generate(totalParts, (index) => index + 1);
    final sentBytesPerPart = <int, int>{};

    try {
      final batches = <List<int>>[];
      for (var i = 0; i < partChunks.length; i += maxConcurrent) {
        batches.add(partChunks.sublist(
            i, i + maxConcurrent > partChunks.length ? partChunks.length : i + maxConcurrent));
      }

      for (final batch in batches) {
        final batchFutures = batch.map((partNum) async {
          final offset = (partNum - 1) * partSize;
          final end = (offset + partSize > totalSize) ? totalSize : offset + partSize;
          final length = end - offset;

          final uploadUrl = await signMultipartPart(
            uploadId: initRes.uploadId,
            objectKey: initRes.objectKey,
            partNumber: partNum,
          );

          final stream = file.openRead(offset, end);

          final putResponse = await _dio.put<void>(
            uploadUrl,
            data: stream,
            options: Options(
              headers: {
                Headers.contentLengthHeader: length,
              },
            ),
            onSendProgress: (sent, total) {
              sentBytesPerPart[partNum] = sent;
              final overallSent = sentBytesPerPart.values.fold<int>(0, (a, b) => a + b);
              onProgress(overallSent / totalSize);
            },
          );

          final etag = putResponse.headers.value('etag') ?? '';
          if (etag.isEmpty) {
            throw Exception('Upload part $partNum failed: no etag');
          }

          return MultipartPart(partNumber: partNum, etag: etag);
        });

        final results = await Future.wait(batchFutures);
        parts.addAll(results);
      }

      parts.sort((a, b) => a.partNumber.compareTo(b.partNumber));

      await completeMultipartUpload(
        uploadId: initRes.uploadId,
        objectKey: initRes.objectKey,
        parts: parts,
      );
      
      // 保证最终进度为 1.0
      onProgress(1.0);
      return initRes.objectKey;
    } catch (e) {
      await abortMultipartUpload(
        uploadId: initRes.uploadId,
        objectKey: initRes.objectKey,
      );
      rethrow;
    }
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
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.m4v':
        return 'video/mp4';
      default:
        // Keep client aligned with backend whitelist.
        return 'application/octet-stream';
    }
  }
}
