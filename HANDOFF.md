# PersonalAssistant-iOS · Build 16 交接

2026-10-27。最新已发布为 **3.5.1（Build 16）**。应用源 **5ad8000088b309eb7941e811c3a98c48ffad4699**；分支codex/natural-group-build16，草稿PR8基于Build15分支，未合并main。后续应用改动使用Build17。

## 交付事实

- Release：https://github.com/3824yyds/PersonalAssistant-iOS/releases/tag/v3.5.1-build16（ID425077274）。
- IPA：https://github.com/3824yyds/PersonalAssistant-iOS/releases/download/v3.5.1-build16/PersonalAssistant-iOS-3.5.1-build16-unsigned.ipa
- 本地包：/workspace/deliverables/build16-release-device/PersonalAssistant-iOS-3.5.1-build16-unsigned.ipa
- **108177329字节，SHA256 10174dc2b20371951c6006942219f0a59591e939b91da46464aac6d09c228591**。本地CRC、arm64设备Mach-O、版本16、SDK26.2、Bundle ID、无FairPlay/DEBUG夹具/旧GGUF检查通过。CI原始校验单独保留为ci-verification.json，与本地结果及SHA256SUMS一致。
- 同源检查40451122704、设备构建发布40451307886，最终均attempt2成功。标签v3.5.1-build16、Release target与上述已验证应用源一致；Release IPA的size/digest已核对一致。之后文档提交不改变IPA或标签。
- 设备最终artifact12712295828，ZIPsha732439cb759ff7120fadb1c0085d76f4d2001c62eb2126d2b8174a93a10d1c99；最终UI artifact12713516152，ZIPsha96cfa5ba8bb23ddff5cd6d6596abb16b2830c4e9665c8fdc8f5848e3263c8c2f。不要把旧attempt的同名artifact当成最终包。
- PR8：https://github.com/3824yyds/PersonalAssistant-iOS/pull/8。Build15交接归档Docs/HANDOFF_BUILD15.md。

## 修复内容

用户群聊截图出现“群发言者：female”“群成员「大肥鱼」（female）说”等重复文字，还要求移除@，自动理解自然称呼与指代。

旧群聊把身份拼进正文、把其他AI改作user角色，模型复述后又在后续轮次重复叠加。现在群聊用JSON独立记录真实发言者、正文、本轮用户消息标识，保留原用户与同轮伙伴回复的实际顺序，其他AI不会冒作真人用户。清理新回复的预览/最终保存，以及旧消息的显示、复制、引用显示、请求副本和历史窗口；原始记录、引用快照和窗口索引不重写。只有标签而无正文的候选不保存，最多一次重整，不伪造成功。

移除@选择栏及相关引导。明确称呼、简单集体消息或明确引用可直接判断；含限定、否定、转向、顺序和间接指代的句子不走简单名字捷径，使用一次无工具、关闭思考、最多192输出token的Flash判断，严格校验成员集合/去重/顺序后保存计划。原用户消息先以可选routingPending保存，失败与取消后可重试；计划确认后不重复推断，已答成员不再重复发言。每人每轮最多一条，无自主无限互聊。

发言判断仅取最近12条、每条最多800字的群记录；真正回答仍使用完整当前窗口与已确认摘要，不缩短既有48,000字符窗口。群内不带私聊记忆与经历，各自身份、形象、表情库保持独立。群聊摘要保留发言归属，群内习惯仅影响对应成员。新增routingPending可选，不改变加密封装版本2。

页面回归另发现返回私聊时等待动画完成的超时。Session.visible/active改为发布状态，头像动画仅在当前页可见且活动时运行，离页或后台停止帧刷新，重新进入恢复，继续尊重个人开关及减少动态效果设置。Build15取名确认、流式预览、表情发送和四位PIN保留。

## 验证与限制

- 213项核心、16图SHA/RGBA资源、80项原生（55网络+3输入法+18加密+4PIN附件）、29项伙伴页面全部通过。最终原生2.42秒、页面1206.98秒，TEST SUCCEEDED，没有执行超时或“动画完成通知未收到”警告。
- 最终jobs：focused-ios122025287088、core122025325713、assets122025289222，设备122025304260。核心/资源成功结果在同源重跑中沿用，源码始终5ad8000；原生与29页面完整重跑，没有跳过断言或增加时限。
- 已查看最终模拟器截图：7F05D06E…两人自然介绍；147A9313…旧标记清理、自然叫名与指代；99363B0D…自动回复引用作者。正确头像/昵称在气泡外，无@栏和程序前缀。图片对应网络模拟数据，不是付费模型质量评测。
- 日志、截图和验证资料：/workspace/companion-build16-checks/final-ui；release-verification.json；最终包目录含CI原始校验、checksum与delivery-manifest.json。
- 未做真实付费API连续质量、端到端耗时、实体iPhone或Face ID验收。复杂指代仍可能需要澄清，语义判断有额外模型用量；不能宣称完全不会理解错误或固定秒回。后台主动、音色和训练不在本次范围。

早期4d/4ba候选与运行未交付；4ba曾在两个既有私聊流程遇到XCTest动画通知超时。补上离页头像暂停后，5ad首轮29个页面功能断言全部通过，但首条取消重试用例仍发生一次动画通知超时，Xcode判整轮失败；同一份5ad代码重跑后全部通过。旧诊断保留在first-ui与visibility-attempt1-ui。未提高时限、跳过用例或绕过发布门禁。早期未发布包删除后仅留meta/log，实际已交付Build13/14/15包未动。40b562…是5ad首轮候选SHA，最终交付必须用上面的10174d…。

## 安装

**从Build13/14/15更新，用原签名身份及相同Bundle ID覆盖安装，保留四位PIN和资料，无需卸载。** iPhone arm64未签名，最低iOS17，SDK26.2，Bundle ID cn.local.assistant.ios。旧Build12及更早长密码资料/备份仍不兼容，不要把旧版卸载要求套到当前升级。

详见Docs/BUILD16_RELEASE.md与Docs/BUILD16_VERIFICATION.json。不要重启已搁置的语音、宣传视频或训练任务；男生性格以用户最新“温柔稳重、善于安慰人”为准。
