# PersonalAssistant-iOS · Build 17 交接

2026-11-01。应用源 **b3cdbaf557cc72655825fdb5f432de195c8af676**；分支codex/companion-voice-build17，草稿PR9基于codex/natural-group-build16，未合并main。后续应用改动使用Build18。

## 功能与配置

两位伙伴新增文字/语音/语音和文字回复。右上角「… → 语音回复」配置。北京地域百炼qwen3-tts-flash官方接口；默认女声Cherry芊悦、男声Ethan晨煦；另有固定声音可选，播放语速0.8至1.2倍。自动播放默认关闭。文字先独立保存，语音生成不阻塞下一轮，群聊按真实发言者分配音色、串行合成播放。正文可展开，失败保留文字且单独重试语音；旧消息可长按语音播放。

用户已明确不试听、要安装包；用户没有语音服务账号。官方免费演示无法作为App的持续后端，本版没有共享密钥、演示爬取或系统朗读替代。**实际自然语音需要用户自己的百炼账号/北京API Key与额度；免费额度有条件及有效期。** 密钥在本机Keychain，DeepSeek仍负责文字聊天，与TTS密钥分开。没有真实服务账号，未调用真实付费TTS，未做实体iPhone、人声自然度或真实网络延迟验收。自动化使用DEBUG隔离的静音WAV验证解码、播放器、缓存和UI，不能当真人试听。

语音仅发送当前回复的朗读文本，不发送整段历史记忆。Markdown、引用、网址和emoji去除后按标点切分，每块最多450Unicode标量，总量1800，超限明确保留文字，不截断伪成功。音频URL官方域名白名单、HTTPS、不重定向、下载不带Key、8MB上限及WAV/播放器验证。AES-GCM独立缓存64MB/100项，cacheID带作用域/消息/角色/音色/文本并绑定AAD；不占32MB资料库、不备份，可再生成。换音色会新用量，调播放速度不重新生成。

离页、后台、锁定、耳机拔出或中断时停止。CompanionPlaybackAudioSession仅释放自己成功启用的音频会话，空闲关闭不干扰其他音频；Session.close幂等、无变化不重复发布状态。返回按钮保留玻璃外观，停用离页时的交互玻璃变形。保留头像动态、表情、自传照片、回复引用、自然群聊路由、48K字符窗口与环形显示。

## 安装与原偏好

iPhone arm64未签名IPA，iOS17起，SDK26.2，Bundle ID cn.local.assistant.ios。**使用原签名身份和相同Bundle ID覆盖安装Build13至16，保留四位PIN和资料，不要卸载。** 未改封装v2、PIN、资料库或备份迁移格式。

女伙伴温暖热情、会玩梗；男伙伴以用户最新“温柔稳重、善于安慰人”为准。无后台主动消息，不重启训练、宣传视频或实时通话。用户取消内部研究限制，不重新添加。Flash/Pro在输入区选择，标题不显示Flash·文字伙伴。各私聊记忆隔离，群内只用群共享上下文。

## 早期候选与诊断记录

旧580候选有父视图AX标识覆盖子按钮问题；去除父标识后四个新语音流程两轮通过。D606两轮分别遇到旧私聊/旧群聊离页动画通知超时，各89原生与其余页面通过，但两轮整体失败且门禁阻止发布，均不是交付包。B3补上音频会话所有权、幂等退出、无变化不发布与返回玻璃动画调整，并把两条超时导航回归一起纳入第一阶段。未增加时限、跳过断言或缩减覆盖。B3总33页面分6+27两阶段；原生91（80既有+9语音+2音频会话所有权），核心219、表情资源16。以下最终交付只采用同源完整成功的记录。

B3首轮第一阶段6项页面全部通过（284.529秒）、91项原生通过（3.099秒），后27项页面的26项通过；表情包/草稿/键盘已通过断言后，在返回伙伴列表时又发生一次动画通知超时。整轮失败，发布门禁生效。随后按原B3代码重跑完整检查，未修改测试、执行时限或应用源。同一份B3代码重跑后整套通过，记录见下。

## 最终交付与验证

最新已发布3.5.1（Build17），Release ID430581343：[下载页](https://github.com/3824yyds/PersonalAssistant-iOS/releases/tag/v3.5.1-build17)。[IPA](https://github.com/3824yyds/PersonalAssistant-iOS/releases/download/v3.5.1-build17/PersonalAssistant-iOS-3.5.1-build17-unsigned.ipa)，108305757字节，SHA256 **f6273db34b3f36ec99a120a519e492950b48f5c2e4403e5bda721794e1fc1c36**。本地包在/workspace/deliverables/build17-release-device。CI原始校验、独立本地校验和SHA256SUMS一致；设备arm64、版本17、SDK26.2、Bundle ID、无FairPlay/DEBUG夹具/旧GGUF检查通过。Release目标、标签和IPA附件digest/size都已核对，与应用源B3一致；后续文档提交不改变标签或安装包。

同源检查41302401790及设备发布41302534076最终均attempt2成功。UI job124845702963：第一阶段6项257.254秒，第二阶段91原生2.690秒及27页面1078.672秒，全部通过，无执行超时或动画通知警告。核心219、16张表情资源的同源成功结果沿用，逻辑job124845704146/124845737596。总33个不同UI用例，无删除断言或提高时限。设备job124845710096。

最终设备artifact13082448581，ZIPsha5099f8ccbe138cce3a34bb5b4a15e7980c6a271d9236dcb655ee2822bf7dafdd；UI artifact13084316059，ZIPsha42645424686133f7d558617bb61be4ca7ebc889e71223ebd8d95c294938306b2。日志和截图在/workspace/companion-build17-checks/final-ui；summary.json逐项校验6+27与91。已看私聊文字展开、未配置账号入口、语音失败保留文字、群聊女声结束后男声播放的最终模拟器截图。静音测试WAV不代表实际人声质量。

草稿PR9：https://github.com/3824yyds/PersonalAssistant-iOS/pull/9，未合并main。Build16交接已归档Docs/HANDOFF_BUILD16.md。详见Docs/BUILD17_RELEASE.md、Docs/BUILD17_VERIFICATION.json与Docs/COMPANION_VOICE_SETUP.md。旧未发布候选仅留诊断元数据，不能当最终交付；既有已交付Build13至16安装包保留。后续应用改动使用Build18。
