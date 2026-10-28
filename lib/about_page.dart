import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'github_profile.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    this.repositoryUrl = 'https://github.com/yipianxiaoye/lyric-poster',
    this.initialProfile = GitHubProfile.author,
    this.profileLoader,
  });

  final String repositoryUrl;
  final GitHubProfile initialProfile;
  final Future<GitHubProfile> Function()? profileLoader;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late Future<GitHubProfile> profile;

  @override
  void initState() {
    super.initState();
    profile = (widget.profileLoader ?? loadAuthorProfile)();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('关于词笺', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/icons/app_icon.png',
                          width: 48,
                          height: 48,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '词笺 · Lyric Poster',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text('版本 1.5.3+11'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      '把喜欢的歌词做成可打印的海报。使用 Flutter 构建，支持手机和电脑上的歌曲搜索、歌单导入、海报编辑与多页导出。',
                      style: TextStyle(height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<GitHubProfile>(
              future: profile,
              initialData: widget.initialProfile,
              builder: (context, snapshot) =>
                  authorCard(snapshot.data ?? widget.initialProfile),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle('开源与许可'),
                    const SizedBox(height: 12),
                    const Text(
                      '软件源码：MIT License\n界面字体：寒蝉全圆体（原生常规字重），SIL Open Font License 1.1\n默认海报字体：Noto Sans SC，SIL Open Font License 1.1',
                      style: TextStyle(height: 1.7),
                    ),
                    const SizedBox(height: 12),
                    const Text('GitHub 仓库'),
                    copyLink(widget.repositoryUrl, '复制仓库链接'),
                    const SizedBox(height: 8),
                    const Text(
                      '开源许可涵盖本软件源码；导入的歌词、封面和自定义字体各自适用其权利人的授权。',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle('本机数据'),
                    const SizedBox(height: 12),
                    const Text(
                      '歌单历史和海报草稿保存在应用数据目录的 history 文件夹；导入的字体保存在 fonts 文件夹。草稿包含歌词、背景图和贴纸，可从“历史”继续编辑。',
                      style: TextStyle(height: 1.6),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '本机数据不会被上传。删除记录时，相应草稿中的图片也会一起删除。',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget authorCard(GitHubProfile author) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle('作者'),
          const SizedBox(height: 14),
          Row(
            children: [
              ClipOval(
                child: author.avatarUrl.isEmpty
                    ? avatarFallback()
                    : Image.network(
                        author.avatarUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Image.asset(
                          'assets/images/github-avatar.png',
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => avatarFallback(),
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '一片小叶',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('@${author.login}'),
                    if (author.location?.trim().isNotEmpty ?? false)
                      Text(author.location!),
                  ],
                ),
              ),
            ],
          ),
          if (author.bio?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 14),
            Text(author.bio!, style: const TextStyle(height: 1.5)),
          ],
          const SizedBox(height: 12),
          copyLink(author.profileUrl, '复制作者主页'),
        ],
      ),
    ),
  );

  Widget sectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
  );

  Widget avatarFallback() => ColoredBox(
    color: Theme.of(context).colorScheme.primaryContainer,
    child: SizedBox.square(
      dimension: 64,
      child: Icon(
        Icons.person_outline,
        size: 34,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
  );

  Widget copyLink(String value, String tooltip) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: SelectableText(
          value,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      IconButton(
        tooltip: tooltip,
        icon: const Icon(Icons.copy_outlined, size: 20),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('链接已复制')));
        },
      ),
    ],
  );
}
