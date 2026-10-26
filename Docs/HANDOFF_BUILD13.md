# PersonalAssistant-iOS · Build 13 交接

2026-10-26。最新交付为 **3.5.1（Build 13）**。应用源提交9cc77ab22b1939b056e41f5498d7be82ee9a52e4；分支codex/companion-composer-build13，草稿PR5基于Build12分支；未合并main。

## 交付事实

- Release：https://github.com/3824yyds/PersonalAssistant-iOS/releases/tag/v3.5.1-build13
- IPA：https://github.com/3824yyds/PersonalAssistant-iOS/releases/download/v3.5.1-build13/PersonalAssistant-iOS-3.5.1-build13-unsigned.ipa
- 本地最终包：/workspace/deliverables/build13-release-device/PersonalAssistant-iOS-3.5.1-build13-unsigned.ipa
- 大小96,788,818字节，SHA256 dd80479027ef7ee25fbb2cd1b91c9dc444a1b11322c77817ab9e6b9f771e0064。本地CRC/arm64设备Mach-O/版本13/SDK26/BundleID/无FairPlay/无DEBUG夹具与旧GGUF检查通过，CI验证文件已单独保留，SHA和字节数与Release资产记录一致。
- 同源检查40338418750、设备构建发布40357240349均成功，标签v3.5.1-build13固定在已验收应用源9cc77ab22b1939b056e41f5498d7be82ee9a52e4；随后交接文档提交不改变IPA或标签。
- 草稿PR5：https://github.com/3824yyds/PersonalAssistant-iOS/pull/5。Build12交接归档Docs/HANDOFF_BUILD12.md，不能沿用其中旧安装指引。后续应用变更递增Build14。

## 本次功能

- 表情包从全屏弹页改为输入框下方展开的底部面板，与系统键盘切换，聊天和草稿留在原页。
- “我的”表情允许原生PhotosPicker导入照片，填写名称与含义、选择是否允许伙伴发送。最长512像素、每张256KiB内、重新编码去掉元数据，保留透明PNG。最多32张（含为历史聊天归档的图片），存入既有加密资料库，总32MiB上限。AI只收到名称和含义，不收到照片像素；不能声称任意照片视觉识别。
- 移除用过的自定义表情只归档，聊天图片仍在；未用过的可物理移除。点表情发送保留文字草稿，保存失败保留编辑表单。自定义表情不替代人物头像。
- 逐张独立绘制四张恶搞表情“绷不住了、吃瓜、我裂开了、就这？”，合计十张内置表情。原图保留/workspace/generated_images；副本与来源SHA在资源目录/Docs/COMPANION_STICKERS.json。沿用频率、重复、温柔与倾诉场景限制。
- 长按指定消息“回复”，输入区展示可取消引用，发送后保存原发言者和最多800字快照。引用、表情含义计入上下文光圈、历史和精简。失败重试沿用原引用、不重复添加用户消息；引用旧取名/记忆指令不执行旧操作，带引用轮关闭自动取名工具；搜索保护引用中的私人长号码。
- 顶部头像轻呼吸、摇摆，忙时显示思考点，最近一条回复有内置表情则切换对应静态神态。无额外模型请求。系统减少动态效果、后台及打开面板时暂停，个人资料可关闭。轻量SwiftUI动效，不是Live2D、真实眨眼或口型绑定。
- 资料库改为恰好4位ASCII数字PIN，保留前导零、PBKDF2-SHA256六十万次/AES-GCM和错误尝试冷却；新加密头版本2。创建、解锁、备份验证统一规则。无资料库的新安装清除遗留钥匙串中的失败次数和生物密钥，不自动删除旧文件或DeepSeek密钥。

## 安装要求（用户已明确授权）

用户明确要求：先卸载原版再安装，不兼容原12位/长密码资料。旧资料库和旧备份不兼容新版，无迁移；不能沿用Build12交接中的“不卸载/覆盖安装”指引。新安装自行设置4位PIN，0426仅为测试夹具，非默认PIN。未签名iPhone arm64，最低iOS17，SDK26.2，Bundle ID cn.local.assistant.ios；沿用既有用户签名安装方式。

## 验证事实与限制

- 189项核心、十张原图SHA/RGBA及设备编译资源检查已通过。同源40338418750的61项iOS单元和18项UI全部通过；设备构建与发布40357240349成功。
- UI检查40332552904首轮于模拟器bootstatus超时，尚未运行到应用；失败原始日志存/workspace/companion-build13-checks/boot-failure.log。原设备工作流40332821613正确拒绝发布；同源重跑，应用代码没有为基础设施故障修改。
- 首次应用UI检查有两处标识被父容器继承覆盖，按钮仍显示但自动化无法独立定位。已为引用与表情面板设置独立可访问容器，原测试未删除或削弱，最终全套通过。
- 已查看最终截图：底部内置/我的表情面板、自定义表情移除后历史原图、指定旧消息引用、取消引用保留草稿、新窗口摘要和头像表情切换。
- 原生PhotosPicker的Release入口存在；自动化导入使用DEBUG编辑页夹具，不代表测试了系统相册选取。ImageIO缩放/透明/元数据和加密恢复另有原生单元验证。
- 无用户真实付费DeepSeek凭据，模拟协议与DEBUG夹具不能证明实际情商、引用理解、表情语义和emoji/反讽生成质量；未完成用户iPhone安装、Face ID和性能验收。
- 仍需云端智能及DeepSeek Key，按实际API用量计费；未增加外部记忆服务、语音、后台主动、模型训练或更改旧225/200权重备份。
