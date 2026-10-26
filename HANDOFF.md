# Build 10 私有伙伴模式开发交接（未打包）

2026-10-26。此工作树位于 /workspace/PersonalAssistant-internal，分支 internal/companion-build10。当前用户已授权按确认的设计实现并交付安装包。

**当前没有新IPA，最后实际交付仍为Build9。** 本轮已接入源代码和本地检查，不等于完成iOS编译或界面测试。

## 已接入

- ＋ → 伙伴模式 → 独立纯文字页；指定女性人物头像、热情短句人设、自我形象与服装资料。
- 明确聊天取名事务保存后立即更新标题；可撤销、资料页编辑。不会把“我叫…”误当她的名字。
- 用户偏好与明确“记住：…”写入现有加密Document的companionResearch字段；可查、改、删；不改原格式和密钥服务。
- 名字、女性身份、外貌问答及明确记忆回问读取真实资料；闲聊使用冻结的225模型。实际CPU检查发现小模型可能混淆偏好主体和回忆，已用基于证据的查询及回归检查处理这些明确场景，不能声称小模型所有问题质量已验证。
- 前台主动接话仅本页active、无编辑/草稿/生成/弹层且安静30秒后考虑；10分钟冷却，忽略后不连发。后台主动仍取消、伙伴语音暂缓。
- 按需使用现有DeepSeek Flash工具链，保留身份/短句表达、实际来源、失败/取消/重试。联网不上传全部记忆/历史/账本/笔记。没有用真实用户API Key做付费联网检查。
- 统一LocalModel native串行队列及全局取消ID，独立选择伙伴GGUF，原本机模型不覆盖。
- 拟交付3.5.1 Build10，Bundle ID仍cn.local.assistant.ios。设备包必须附完整986048064字节Q4 GGUF，打包前及IPA内均检查SHA256。

## 本地验证

/workspace/companion-build10-checks 保存日志：完整核心134项通过；最后针对CompanionTests复查通过。Swift语法解析通过；脚本语法及最终模型SHA核对通过。语法解析不是iOS SDK类型检查或设备构建。

实际CPU模型三例输出在native-persona-smoke.json：普通疲惫聊天输出自然短句；原始自由生成记忆回问不可靠。随后增加明确记忆回问的Core事实检索层，并通过对应回归测试。未重新训练，未修改225/200原始权重。

## 构建阻塞及恢复步骤

当前GitHub连接不允许createRepository（Resource not accessible by integration / 403），PersonalAssistant-Internal仓库尚不可访问。已通过异步问题请用户创建3824yyds/PersonalAssistant-Internal私有仓库，并加入当前GitHub连接授权范围；尚未收到完成回复。Linux环境无Xcode，因此iOS编译与界面检查待此项补齐。不能把研究代码/权重推到现有公共PersonalAssistant-iOS仓库。

仓库授权补齐后，在本工作树运行：

    python3 Scripts/start_internal_build.py

脚本先核对仓库private=true才push本地已提交源码、上传冻结模型到私有Release，并启动internal-companion.yml。模型App/Resources/CompanionModel.gguf为本地完整GGUF的硬链接，已gitignore，不进入Git对象。构建流程先跑Core及iOS26定向界面/网络/加密测试，再编译带模型的设备IPA。继续跟进日志、修复、下载和核验IPA后，才能向用户交付。

没有签名密钥；沿用此前未签名IPA交付方式，并明确需使用原签名方式覆盖安装。不可卸载、清库、改Bundle ID或Keychain服务。历史Build9交接在Docs/HANDOFF_BUILD9.md。

## 空间处理

本地Docker VFS复制Swift工具链导致空间不足，失败运行未执行测试。已改用官方Swift6.0.3原生工具链 /workspace/swift6，完成核心与语法检查。为释放空间，清理了可重建的F16 GGUF、merged-hf合并分片、重组验证副本与原生两分片；原始base-config、checkpoint-225、最终完整Q4、LoRA和12个传输卷保留，云盘225/200未动。详见companion-final-225/reports/build10-intermediate-cleanup.txt。
