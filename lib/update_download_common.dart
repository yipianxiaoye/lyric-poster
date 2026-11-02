import 'app_updates.dart';

enum UpdateDownloadSource { github, mirror }

class UpdateDownloadProgress {
  const UpdateDownloadProgress(this.receivedBytes, this.totalBytes);

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : (receivedBytes / totalBytes!).clamp(0, 1);
}

typedef UpdateProgressCallback = void Function(UpdateDownloadProgress value);

class UpdateInstallResult {
  const UpdateInstallResult(this.message, {this.permissionRequired = false});

  final String message;
  final bool permissionRequired;
}

typedef UpdateDownloadHandler =
    Future<UpdateInstallResult> Function(
      ReleaseInfo release,
      UpdateDownloadSource source, {
      UpdateProgressCallback? onProgress,
    });

class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
