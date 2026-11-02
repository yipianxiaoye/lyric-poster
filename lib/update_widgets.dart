import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_updates.dart';
import 'update_download.dart';

export 'update_download.dart' show UpdateDownloadSource;

typedef UpdateUrlLauncher = Future<bool> Function(Uri url);
typedef UpdateActionHandler =
    Future<void> Function(
      BuildContext context,
      ReleaseInfo release,
      UpdateDownloadSource source,
    );

final _latestDownloadPageUrl = Uri.parse(
  'https://github.com/yipianxiaoye/lyric-poster/releases/latest',
);

Future<bool> _launchUpdateUrl(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

Future<void> openUpdateUrl(
  BuildContext context,
  Uri url, {
  UpdateUrlLauncher? launcher,
}) async {
  try {
    if (await (launcher ?? _launchUpdateUrl)(url)) return;
  } catch (_) {
    // Keep the download link accessible if the system has no browser handler.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('无法打开浏览器'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请复制下方链接，在浏览器中打开。'),
            const SizedBox(height: 12),
            SelectableText(url.toString()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () => copyUpdateLink(dialogContext, url),
          child: const Text('复制链接'),
        ),
      ],
    ),
  );
}

Future<void> copyUpdateLink(BuildContext context, Uri url) async {
  var copied = false;
  try {
    await Clipboard.setData(ClipboardData(text: url.toString()));
    copied = true;
  } catch (_) {
    // The selectable link is still available when clipboard access is denied.
  }
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(copied ? '下载链接已复制' : '无法访问剪贴板，请长按或选中链接复制')),
  );
}

class UpdatePanel extends StatelessWidget {
  const UpdatePanel({
    required this.controller,
    this.launcher,
    this.downloader,
    this.beforeInstall,
    super.key,
  });

  final UpdateController controller;
  final UpdateUrlLauncher? launcher;
  final UpdateActionHandler? downloader;
  final Future<void> Function()? beforeInstall;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final release = controller.latestRelease;
      final showUpdate = controller.updateAvailable && controller.error == null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '软件更新',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 10),
              const Text('每次启动时自动检查，有新版本时会提醒你。'),
              const SizedBox(height: 12),
              if (controller.checking)
                const Text('正在检查更新…')
              else if (controller.error != null)
                Text(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else if (showUpdate)
                Text('发现新版本 ${release!.version}')
              else if (release != null)
                const Text('当前已是最新版本'),
              if (controller.lastCheckedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  '上次检查：${_formatCheckTime(controller.lastCheckedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.checking ? null : controller.check,
                    icon: controller.checking
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.system_update_outlined, size: 18),
                    label: Text(
                      controller.checking
                          ? '检查中…'
                          : controller.error == null
                          ? '检查更新'
                          : '重新检查',
                    ),
                  ),
                  if (controller.error != null && !controller.checking)
                    TextButton.icon(
                      onPressed: () => openUpdateUrl(
                        context,
                        _latestDownloadPageUrl,
                        launcher: launcher,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('前往下载页'),
                    ),
                  if (showUpdate && release!.downloadSha256 != null) ...[
                    FilledButton.icon(
                      onPressed: () => _startUpdateDownload(
                        context,
                        release,
                        UpdateDownloadSource.github,
                        downloader: downloader,
                        beforeInstall: beforeInstall,
                      ),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('GitHub 下载'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _startUpdateDownload(
                        context,
                        release,
                        UpdateDownloadSource.mirror,
                        downloader: downloader,
                        beforeInstall: beforeInstall,
                      ),
                      icon: const Icon(Icons.cloud_download_outlined, size: 18),
                      label: const Text('镜像下载（第三方）'),
                    ),
                  ],
                  if (showUpdate)
                    TextButton.icon(
                      onPressed: () => openUpdateUrl(
                        context,
                        release!.pageUrl,
                        launcher: launcher,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('前往发布页'),
                    ),
                  if (release != null)
                    TextButton(
                      onPressed: () => openUpdateUrl(
                        context,
                        release.pageUrl,
                        launcher: launcher,
                      ),
                      child: const Text('查看发布说明'),
                    ),
                ],
              ),
              if (showUpdate) ...[
                const SizedBox(height: 12),
                Text(
                  release!.notes.trim().isEmpty
                      ? '更新说明暂不可用，请前往发布页查看。'
                      : release.notes,
                  style: const TextStyle(height: 1.5),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

String _formatCheckTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

Future<void> showAppUpdateDialog(
  BuildContext context,
  ReleaseInfo release, {
  UpdateUrlLauncher? launcher,
  UpdateActionHandler? downloader,
  Future<void> Function()? beforeInstall,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    scrollable: true,
    title: Text('发现新版本 ${release.version}'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('词笺有新版本可供下载。'),
          if (release.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(release.notes, style: const TextStyle(height: 1.5)),
          ] else ...[
            const SizedBox(height: 14),
            const Text('更新说明暂不可用，请前往发布页查看。'),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => openUpdateUrl(
              dialogContext,
              release.pageUrl,
              launcher: launcher,
            ),
            child: const Text('查看发布说明'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('稍后'),
      ),
      if (release.downloadUrl != null && release.downloadSha256 != null)
        FilledButton.icon(
          onPressed: () => _startUpdateDownload(
            dialogContext,
            release,
            UpdateDownloadSource.github,
            downloader: downloader,
            beforeInstall: beforeInstall,
          ),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('GitHub 下载'),
        ),
      if (release.downloadUrl != null && release.downloadSha256 != null)
        OutlinedButton.icon(
          onPressed: () => _startUpdateDownload(
            dialogContext,
            release,
            UpdateDownloadSource.mirror,
            downloader: downloader,
            beforeInstall: beforeInstall,
          ),
          icon: const Icon(Icons.cloud_download_outlined, size: 18),
          label: const Text('镜像下载（第三方）'),
        ),
      TextButton.icon(
        onPressed: () =>
            openUpdateUrl(dialogContext, release.pageUrl, launcher: launcher),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: const Text('前往发布页'),
      ),
    ],
  ),
);

Future<void> _startUpdateDownload(
  BuildContext context,
  ReleaseInfo release,
  UpdateDownloadSource source, {
  UpdateActionHandler? downloader,
  Future<void> Function()? beforeInstall,
}) async {
  final progress = ValueNotifier<UpdateDownloadProgress>(
    const UpdateDownloadProgress(0, null),
  );
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('正在下载更新'),
          content: SizedBox(
            width: 360,
            child: ValueListenableBuilder<UpdateDownloadProgress>(
              valueListenable: progress,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source == UpdateDownloadSource.github ? 'GitHub' : '镜像源',
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: value.fraction),
                  const SizedBox(height: 8),
                  Text(
                    _formatDownloadBytes(value.receivedBytes, value.totalBytes),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  try {
    await beforeInstall?.call();
    if (!context.mounted) return;
    if (downloader != null) {
      await downloader(context, release, source);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    final result = await downloadAndInstallUpdate(
      release,
      source,
      onProgress: (value) => progress.value = value,
    );
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(result.message)));
  } catch (failure) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更新未能启动'),
        content: Text(failure.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () => openUpdateUrl(
              dialogContext,
              release.pageUrl,
              launcher: _launchUpdateUrl,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('前往发布页'),
          ),
        ],
      ),
    );
  } finally {
    progress.dispose();
  }
}

String _formatDownloadBytes(int received, int? total) {
  String format(int value) => value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(0)} KB'
      : '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  return total == null
      ? '已下载 ${format(received)}'
      : '${format(received)} / ${format(total)}';
}
