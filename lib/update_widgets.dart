import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_updates.dart';

typedef UpdateUrlLauncher = Future<bool> Function(Uri url);

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
  const UpdatePanel({required this.controller, this.launcher, super.key});

  final UpdateController controller;
  final UpdateUrlLauncher? launcher;

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
                  if (showUpdate)
                    FilledButton.icon(
                      onPressed: () => openUpdateUrl(
                        context,
                        release!.downloadUrl ?? release.pageUrl,
                        launcher: launcher,
                      ),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('下载新版'),
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
              if (showUpdate && release!.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  release.notes,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
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
      FilledButton.icon(
        onPressed: () => openUpdateUrl(
          dialogContext,
          release.downloadUrl ?? release.pageUrl,
          launcher: launcher,
        ),
        icon: const Icon(Icons.download_outlined, size: 18),
        label: const Text('下载新版'),
      ),
    ],
  ),
);
