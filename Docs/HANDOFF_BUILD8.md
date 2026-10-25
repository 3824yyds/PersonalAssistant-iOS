# PersonalAssistant-iOS · Build 8 交接

2026-10-25 UTC。最新合并交付为 **3.5.1（Build 8）**，已经设备编译、下载和文件校验。历史 Build 6 交接保存在 `Docs/HANDOFF_BUILD6.md`，旧包与旧等待状态不代表当前状态。

## 实际源码和交付物

- 当前分支：`codex/fullscreen-notes-model-slider`；PR：https://github.com/3824yyds/PersonalAssistant-iOS/pull/1 。本轮应用修改位于该分支，main 尚未合并。
- 安装包源码提交：`3ffe94f15cc3a02dc3a0f17370a5f264eee37256`。之后的交接文档和工作流整理不会更新同一 IPA。
- 最终打包：https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40177508702
- 最终 artifact：https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40177508702/artifacts/12592848080
- IPA：`/workspace/deliverables/build8-device/PersonalAssistant-iOS-3.5.1-build8-unsigned.ipa`；80,596,113 字节。
- SHA-256：`e649867820034cf23cd074e4ca394c4312063a2774e6ca778962cf4995c2cb49`。
- 安装 ZIP：`/workspace/deliverables/PersonalAssistant-iOS-3.5.1-build8-Install.zip`。
- 当前事实清单：`/workspace/deliverables/build8-delivery-manifest.json`。
- 未签名 iPhone arm64、SDK iphoneos26.2、最低 iOS 17.0。使用原签名方式覆盖安装；没有真机签名安装成功的验证。
- **40175158026、40175914198、40176228705、40177034920 都是被替代的中间 Build 8，不要把这些当最终包。**

## 用户最终要求和已做内容

1. 笔记独立全屏编辑，黄色 ✅ 保存成功后退出，返回放弃本次修改并清理当前草稿；保存失败留在编辑页。
2. 模型入口在输入框里，点击在输入区原位展开，只显示 Flash / Pro，左右滑动和点按切换。展开后保留键盘、原输入和图片草稿，名称旁没有 >。
3. 用户报告语音输入下“按住说话”及底色与选择器重叠；修复为模型选择器展开时移除整块语音 Text/背景/手势，收起恢复。
4. 用户指出语音通话此前只说明方案没有实现，要求和重叠修复做成同一版。Build 8 已加入全屏语音对话，入口为蓝色波形按钮或 ＋ → 语音通话。系统离线普通话识别、停顿发送、沿用现有 DeepSeek / 本机回复、系统朗读、自动恢复收听、字幕、静音、点按球体打断、文字记录和结束。后台、音频中断或耳机断连暂停，返回后手动继续。
5. 用户强调避免再次漏需求和漏模式检查。交付清单需明确区分实现、界面验证和真机验证，不能仅给方案却声称功能已完成。

## 关键实现约束

- `ConversationView.composerInput` 的语音纯 SwiftUI 分支使用条件构建，在 modelMenu 为 true 时用 42pt 透明占位。只设 opacity=0 时旧按钮仍可能保留在无障碍层，不要退回这种处理。
- 文字输入使用常驻 `ComposingTextInput`，通过 concealed 清除文字/光标颜色保护原生输入法焦点。不要移除/禁用整个 UIKit 输入宿主，不要改回未注册的 FocusState。
- `VoiceCallSession.swift` 轮流进行系统识别与系统朗读，避免将扬声器回复再次送入麦克风。静音会停止收听；结束、后台或中断会取消请求和音频任务。
- `VoiceCallView.swift` 等待本轮实际 `store.activeTask` 结束后读取同一 answer ID 朗读，避免依赖 busy 的瞬时界面变化而漏掉快速回复。晚到回调需检查任务取消和通话状态。
- 语音输入以文字传给已有回复/工具路径，原文字/图片草稿保留；聊天真实保存规则、金额和账户校验沿用现有代码。
- 当前不是新接入的原生实时音频模型：采用识别 → 当前模型 → 朗读；每轮有等待，支持点按打断。实际麦克风、音质、蓝牙和延迟尚未真机验证。系统离线中文资源和权限不可用时显示错误，不假装已连接。
- 使用现有 Keychain DeepSeek Key；没有在云端读取用户真 Key 或做付费模型调用。Release 不包含模拟发言按钮或语音测试开关。

## 准确验证状态

- 40176212025：源码 26679a5，键盘保留/模型双向滑动通过；语音界面、静音、模拟一句真实本地回复衔接、点按打断、后台暂停/恢复和退出后输入通过。整次运行因为旧语音按钮仍在无障碍层的断言失败而是 failure，不能标成整次 success。
- 40177490166：源码 3ffe94f，修正后的语音输入层移除/恢复专项复查通过。最新设备 IPA 同源码。
- 相关 3 个场景按上述运行分别通过；不是重新完成全量 UI 验证。`complete_UI_validation_verified=false`。
- 语音 UI 夹具不启动真实麦克风/朗读，不调用付费 API。模拟识别输入复用实际本地回答及历史保存路径，并不能证明物理音频质量或真实云端模型理解。
- Build 7 先前笔记保存/放弃等专项 40172291552 属于历史证据。不要恢复用户已取消的 Build 6 长验证，只按新任务需要检查 iOS 26。

## 环境和后续

Linux 本机没有 Xcode/交互式 iPhone 模拟器，实际设备编译和模拟器操作通过 GitHub Actions。模拟器冷启动可能卡住，最多重试一次；启动失败和产品测试失败要区分。

后续先检查 git status / log 和上述清单，再处理新需求。保留旧资料，不能擅自卸载、清空、换 Bundle ID、钥匙串服务名或加密格式。新应用改动再次交付时递增构建号；当前8。
