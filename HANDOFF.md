# PersonalAssistant-iOS · Build 15 交接

2026-10-27。最新交付为 **3.5.1（Build 15）**。应用源82646cc9255d767613aaf22d74674f995ab6f129；分支codex/companion-response-build15，草稿PR7基于Build14分支；未合并main。后续应用改动递增Build16。

## 交付事实

- Release：https://github.com/3824yyds/PersonalAssistant-iOS/releases/tag/v3.5.1-build15
- IPA：https://github.com/3824yyds/PersonalAssistant-iOS/releases/download/v3.5.1-build15/PersonalAssistant-iOS-3.5.1-build15-unsigned.ipa
- 本地最终包：/workspace/deliverables/build15-release-device/PersonalAssistant-iOS-3.5.1-build15-unsigned.ipa
- 大小108,166,831字节，SHA256 c45cbe9fad812013113806063cf4bbb62bf65b725015b90f2697849a1bb74d9c。本地CRC/arm64设备Mach-O/版本15/SDK26.2/Bundle ID/无FairPlay/无DEBUG夹具与旧GGUF检查通过，ci-verification.json单独保留；本地、CI、SHA256SUMS及Release资产digest/字节数一致，标签源也已核对。
- 同源检查40425520573、设备构建发布40425549640全部成功。标签v3.5.1-build15固定在已验收应用源82646cc9255d767613aaf22d74674f995ab6f129；随后文档提交不改变IPA或标签。
- 草稿PR7：https://github.com/3824yyds/PersonalAssistant-iOS/pull/7。Build14交接归档Docs/HANDOFF_BUILD14.md。

## 问题与修复

用户截图：助手问“真要拿‘大肥鱼’当我的名字？确认了我可就顶着它到处游了”，用户答“是的”却没有保存，后续天气和表情问题继续被取名错误拦截；用户另报回复比之前慢。

取名改为最近真实用户候选加直接的自我取名关系判断，确认与回执同事务保存。普通话题不开放取名工具；不执行未开放工具，不把第三方、引用或假设当取名。补存旧漏确认只在各自私聊开启时进行一次，新增可选confirmationRecoveryChecked；不覆盖已有名字/更名撤销，尊重后续取消。若最后还有未回答用户消息，只补资料而不添加遮住重试入口的系统回复。重试旧确认不重复追加原用户消息。

速度方面，私聊/群聊接通既有流式预览，140ms节流，只改临时UI状态；请求ID、锁定epoch、取消及组员切换保护晚到数据。预览过滤表情标记前缀和未验证发图回执；命名请求在确认卡准备好前不显示可能虚假改名的预览。最终正文/图片仍校验后一起加密保存。

本地工具已形成完整回复时省掉额外解释性模型请求：候选名字直接展示确认卡；图片带同轮正文或用户明确只要图可同轮完成。普通聊天仅选图无正文仍继续生成自然回应，联网消息仍完成来源证据整理。伙伴最多两轮工具处理；主聊天默认工具流程不变。没有用真实付费API做端到端速度基准，不能声称固定秒数/倍速，也不能把网络排队问题宣称为已解决。

## 验证事实与限制

- 205项核心、16张图片SHA/RGBA与编译资源、75项iOS单元、26项页面流程全部通过。服务模拟验证：流结束前已收到预览、完整最终文本、已完成本地结果的一轮请求、普通空正文的后续生成、搜索+表情仍等待最终天气答复、未完成SSE不提交、旧取名工具不影响天气、反复未授权调用的轮数上限。
- 已查看最终截图：新截图原样取名问句→是的→标题大肥鱼→天气自然澄清；旧是的+天气记录升级补存名字、重试原消息且不重复用户文本；实际抱抱图重复发送仍正常。页面对话为测试夹具，非真实模型对话评测。
- 首次设备编译发现流式闭包因多余await变成async，而接口要求同步MainActor回调；移除该await后同源重建，完整原生和页面检查通过，没有删除断言或增加执行时限。
- 运行资料与完整日志在/workspace/companion-build15-checks/final-ui，Release比对记录在release-verification.json，最终包与CI原始校验在build15-release-device。先前7b4ebed构建失败，不是交付源；最终源是82646cc。
- 仍无真实付费DeepSeek连续质量/端到端耗时评估，未完成用户iPhone、Face ID、系统PhotosPicker及性能验收。模型生成、排队、网络与检索仍会影响总耗时。后台主动、音色扩展或模型权重训练不在本版范围，旧训练备份保留。

## 安装要求

**从Build14或Build13更新请用原签名身份与相同Bundle ID覆盖安装，保留现有4位PIN和资料，无需卸载。** 加密封装沿用版本2，新增字段可选；旧Build12及更早长密码资料/备份仍不兼容。未签名iPhone arm64，最低iOS17，SDK26.2，Bundle ID cn.local.assistant.ios，沿用既有签名安装方式。

详细功能与校验见Docs/BUILD15_RELEASE.md、Docs/BUILD15_VERIFICATION.json。前版Build14最终包单独保留，不能混用其版本/校验值。
