# Third-party notices

词笺 / Lyric Poster 的原创代码采用 [MIT License](LICENSE)。下列第三方软件、字体和服务仍按各自许可及条款使用，不因本项目的 MIT 许可而改变。

## 内置字体

- 界面字体：寒蝉全圆体（ChillRoundF v3.000，Regular 400）。
- 界面保持字体原生常规字重，避免模拟粗体引起部分汉字的笔画异常；海报字体独立设置。
- 来源：[ChillType / Warren2060，官方 v3.0 原文件](https://github.com/Warren2060/ChillRound/blob/46dda1602729b58de96e3fdee9f918d7aaa64727/ChillRoundF%20v3.0.ttf)。
- 字体 SHA-256：`7dae804b344f7bc1a1c8426b9515e9b54d7baac3e123263d0bae94d0a305a732`。
- 许可：SIL Open Font License 1.1。
- 字体原文件未经修改或子集化；完整原始版权与许可：[assets/fonts/ChillRoundF-OFL.txt](assets/fonts/ChillRoundF-OFL.txt)。
- Windows 发行包同时附带 `CHILLROUND-FONT-LICENSE.txt`。

- 海报默认字体：Noto Sans SC。用户可在海报中导入和使用自己的字体。
- 来源：[Google Fonts / notosanssc](https://github.com/google/fonts/tree/main/ofl/notosanssc)。
- 许可：SIL Open Font License 1.1。
- 完整原始版权与许可：[assets/fonts/OFL.txt](assets/fonts/OFL.txt)。
- Windows 发行包同时附带 `FONT-LICENSE.txt`。

## Flutter、Dart 与直接依赖

| 组件 | 许可 | 上游 |
| --- | --- | --- |
| Flutter / Dart | BSD-3-Clause | [Flutter](https://github.com/flutter/flutter)、[Dart SDK](https://github.com/dart-lang/sdk) |
| cupertino_icons | MIT | [pub.dev](https://pub.dev/packages/cupertino_icons) |
| http | BSD-3-Clause | [pub.dev](https://pub.dev/packages/http) |
| archive | MIT | [pub.dev](https://pub.dev/packages/archive) |
| path_provider | BSD-3-Clause | [pub.dev](https://pub.dev/packages/path_provider) |
| file_picker | MIT | [pub.dev](https://pub.dev/packages/file_picker) |
| pdf | Apache-2.0 | [pub.dev](https://pub.dev/packages/pdf) |
| printing | Apache-2.0 | [pub.dev](https://pub.dev/packages/printing) |
| shared_preferences | BSD-3-Clause | [pub.dev](https://pub.dev/packages/shared_preferences) |
| package_info_plus | BSD-3-Clause | [pub.dev](https://pub.dev/packages/package_info_plus) |
| pub_semver | BSD-3-Clause | [pub.dev](https://pub.dev/packages/pub_semver) |
| url_launcher | BSD-3-Clause | [pub.dev](https://pub.dev/packages/url_launcher) |

实际依赖版本及传递依赖由 `pubspec.lock` 锁定。Flutter 构建生成的 `NOTICES` 资源收录依赖的许可信息；这些许可应随应用资源保留。Material Icons 随 Flutter 使用其上游许可。

Windows 便携包包含 Microsoft Visual C++ Runtime DLL，版权归 Microsoft Corporation，按微软相应再分发条款提供。

## 内容与外部服务

检查更新通过 GitHub 的公开 Releases API 获取正式版本信息；API 不可用时通过 GitHub 最新版发布页确认版本。下载由系统浏览器打开相应发布页面或安装包链接。

网易云音乐的名称、歌曲元数据、歌词和封面均归各自权利人所有。程序只请求公开元数据与歌词，不提供音频下载，不包含会员资源或 DRM 绕过功能。本仓库的 MIT 许可不授予歌词、封面、第三方字体或商标的使用权。导入及分享内容时，请遵守相应版权和平台条款。
