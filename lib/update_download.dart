import 'app_updates.dart';
import 'update_download_common.dart';
import 'update_download_stub.dart'
    if (dart.library.io) 'update_download_io.dart'
    as platform;

export 'update_download_common.dart';

Future<UpdateInstallResult> downloadAndInstallUpdate(
  ReleaseInfo release,
  UpdateDownloadSource source, {
  UpdateProgressCallback? onProgress,
}) => platform.downloadAndInstallUpdateImpl(
  release,
  source,
  onProgress: onProgress,
);
