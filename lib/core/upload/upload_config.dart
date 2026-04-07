import 'package:flutter_dotenv/flutter_dotenv.dart';

class UploadConfig {
  const UploadConfig({
    required this.baseUrl,
    required this.uploadPath,
    this.connectTimeout = const Duration(seconds: 10),
    this.sendTimeout = const Duration(seconds: 60),
    this.receiveTimeout = const Duration(seconds: 30),
    this.extraHeaders = const <String, String>{},
    this.maxRetryAttempts = 3,
    this.retryBaseDelay = const Duration(seconds: 2),
    this.maxHistoryItems = 40,
  });

  final String baseUrl;
  final String uploadPath;
  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;
  final Map<String, String> extraHeaders;
  final int maxRetryAttempts;
  final Duration retryBaseDelay;
  final int maxHistoryItems;

  Uri get uploadUri {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final normalizedPath = uploadPath.startsWith('/')
        ? uploadPath.substring(1)
        : uploadPath;
    return Uri.parse(normalizedBase).resolve(normalizedPath);
  }

  UploadConfig copyWith({
    String? baseUrl,
    String? uploadPath,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    Map<String, String>? extraHeaders,
    int? maxRetryAttempts,
    Duration? retryBaseDelay,
    int? maxHistoryItems,
  }) {
    return UploadConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      uploadPath: uploadPath ?? this.uploadPath,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      extraHeaders: extraHeaders ?? this.extraHeaders,
      maxRetryAttempts: maxRetryAttempts ?? this.maxRetryAttempts,
      retryBaseDelay: retryBaseDelay ?? this.retryBaseDelay,
      maxHistoryItems: maxHistoryItems ?? this.maxHistoryItems,
    );
  }
}

String _requireEnv(String key) {
  final value = dotenv.env[key]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('缺少环境变量: $key');
  }
  return value;
}

Duration _durationSecondsEnv(String key, Duration fallback) {
  final raw = dotenv.env[key]?.trim();
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 0) {
    return fallback;
  }
  return Duration(seconds: parsed);
}

int _intEnv(String key, int fallback) {
  final raw = dotenv.env[key]?.trim();
  if (raw == null || raw.isEmpty) {
    return fallback;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < 0) {
    return fallback;
  }
  return parsed;
}

String _uploadBaseUrlFromEnv() => _requireEnv('UPLOAD_BASE_URL');
String _uploadPathFromEnv() => _requireEnv('UPLOAD_PATH');
String _uploadTokenFromEnv() => _requireEnv('UPLOAD_AUTH_TOKEN');

UploadConfig get defaultUploadConfig => UploadConfig(
  baseUrl: _uploadBaseUrlFromEnv(),
  uploadPath: _uploadPathFromEnv(),
  connectTimeout: _durationSecondsEnv(
    'UPLOAD_CONNECT_TIMEOUT_SECONDS',
    const Duration(seconds: 10),
  ),
  sendTimeout: _durationSecondsEnv(
    'UPLOAD_SEND_TIMEOUT_SECONDS',
    const Duration(minutes: 10),
  ),
  receiveTimeout: _durationSecondsEnv(
    'UPLOAD_RECEIVE_TIMEOUT_SECONDS',
    const Duration(seconds: 60),
  ),
  extraHeaders: <String, String>{
    'Authorization': 'Bearer ${_uploadTokenFromEnv()}',
  },
  maxRetryAttempts: _intEnv('UPLOAD_MAX_RETRY_ATTEMPTS', 3),
  retryBaseDelay: _durationSecondsEnv(
    'UPLOAD_RETRY_BASE_DELAY_SECONDS',
    const Duration(seconds: 2),
  ),
  maxHistoryItems: _intEnv('UPLOAD_MAX_HISTORY_ITEMS', 40),
);
