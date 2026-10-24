# 个人助理 iOS 3.5.1 · Build 5

为 iPhone 设计的原生 SwiftUI 应用，包含加密笔记、多币种账本、卡包和智能助理。使用 iOS 26 SDK 构建，导航和控制层采用原生 Liquid Glass；最低支持 iOS 17，旧系统提供清晰的兼容显示。

## 安装者只有 iPhone

交付目标为 `PersonalAssistant-iOS-3.5.1-build6-unsigned.ipa`。这是 iOS 真机 arm64 构建，需要你通过自己的签名工具、有效证书与描述文件签名后安装；不能在“文件”中直接点击未签名 IPA 安装。不需要把证书、私钥或 Apple ID 交给本工程。

没有本地 Mac 时，项目的 GitHub Actions 可通过手动触发在云端运行测试并生成 IPA。项目 Actions → `iOS build and unsigned IPA` → 成功运行 → 下载 `PersonalAssistant-iOS-3.5.1-build6-unsigned` artifact。下载得到 ZIP，解压可取得 IPA。**源码 ZIP、模拟器 .app 和 Android APK 都不能当作 IPA 安装。**

保持签名工具使用的 Bundle ID 和签名配置稳定，有助于后续覆盖升级；不同签名方式的数据保留行为以工具与 iOS 为准。免费开发签名通常有有效期限制。首次使用前请导出加密备份。

## 平台与构建

- iPhone，iOS 17.0 及以上；Swift 5 语言模式，包含 iOS 26 SDK 的 Xcode 26 或更新兼容版本。
- 主程序 SwiftUI；系统 Vision OCR；Apple Speech 离线普通话；llama.cpp + Metal 的 Qwen2.5-1.5B Q4_K_M。
- 没有 CocoaPods、第三方 Swift 包或外部项目生成器依赖。Apple SDK 由 Xcode 提供。
- `python3 Scripts/generate_project.py` 生成普通 `.xcodeproj`（已包含共享 Scheme）。
- `bash Scripts/build-ipa.sh` 构建 C++ Metal 运行库和未签名真机 IPA。
- 本机模型单独下载/导入，不内置 1.12GB 权重；文件大小与 SHA256 与 3.5.1 固定版本一致。推荐有足够可用内存的较新 iPhone；不承诺所有设备的速度。

## 已实现

- 加密资料库、系统身份认证解锁、自动锁定、完整 `.pavault` 加密备份恢复与导出。
- 笔记搜索、归档、置顶、滑动删除/恢复、加密草稿、系统拍照 OCR；云端标题与正文润色，摘要/要点/会议纪要/行动提取，原页展示结果、采纳、取消和撤销。
- 多币种流水、分类统计、紧凑日历、预算、退款、账户余额、同币种转账、信用卡还款，卡包与账本联动。
- 98个账户模板、配套手绘图标与卡面；卡包折叠/展开、卡片相连详情、手动资产与负债。
- 月度财务报告、六个月趋势、云端深入分析、31/90天情景推演（不写入流水）。
- 国内贷款类型、分期计划、实际本金/利息/费用分别入账、实际日期综合年化成本、区分机构性质的法律风险提示。
- 订阅续费、资金桶、AA 分摊/结算、投资买卖/分红/报价及对应流水。
- 明确的聊天/财务咨询模式、DeepSeek流式回复、可从 API 刷新的模型列表、云端开关、应用操作知识、历史搜索/重命名/删除和助理记忆。
- Qwen2.5 原生推理与完整性校验下载、Apple系统语音实时文字、简体转换、通知权限与提醒。
- 深色纯黑底色、三种应用图标可选，预设头像与系统相册自定义头像，CSV导入核对与导出，公开汇率查询。

## 数据和隐私

备份格式保留原有 PAVAULT01、PBKDF2-HMAC-SHA256 600000轮、AES-256-GCM 和头部 AAD。金额继续使用 Int64 分，避免浮点金额累计误差。只恢复完整备份，局部备份不会误覆盖完整资料库。

API Key 单独保存在 `ThisDeviceOnly` 钥匙串。资料、草稿和聊天密文存放在排除系统备份的 Application Support，并应用 iOS 文件保护。切入后台会取消录音/对话，后台超过一分钟后再次进入会锁定。

**云端开关开启且已配置密钥时，聊天默认优先请求 DeepSeek；问题、近期对话以及财务咨询使用的金额、明细会原文发送。** 界面有明确说明和开关。没有隐藏脱敏限制。笔记云端整理只有主动点击才发送。

本工程是手动财务管理产品，不会登录银行或获取真实银行余额，不是 Apple Pay 支付卡，也没有远程自动交易功能。卡面使用项目已有的手绘资源，保留来源信息，不额外主张银行商标或卡面授权。

## 验证与限制

只有成功的实际构建与测试日志才能证明对应检查通过。查看交付时生成的 `VERIFICATION.json`。仓库本身包含测试与构建流程，不代表已经完成 Xcode 构建、真机安装或中国运营商网络测试。

详见 [签名安装说明](Docs/INSTALL.md)、[Build 5 改进](Docs/BUILD4.md) 和 [公开构建说明](Docs/OPEN_SOURCE.md)。

## 开源许可与云端构建

原创应用代码、脚本、测试与文档采用 [MIT License](LICENSE)，第三方库、银行标识与图形素材的权利说明见 [NOTICE.md](NOTICE.md)。

公开仓库采用标准 GitHub-hosted runner。完整流程只在 Actions 中手动点击 `Run workflow` 时运行，普通提交不会自动打包。核心测试使用 Ubuntu + Swift 6.0.3，iOS 18 / 26 测试与 IPA 构建使用标准 macOS runner。

本次更新：[Build 5](Docs/BUILD5.md) · [债务记账与自动提醒规则](Docs/DEBT_MODEL.md)。

本次更新见 [Build 6](Docs/BUILD6.md)。全产品模拟器审计发现的额外优化会单独列建议，获得用户确认后再实施。
