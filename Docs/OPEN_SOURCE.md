# 开源与公开构建

应用代码、脚本、测试和文档采用 MIT 许可，第三方素材及商标的范围见 [NOTICE.md](../NOTICE.md)。

## 公开前检查

2026-10-24 对基线提交 `9ab1557559a159ed5c4d75c22a8b140da7edb645` 的 25 个 Git 历史提交进行了 Gitleaks 8.30.1 扫描。4 个提示经人工复核，分别为 llama.cpp 的单像素 PNG 测试数据、`your-api-key` 文档占位符和 xxHash 的两处 SIMD 变量表达式，没有发现真实凭据。同时扫描了 23 次已有 Actions 运行的完整日志，未发现凭据。

已跟踪文件中没有签名证书、描述文件、资料库备份、数据库、IPA 或 APK。Git 提交作者使用 GitHub no-reply 邮箱。公开的是项目与历史；用户手机中存储的资料和钥匙串密钥不属于仓库。

该检查是一次具体版本检查，不构成未来提交永不泄露数据的保证。请勿提交 API Key、签名材料或个人导出文件。

## 在手机上手动打包

1. 登录 GitHub，进入本项目的 **Actions → iOS build and unsigned IPA**。
2. 点 **Run workflow**，选择 `main` 后运行。
3. 核心测试在标准 Ubuntu runner 的 Swift 6.0.3 官方容器中执行；iOS 18 / 26 测试和 IPA 打包使用标准 `macos-15` runner。
4. 全部测试通过后，下载 `PersonalAssistant-iOS-3.5.1-build9-unsigned` artifact，解压取得 IPA，再按已有方式自行签名安装。

工作流只通过手动触发运行，普通提交、文档修改和 Fork 的拉取请求不会自动启动完整打包。没有使用付费 larger runner，工作流权限保持 `contents: read`，不需要上传 Apple 证书或 DeepSeek 密钥。

GitHub 当前规定：公开仓库使用标准 GitHub-hosted runner 的运行时间免费，不占用私有仓库的月度免费分钟数；larger runner 属于另一种计费范围。本项目使用前者。官方说明：https://docs.github.com/en/actions/reference/runners/github-hosted-runners 。
