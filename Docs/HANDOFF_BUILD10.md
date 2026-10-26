# PersonalAssistant-iOS · Build 10 交接

2026-10-26。最新交付为 **3.5.1（Build 10）**，从助理输入区＋进入独立纯文字伙伴页。

## 交付事实

- 应用构建提交：305c01a30f43c0e14b7ce4ba21d59825b8370dbb；分支codex/companion-build10。后续文档提交不改变安装包。
- Release：https://github.com/3824yyds/PersonalAssistant-iOS/releases/tag/v3.5.1-build10
- IPA：https://github.com/3824yyds/PersonalAssistant-iOS/releases/download/v3.5.1-build10/PersonalAssistant-iOS-3.5.1-build10-unsigned.ipa
- 本地：/workspace/deliverables/build10-device/PersonalAssistant-iOS-3.5.1-build10-unsigned.ipa
- 大小：1045859475字节；SHA256：3077868ca0a4e29e3d79a0375c9b83282726be2584e65520ea5a30a0c109d1e5。
- 设备构建与发布：https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40282236178
- 核心及iOS检查：https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40281913473
- 交付清单：/workspace/deliverables/build10-delivery-manifest.json。
- 未签名iPhone arm64，最低iOS17，SDK iphoneos26.2；Bundle ID仍cn.local.assistant.ios。沿用原签名身份覆盖安装，不卸载、不清库、不改Keychain服务。
- PR2草稿：https://github.com/3824yyds/PersonalAssistant-iOS/pull/2，基于原Build9分支供单独审阅；main尚未合并。

## 已交付功能

- 指定蓝发女性角色头像；热情、简短口语表达的人物指令；可查看和编辑外貌服装、名字与性格资料。
- 明确聊天取名先保存，再即时更新标题及输入提示，支持撤销，退出后重进仍保留。
- 偏好和明确“记住：…”保存到既有加密Document，支持查看、编辑、删除。明确记忆回问读实际事实和对话，防止225小模型混淆主体或编造回忆。
- 普通聊天使用冻结225步模型；前台主动接话尊重可见性、编辑、草稿、弹窗、忙碌状态和冷却，忽略后不连发。
- 需要当前公开信息时复用DeepSeek Flash搜索，保留伙伴身份、短句表达、实际来源，提供取消和失败重试；不上传全部记忆、历史、账本或笔记。
- 伙伴语音暂缓、后台主动取消；普通助理既有语音与Flash/Pro选择器保留。
- 统一native串行队列和全局取消ID，原本机模型不覆盖。IPA内置完整225步GGUF，无需导入。

## 验证及限制

- 134项核心测试通过；iOS26的14项单元/输入法/加密/模拟联网工具检查及3项伙伴页面操作通过。
- 设备Release编译与IPA检查通过：arm64设备平台、版本/构建号、SDK、CRC、无FairPlay、无模拟回复开关、完整模型大小与SHA256。本地下载IPA的整体SHA再核对一致。
- 未以用户真实API Key执行付费联网请求；未做用户iPhone真机安装、性能或全部聊天质量验证。不要把定向检查称作完整UI验收。
- 225权重未续训；CPU实际自由生成的记忆回问曾不可靠，故明确回问由事实层处理。开放式聊天质量仍受当前模型能力限制。
- 初次UI检查40279833414因容器标识覆盖子控件而失败，修正后以上最终检查通过；初次设备包40280384380不作为交付。

## 模型与发布范围

用户已明确取消仅内部研究/必须私有仓库限制，授权沿用原公共仓库流程。不要再次要求私有仓库；原始语料、私有Drive备份和API密钥仍不上传。

模型986048064字节，SHA256 07fcb0fdd9a9e116f3ddb0926a5f9059fc8f9e3369f6455b80397cab562c4f4f。12卷位于独立companion-model-225分支，固定提交4fa8c13439839c8a5b158626486f6ce1d2942f39；下载脚本逐卷及整体核验组装。原始云盘225/200未改。GitHub Release上传域认证受限已通过正常Git传输分卷解决；最终IPA由GitHub Actions原生token发布，公共Release下载成功。

当前Build10已经交付，下一轮应用修改需递增Build11。Linux无Xcode，继续用已注册GitHub Actions；不恢复旧的已取消全面UI审计。历史Build9交接在Docs/HANDOFF_BUILD9.md。
