import 'app_updates.dart';
import 'update_download_common.dart';

Future<UpdateInstallResult> downloadAndInstallUpdateImpl(
  ReleaseInfo release,
  UpdateDownloadSource source, {
  UpdateProgressCallback? onProgress,
}) => throw UnsupportedError('此平台不支持应用内安装更新');
