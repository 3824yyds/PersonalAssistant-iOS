# PersonalAssistant-iOS · Build 9 交接

## 宣传片预览分支补充（2026-10-25）

**后续已完成产品操作演示 MP4**：用户确认视觉后明确强调“要产品演示视频，不是产品截图”。工作已按真实原生应用操作录屏完成，素材为运行40196944650（success）、artifact12600193921、源码5a3e5e3。全新iOS26模拟器录制190.955秒连续视频，录制流程 PromoDemoTests 一项通过，实际输入和保存笔记/支出、切换统计/日历、查看卡包、双向滑动Flash/Pro、发送本机问候、控制语音界面、锁定资料库。

成片 `/workspace/product-demo/个人助理-产品操作演示-45秒.mp4`：45秒、1080×1920、30fps、1350帧、H.264/AAC、5,282,946字节，SHA256 `af2522d298b1f744492deb56968a126284d2049864d1de362fc8dd044ec603ff`。44段视频均取自实际连续录屏，剪去等待并适当加速，后期添加字幕、点击辅助、边框和原创音乐。当前视频取代静态分镜作为本轮交付，不能再把预览图当作演示视频交付。

`Marketing/ProductDemo` 保存源脚本、操作事件与剪辑时间对应关系。全部金额/笔记为虚构演示数据。语音段明确为“语音界面操作演示”，只展示进入、静音、取消静音和退出；没有真实收音、云端回复或新音色。音色升级继续搁置。没有更新Build9 IPA、改用户资料或发布视频。

本节只适用于 `codex/promo-preview`：用户已要求制作产品宣传视频，并同意先出关键画面预览，视觉确认后再做完整视频。音色服务升级已明确搁置，不要重新推进付费 TTS 或男女声接入。

`Marketing/PromoPreview` 保存六张竖屏 1080×1920 关键画面的原始排版、渲染脚本、45秒时间线和实际模拟器截图。工作区交付位于 `/workspace/product-promo`，包含总览 PNG、六页高清 PDF、单文件逐张预览 HTML。此时尚未生成带转场、音乐的 MP4，不能称视频已完成。

截图采集运行 40194874943 成功，artifact 12599592959，来源提交7c96621。只运行 PromoCaptureTests 一项采集任务，使用全新 iOS 26 模拟器与虚构笔记/金额；语音画面采用模拟收听状态，无真实麦克风或音质验证。`--promo-capture` 和夹具均限 DEBUG；语音演示隐藏测试按钮。没有改动发布版、版本号、资料格式或用户资料。Build 9 IPA 仍以本文件后文记载为准。

静态分镜阶段已结束，后续根据用户对实际MP4的反馈继续调整。不要擅自发布、添加不存在的App Store入口，或把演示状态宣传为真实延迟/自然音色证据。

2026-10-25 UTC。最新交付为 **3.5.1（Build 9）**。历史交接保存在 Docs/HANDOFF_BUILD8.md 和 Docs/HANDOFF_BUILD6.md。

## 当前交付事实

- 分支 codex/fullscreen-notes-model-slider；PR #1：https://github.com/3824yyds/PersonalAssistant-iOS/pull/1 。应用修改仍在该分支，main 尚未合并。
- 最终应用构建提交：2fb3ff5221a180cebb277cfba060aad3c5a8dcad。之后的文档/测试流程提交不更新 IPA。
- 最终设备打包：https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40184774721
- artifact：https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40184774721/artifacts/12596290415
- IPA：/workspace/deliverables/build9-device/PersonalAssistant-iOS-3.5.1-build9-unsigned.ipa；80,601,885 字节。
- SHA-256：296ee0068cea873b0ee4f896a59ac8d792cce264ab8f0dcc94128d02ab7a4979
- 安装 ZIP：/workspace/deliverables/PersonalAssistant-iOS-3.5.1-build9-Install.zip
- 当前清单：/workspace/deliverables/build9-delivery-manifest.json
- 最低 iOS 17，SDK iphoneos26.2，未签名 iPhone arm64，Bundle ID cn.local.assistant.ios。沿用原签名方式覆盖安装；没有证明新版本在用户手机已安装成功。
- 40182602239 是缺少后续口语提示的中间 Build 9，不作为最终交付。

## 本轮用户问题、决定与完成内容

用户在 Build 8 说话后，识别文字“你好呀”已出现，但一直停留“正在听”。用户随后确认手动点球能进入思考并听到回复，说明这次主要卡点在自动结束/发送。旧逻辑每次环境音量超过0.16都会刷新活动时间，底噪可使自动发送持续推迟；旧模拟整句夹具绕过这一步，没有覆盖到它。

