# Build 10 伙伴模式：正在构建

2026-10-26。用户已明确取消“仅内部研究/必须私有仓库”的限制，并授权沿用原仓库与GitHub Actions流程尽快交付。不要再要求创建或授权私有仓库。

本次从 /workspace/PersonalAssistant-internal 工作树发布至原3824yyds/PersonalAssistant-iOS的独立伙伴分支。没有修改main、原始训练检查点、原用户数据、Bundle ID或Keychain服务名。原始语料、API密钥不上传。伴随安装包使用的冻结225步Q4模型放在独立companion-model-225分卷分支，不进入应用代码分支。原GitHub Release上传域名返回401，所以采用已授权Git传输，12卷全部上传成功。

当前功能代码包含：＋进入独立纯文字伙伴页；指定女性人物头像、热情短句人设、固定外貌服装资料；聊天命名即保存并更新标题，可撤销和编辑；加密记忆的增改删与明确记忆回问；前台低频主动接话；按需DeepSeek Flash搜索及真实来源/失败/取消/重试。伙伴语音暂缓，后台主动取消，原普通聊天语音保留。

本地核心134项通过，最终伙伴13项通过；修改Swift语法检查通过；模型986048064字节、SHA256 07fcb0fdd9a9e116f3ddb0926a5f9059fc8f9e3369f6455b80397cab562c4f4f 核对通过。实际CPU试聊暴露了小模型记忆回问不可靠，明确回问已改用实际保存的事实与历史直接回复。没有声称真机质量、iOS界面或设备编译已通过。

复用已注册流程：note-model-ui.yml运行Core及iOS26伙伴/键盘/联网/加密定向检查，ios-package.yml并行做带冻结模型的arm64设备包。模型分卷固定提交为4fa8c13439839c8a5b158626486f6ce1d2942f39，Scripts/download_companion_model.py按单卷和最终SHA验证并组装成CompanionModel.gguf。设备打包前及IPA内均核对完整SHA。拟交付3.5.1 Build10、cn.local.assistant.ios、iOS17最低、iOS26SDK；未签名，沿用原方式覆盖安装，不卸载或清库。

新IPA尚未生成。构建后必须跟进日志和修复、核对IPA平台/版本/模型/CRC/无测试夹具，再交付实际下载链接。旧的Build9交付记录保存在Docs/HANDOFF_BUILD9.md。
