# PersonalAssistant-iOS · Build 11 交接

2026-10-26。最新交付为 **3.5.1（Build 11）**，伙伴聊天、上下文窗口和发送按钮光圈已完成构建及定向检查。

## 交付事实

- 应用构建提交：7ea79ee681646111664bee11379eb5c6d972d965；分支codex/companion-conversation-build11。后续文档提交不改变安装包。
- Release：https://github.com/3824yyds/PersonalAssistant-iOS/releases/tag/v3.5.1-build11
- IPA：https://github.com/3824yyds/PersonalAssistant-iOS/releases/download/v3.5.1-build11/PersonalAssistant-iOS-3.5.1-build11-unsigned.ipa
- 本地：/workspace/deliverables/build11-device/PersonalAssistant-iOS-3.5.1-build11-unsigned.ipa
- 大小：82,543,453字节；SHA256：fa05d5b110597b0ee89a59261c202fe447648f3eb003a94330e2e2fd033f1111。
- 设备构建与发布：https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40301346251，成功。
- 同源核心及iOS检查：https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40300948229，成功。
- 未签名iPhone arm64，最低iOS17，SDK iphoneos26.2；Bundle ID仍cn.local.assistant.ios。沿用原签名身份覆盖安装，不卸载、不清库、不改Keychain服务。
- PR3草稿：https://github.com/3824yyds/PersonalAssistant-iOS/pull/3，基于Build10分支供审阅；未合并main。

## 已交付功能

- 日常伙伴聊天改用DeepSeek Flash，固定女性外貌与身份，温柔/适度互损/贴吧老哥三档语气；支持当天暂时收敛。
- 明确取名、用户自己的称呼、偏好更正、撤销分别处理并写入加密资料。自然语言取名建议可由模型提出确认卡；首次升级可修复旧聊天中明确但漏存的名字。
- 按需查询当前公开信息和陌生热梗，保留实际来源；无结果、断流、截断、密钥、余额或网络失败提供真实错误及重试。连续复读最多修复一次。
- 每窗口完整对话预算48,000字符，不再悄悄裁成最近24条。80%提醒，满额阻止继续发送。预算包含当前对话及交接摘要，不等于供应商token上限。
- 蓝色发送箭头外围光圈按已记录用量顺时针点亮，80%橙色、满额红色；不是加载动画。精简后按新摘要实际用量回落。
- 分段精简后先预览和编辑，确认再开新窗口；取消、失败或原文变化不切换。旧窗口原文可查，名字、长期记忆和未发送草稿保留。摘要上限5,000字符，摘要有损，不能保证所有细节继续进入新对话。
- 原文总容量5,000条消息、200窗口、200记忆，容量满时需用户备份整理，不自动删除。
- 前台主动接话尊重草稿、编辑、弹窗、未回答问题、结束话题及冷却。后台主动和伙伴语音继续取消/暂缓；原助理功能保留。
- 225步模型备份保留、不再内置或用于日常伙伴聊天，包体降至约83MB。原始云盘语料和权重未更改。

## 验证与限制

- 167项核心测试通过；同源iOS26检查31项单元/输入法/模拟DeepSeek流与工具测试、11项伙伴UI场景全部通过。
- 已查看实际导出截图：83%橙色光圈、100%红圈、精简预览、保留草稿的新窗口及历史原文。
- 设备Release和本地下载IPA校验通过：arm64设备、版本11、SDK26、CRC、无FairPlay、无DEBUG模拟开关、无旧伙伴GGUF；本地SHA与CI、Release发布记录一致。
- UI运行记录包含系统UIHostingController视图层级警告，11项断言全部通过；尚未做用户iPhone真机安装与性能验证。
- 未用真实付费API做连续聊天质量验收。模拟协议测试及DEBUG页面数据不证明真实情商、热梗或长摘要语义质量；详见Docs/COMPANION_CHAT_EVAL.md。
- 伙伴聊天需要开启云端智能并配置DeepSeek API Key，按服务实际用量计费。发送当前窗口、已确认交接摘要和相关记忆，不发送整份笔记/账本/资料库。
- 早期Build11缺密钥UI断言失败，修正API Key读取错误提示后本次全部通过；早期包没有发布，/workspace/deliverables/build11-pre-context-device不是交付包。

用户已取消仅内部研究/必须私有仓库限制，授权公共仓库流程；不要重复询问。旧模型备份和Build10交付见Docs/HANDOFF_BUILD10.md。后续应用改动递增Build12。