Build 9 新增 VoiceTurnDetector：实质识别文字变化刷新文本时钟，重复文字/空白/标点不延长；安静停顿可提前结束，文本稳定2.2秒后不受持续底噪阻止。界面增加识别确认、语音准备状态及“发送这句话”；识别收尾有兜底，合成8秒没启动回调显示错误。现有手动点球发送/打断保留。

用户另要求像正常口语交流，简洁、直接、少输出大段。AIService.reply 增加仅全屏语音 spoken 请求启用的 voiceConversation 提示：默认1至3短句、通常20至80字，先回答、一次一个澄清问题；用户明确要求详解时展开，金额/币种/日期/实际保存回执完整保留。普通文字聊天和笔记 AI 不受该语音提示影响。没有通过硬截断回答来实现简短，也没有声称真实模型每次都满足字数。

原有全屏笔记、输入区 Flash/Pro 滑动选择器、展开名称无 >、文字键盘保留和语音长按层条件移除均保留。不要把语音 Text 改回只设透明；modelMenu 展开时直接移除该 Text/背景/手势，以42pt透明占位。UIKit 文字输入仍常驻，通过 concealed 隐藏文字/光标，保护中文输入法焦点。

## 音色服务尚待用户选择

用户想要更像人声、可选男声/女声与调语速，最新决定是“先比较试听效果和费用再决定”。已整理官方试听和费用，见 Docs/VOICE_OPTIONS.md；未接入新的付费 TTS，没有创建付费资源或调用付费语音 API。男女声选择和扩展调速待方案选定后实现；现有系统朗读及三档语速仍可用。不要声称新音色已实现，也不要未经用户决定擅自接入付费服务。

比较建议：保留 DeepSeek Flash/Pro 负责回答，另接专门TTS负责发声。Azure 标准神经音色 East US 约$15/百万字符；HD约$22，但HD官方不支持SSML prosody，语速需客户端处理。ElevenLabs当前v4约$0.08/千字符，Turbo约$0.04/千字符。OpenAI mini TTS输入文本$0.60/百万token、音频输出$12/百万token，不能直接按字数混算。官方试听链接与定价来源都在报告里，价格按2026-10-25核对。

## 验证记录（不能混同）

- 40182519825：应用源码 d1b8cd5；8项 VoiceTurnDetector 核心测试通过，包括持续高底噪、正常讲话进展、标点/重复、空文本、金额修订等。
- 同次 iOS：识别最终结果兜底及取消两项通过，三个界面场景通过。新的模拟发言只注入中间识别文字和持续0.95噪声，必须经过生产的停顿计时再发送和获取本地回复，不再直接跳过自动结束。
- 该次整体 failure：PCM 检查错误地把每个零帧回调当结束，多次 fulfill 导致测试工具崩溃。不能把该运行标成整体success。
- 40184169700：b23c863 仅改测试和工作流；PCM 检查按实际非静音数据只报告一次，通过。实际2700帧，峰值0.4562378。核心8项也再次通过，不重复计数。
- 合计14个不同相关检查分别通过：核心8、识别收尾2、界面3、PCM1。不是完整UI验证，complete_UI_validation_verified=false。
- 最终2fb3ff5在此前功能代码上增加语音专用口语提示，并设备Release编译通过；没有用用户真实DeepSeek Key做付费模型风格测试。模型表达风格需在实际使用中观察。
- 新Build9尚未做用户设备真实麦克风/扬声器/蓝牙测试；用户确认的是旧Build8的手动发送能听到回复。模拟器产出PCM不等于真机音质验证。
- 发布IPA已检查CRC、版本/构建号、arm64设备平台、无FairPlay、隐私说明/manifest与许可，并确认不包含模拟发言按钮和测试开关。

## 工作方式与后续

Linux本机没有Xcode；设备编译与实际模拟器测试经GitHub Actions。模拟器启动曾慢，启动失败与产品测试失败要分开记录。焦点持续iOS26，不擅自恢复用户取消的旧长测试或iOS18任务。

后续先git status/log和交付清单。新应用改动再次交付递增构建号（当前9）。保留用户资料，不能擅自卸载、清空、变更Bundle ID、Keychain服务名、加密格式或迁移数据。没有后台跨窗口自动监控承诺；在当前工作期间跟进必要构建并交付产物。
