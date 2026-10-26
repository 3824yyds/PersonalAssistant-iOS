# PersonalAssistant-iOS · Build 12 交接

2026-10-26。最新交付为 **3.5.1（Build 12）**，六张角色表情包、emoji语境指引和多轮取名修复已发布。

## 交付事实

- 应用源提交：08e76e7c412ea6261780b304b6b4668cba29197b；分支codex/companion-stickers-build12。之后仅文档提交，不改变IPA或Release标签。
- Release：https://github.com/3824yyds/PersonalAssistant-iOS/releases/tag/v3.5.1-build12
- IPA：https://github.com/3824yyds/PersonalAssistant-iOS/releases/download/v3.5.1-build12/PersonalAssistant-iOS-3.5.1-build12-unsigned.ipa
- 本地：/workspace/deliverables/build12-device/PersonalAssistant-iOS-3.5.1-build12-unsigned.ipa
- 大小92,181,107字节，SHA256 b6a40625d422fe6a34e00b74a02416b5589accf6bc74aaec4f6dd16a86704aac。
- 同源检查40323257996、设备构建与发布40323476490均成功。
- PR4草稿：https://github.com/3824yyds/PersonalAssistant-iOS/pull/4，基于Build11分支；未合并main。
- 未签名iPhone arm64，最低iOS17，SDK iphoneos26.2；Bundle ID cn.local.assistant.ios。沿用原签名身份覆盖安装，不卸载、不清库、不改变Keychain服务。

## 新增与修复

- 按既有女性蓝发头像用image_gen逐张独立绘制六张透明PNG：开心、抱抱、疑惑、无语、得意、晚安。原始生成图保留/workspace/generated_images，副本进入Assets.xcassets；Docs/COMPANION_STICKERS.json记录来源文件名和SHA。没有切图或叠加表情替代逐张生成。
- 每张有固定语义ID、画面与适用场景。DeepSeek通过send_companion_sticker选择，最多一张，限制连发/重复/不适当调侃；完整文字回复成功后才一起保存。关闭自动表情、温柔语气和前台主动场景受相应限制，用户仍能发送本套表情。
- 输入区笑脸面板点图发送、保留文字草稿；图片ID随加密聊天和历史窗口保存，语义进入上下文、字符预算与精简证据。API只接收语义文本，不为每次聊天实时绘图。
- emoji组合、肤色、ZWJ和旗帜序列保持原文；提示词结合中文反讽/无奈/夸张语境理解。取名邀请后的emoji或带emoji的简单附和不自动变成名字；明确“以后叫你🐟”仍能取名。
- 可能带反讽的emoji不自动提取长期偏好；咖啡☕️等装饰emoji不阻止后续偏好更正与撤销。这不是模型权重训练，也不是每段聊天都会自动成为长期记忆。
- 修复“大肥鱼→名字→是叫我‘大肥鱼’对吧→对的”流程：支持紧邻用户候选的澄清引用、有用户依据的普通确认问句及真正的候选状态；确认后保存并更新标题，不使用模型编造的名字或无关旧话题。
- 回归发现精简后新窗口已保存，但LazyVStack偶尔沿用旧长窗口滚动位置，隐藏摘要。现按窗口ID重建滚动布局；待回复提示和重试严格限定当前窗口，旧原文保留。原有UI断言和新加的残留提示断言均通过。
- Build11完整窗口、48,000字符上限/光圈、精简预览、人物和记忆、搜索、语气保留；伙伴语音暂缓、后台主动取消，未新增外部记忆云服务或SDK。

## 验证与限制

- 最终源181项核心、六张原图SHA/RGBA校验、编译Assets.car完整性全部通过；33项服务+3项IME=36项iOS单元、14项UI全部通过。
- 已查看最终导出截图：新窗口摘要/草稿、历史原文、表情收发与取名标题。之前失败场景修复后通过，未跳过该测试。
- 下载最终设备IPA，原CI验证文件单独保留；本地CRC、设备arm64/SDK26/版本12/BundleID、无FairPlay、无DEBUG夹具及无旧伙伴GGUF检查通过。整体SHA与CI及Release发布记录一致。
- 没有用户真实DeepSeek付费凭据，模拟协议和DEBUG页面不能证明真实情商、emoji/反讽/表情选择和摘要语义全部正确；未做用户iPhone安装或性能验证。见Docs/COMPANION_CHAT_EVAL.md。
- 仍需原有云端智能和DeepSeek Key，按实际API用量计费。图片随包提供；不上传整份资料库、笔记或账本。
- 前一b1d源全量检查36单元+13/14UI通过，唯一精简窗口显示失败阻止发布；旧包保留build12-pre-scroll-device，绝不能作为当前交付。其他取消的中间检查也不算最终验收。

用户已授权公共仓库和既有发布流程，不重复要求仅内部研究/私有化。模型原225/200云盘及旧权重备份未更改。Build11交接归档Docs/HANDOFF_BUILD11.md。后续应用更改递增Build13。
