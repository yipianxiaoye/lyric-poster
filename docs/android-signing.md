# Android 正式签名与构建

正式 APK 需要长期使用同一把私钥签名。项目已支持私有 `key.properties`，私钥和密码放在仓库外；不要上传到 GitHub、网盘公开链接或问题反馈。

## 1. 准备环境

使用项目指定的 Flutter 版本、JDK 17 和 Android SDK。在普通 PowerShell 中进入项目目录，确认工具可用：

```powershell
flutter --version
java -version
keytool -help
```

首次使用 Android SDK 时，通过官方 Android SDK 工具完成许可确认。环境准备好后，以下操作不需要管理员权限。

## 2. 创建自己的正式签名

如果已经有本项目的正式签名，请直接复用，跳到第 3 步。**已有正式私钥时不要重新生成**；新私钥无法给已安装的旧签名版本覆盖升级。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-android-signing.ps1
```

按提示输入并确认至少 12 个字符的密码。也可以让脚本使用密码学随机数生成强密码：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-android-signing.ps1 -GeneratePassword
```

脚本仅首次创建以下文件，遇到已存在的签名会停止，避免更换应用身份：

| 文件 | 作用 |
| --- | --- |
| `%USERPROFILE%\.lyric-poster\signing\release\lyric-poster-release.jks` | RSA 4096 位正式私钥，证书有效期 10000 天 |
| 同目录 `key.properties` | 密钥路径、别名、私钥密码与仓库密码 |
| 同目录 `KEEP-PRIVATE.txt` | 私密备份与恢复提醒 |

`key.properties` 含明文密码，目录权限限制为当前用户、SYSTEM 和管理员。脚本不会在终端打印密码，不会修改用户环境变量，也不会替换旧预览签名。使用 `-SigningDirectory 'D:\PrivateSigning\lyric-poster'` 可选择仓库外的新空目录；不要选择源代码目录或与其他资料混用的目录。

**请将整个签名目录备份到私有加密存储**，建议另留一份离线备份。未来构建无需重新输入密码，但依赖这份配置和私钥。丢失私钥可能导致无法继续给原 APK 发布升级；不要将私钥备份放进发布 ZIP 或 APK。

## 3. 检查签名并构建 APK

检查已有签名，不会重新生成或修改私钥：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-android-signing.ps1 -CheckOnly
```

显式选择正式签名构建：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-android.ps1 -SigningProperties "$env:USERPROFILE\.lyric-poster\signing\release\key.properties"
```

构建脚本使用独立英文暂存目录，默认运行测试，生成包含 ARMv7、ARM64 和 x86_64 的通用 Release APK。结果位于 `dist/LyricPoster-<版本号>-android-universal.apk`，旁边的 `.json` 记录证书指纹、版本、架构与哈希，`.sha256` 可用于下载校验。日志位于 `work/android/`。

先运行同一命令并加 `-CheckOnly` 可检查构建环境和配置字段；签名有效性请使用上一条 `setup-android-signing.ps1 -CheckOnly` 检查。使用自定义签名目录时，两条命令都传入对应的路径。

原有打包脚本为兼容历史预览版保留默认签名配置。因此正式构建时请始终显式传入上面的 `-SigningProperties`，避免误用预览签名。

## 4. 后续升级与恢复

后续版本提高 `pubspec.yaml` 的版本号和 `+` 后面的构建号，再使用**同一份**正式 `key.properties` 构建。可比较每次产物 JSON 中的 `certificateSha256`；正式版本之间必须一致。

更换电脑后，恢复整个私有签名目录，安装兼容工具链，然后将 `key.properties` 的 `storeFile` 修改为私钥的新绝对路径（Windows 路径建议使用 `/`）。保留密码、`keyAlias` 和私钥本身。中文和特殊字符需要 Java properties 转义；默认脚本已自动处理，手工编辑时避免改变这些转义。

早期预览 APK 使用 Android Debug 证书。本次独立正式签名与它不同，Android 会拒绝同包名覆盖安装，并显示签名冲突。**不要直接卸载有重要草稿的预览版**；请先在原软件导出或备份需要保留的资料，确认保存后再自行决定是否卸载旧版并安装正式版。首次完成迁移后，后续使用这把正式密钥的版本即可正常覆盖升级。

## 5. APK 签名与应用商店

本流程生成可直接安装、带正式私钥签名的 Release APK，不代表已提交应用商店。若计划上架 Google Play，需要另行设置 Play App Signing、上传密钥和 AAB 发行流程；请在首次商店发布前决定应用签名策略，并妥善备份上传密钥和恢复资料。

CI 当前的临时测试签名仅用于构建验证，不能替代本地正式私钥，也无法覆盖正式安装版。不要为方便构建将真实密码或私钥提交到仓库。
