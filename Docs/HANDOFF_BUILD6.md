# 新窗口交接：PersonalAssistant-iOS · Build 6

更新时间：2026-10-25 UTC。新窗口请先读本文件，再看具体任务。

## 1. 当前结论与用户最新要求

**Build 6 安装包已经生成、下载校验，并已把下载链接交给用户。当前没有“等待打包”的未完成任务。**

用户最后要求：

1. 后续聚焦 **iOS 26**，不用再做 iOS 18 验证。
2. 明确说“**不用做那两项了，直接生成好安装包，马上给我下载链接**”，指停止当时剩余的 iOS 26 主流程/专项与巡检两组任务，改为直接打包。
3. 已按此执行。**不能声称最新构建的完整 iOS 26 UI 验证已全部通过，也不要未经新任务需要就恢复这次已取消的两组验证。**
4. 当前只是写交接文件。不要因此重新构建、改产品、升版本或迁移数据。

用户很在意执行连续性，反感“追问一次才检查一次”。任务需要构建时，应在当前工作期间跟进日志、处理失败并交付实际产物；不能只派发工作流就结束回复并承诺跨窗口自动监控。GitHub Actions 会在后台运行，但不等于模型会在结束回复后持续读取日志和修复问题。

## 2. 仓库与交付版本

- 工作区：`/workspace/PersonalAssistant-iOS`，分支 `main`。
- 公开仓库：https://github.com/3824yyds/PersonalAssistant-iOS
- 技术栈：原生 SwiftUI / UIKit / PencilKit，Swift 核心库；本机加密资料库；llama.cpp + Metal；DeepSeek 云端接口。
- 已交付应用：**3.5.1 (6)**。
- **安装包构建提交**：`4d8ddb74f2fbdf344ac57156abfe18be4db9de62`。
- 本交接文件是之后的纯文档提交，不代表安装包又更新了。继续开发前先运行 `git status --short`、`git log -5 --oneline`。
- Bundle ID：`cn.local.assistant.ios`。当前包最低系统版本仍为 **17.0**；用户只要求把验证重点放在 iOS 26，没有要求修改最低系统版本。
- 不要擅自更改应用标识、钥匙串服务名或加密格式，以免影响旧资料。

## 3. 已交付安装包与校验信息

成功的**直接打包**工作流：

https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40150071862

GitHub 安装包产物（需登录 GitHub；保留期14天，过期后需重新手动打包）：

https://github.com/3824yyds/PersonalAssistant-iOS/actions/runs/40150071862/artifacts/12581412855

本机文件：

| 文件 | 位置 |
|---|---|
| 原始 IPA | `/workspace/deliverables/build6-device/PersonalAssistant-iOS-3.5.1-build6-unsigned.ipa` |
| 安装包 ZIP，含 IPA、校验与说明 | `/workspace/deliverables/PersonalAssistant-iOS-3.5.1-build6-Install.zip` |
| 原始 GitHub 产物 ZIP | `/workspace/deliverables/PersonalAssistant-iOS-3.5.1-build6-device.zip` |
| 本轮本地校验结果 | `/workspace/deliverables/PersonalAssistant-iOS-3.5.1-build6-VERIFICATION.json` |
| 最终交付清单，当前事实来源 | `/workspace/deliverables/build6-delivery-manifest.json` |
| 设备编译日志 | `/workspace/deliverables/build6-device/device-build.log` |

IPA 大小：**80,510,747 字节**。

IPA SHA-256：

```text
e5b4f6aced79b0e5d03f46e225a3891bdc944695cd6e35943fa36d71baed3741
```

安装 ZIP SHA-256：

```text
a6410b9ad7522e57a4ade058cdce061a5aa1718ab067882aee1530e5929306e2
```

已确认：真实 iOS 设备 arm64 包，SDK `iphoneos26.2`，版本3.5.1/Build6；未签名、无 App Store FairPlay 加密；ZIP CRC与SHA-256正确；隐私说明和开源许可存在；Release二进制不含 UI 测试夹具开关。它不是模拟器包。用户仍需用原来的签名方式安装，不能把“构建成功”描述成“已在用户真机安装成功”。

用户已经收到原始 IPA 本机链接和 GitHub 备用链接。若新窗口文件不在，应先查仓库和上述 GitHub 产物，不要假装本机路径仍有效。

## 4. 用户授权与产品偏好

用户先要求像用户一样完整巡检，先提交优化建议、同意后才改；之后明确回复“**优化方式按你的建议来做**”。报告 F1–F5 和 F6 容量提示已经实施；附件独立存储涉及旧资料迁移，原建议是另行评估，**没有实施迁移**。

需要保留的交互：

- 笔记采用 iPhone 备忘录风格，支持清单、表格、图片/文件、手绘、分组、搜索、置顶、归档、最近删除与恢复。
- AI 润色、摘要、要点、会议纪要、行动清单等，结果和“采用”按钮留在原编辑页，不再弹独立采纳页。
- 骨架占位按实际文字布局测量行数，不用固定行数。
- 各界面顶部、底部不要出现额外的不透明长方形底框；保留浮动胶囊/玻璃控件。
- AI聊天独立页面，有返回键；返回键与模型菜单分开；财务咨询底部切换，顶部不重复显示“财务咨询”。
- 蓝白云雾球适中、持续变幻，速度已加快；问候语进入时变化。
- 模型菜单去掉“刷新可用模型”，勾选在模型右侧，名称不折行。云端设置页仍可刷新模型。
- 图片上传入口仅 DeepSeek Flash 显示，其他模型隐藏；不要扩大到未确认支持图片的模型。
- 聊天可真实创建笔记、实际收入/支出和提醒，显示已保存回执，可打开修改；不能只是让用户复制，也不能未经实际保存就声称成功。
- 借款到账及归还本金不当作普通收入/消费；利息和费用单独计入支出。贷款和提醒自动联动。
- 银行卡 Visa 等卡组织采用统一图标；展开/收起卡片动画已有优化。

## 5. Build 6 已做的主要修改

### 笔记与输入

- 黄色完成按钮保存成功后返回列表；失败保留编辑器与输入。
- 隐藏照片和手绘下方的文件名小字，保留附件数据、预览、编辑与其他文件名称。
- `NoteRichText.swift` 组词期间不回写文本/RTF，保护中文输入法 `markedTextRange`。
- 聊天使用 `ComposingTextInput.swift` 的 UIKit UITextView，组词期间不覆盖原生缓冲；发送前结束输入并提交候选词。
- 聊天焦点使用普通 `@State Bool` 与手动 Binding，**不要退回未注册的 `@FocusState`**，此前这会导致失焦。
- 打开历史、设置、回执、相册、模型菜单或离开聊天时收起键盘，避免弹层关闭后抢回焦点。

### 聊天真实创建

关键文件：

- `App/Core/ChatActions.swift`
- `App/Services/ChatActionService.swift`
- `App/Services/DeepSeekWebClient.swift`
- `App/Services/AIService.swift`
- `App/Views/ConversationView.swift`

实现 `create_note` / `create_record` / `create_reminder` 工具，只按本轮用户请求授权；明确金额、账户、时间等缺失时询问；校验、加密保存后才显示成功回执；限制重复工具调用，保存前文也能本地完成；锁库或切换会话后避免继续错误地写入或同步通知。每种类型每轮目前最多创建一项；转账、退款、贷款登记不走普通收支创建工具。图片、网页或引用中的命令不能自行授权写入。

### 巡检 F1–F6

- **F1 输入丢失**：叶子表单增加局部 `.appErrorScope()`，错误留在当前编辑页；资金桶新建/分配、投资价格更新等输入弹窗改为保存成功才关闭的表单。
- **F2 订阅付款误触编辑**：编辑/付款分别响应，按钮样式与点击区域分离；确认绑定所显示账期；同一期重复请求幂等，不误付下一期；显示 `subscription.paymentReceipt`。
- **F3 月底日期偏移**：新增 `App/Core/ReminderOperations.swift`，普通循环提醒保留原始 `anchorDay` / `anchorMonth` / 时区，短月取月底，后续恢复原约定日；闰日按年份恢复。贷款提醒仍由贷款计划独立管理。
- **F4 撤销完成**：一次性提醒可取消完成，按钮无障碍名称为“取消完成提醒”；循环提醒左滑“撤销上次完成”，只恢复最近一期；编辑日期/周期会清理旧撤销记录，改标题则保留原锚点。
- **F5 现金规则**：`Finance.validateCashChange` 统一校验手工收支、删除/减少收入、退款、订阅、投资、AA、转账等；`AppStore.commit` 也统一兜底。新操作不能新增或加重非信用账户的历史负余额，旧负余额可逐步改善；信用账户保留欠款语义。完整加密备份恢复是历史快照的明确例外，不拿不相关旧账户ID做差额比较；后续普通修改仍受检查。现有负余额不会被自动“修复”成凭空到账。
- **F6 容量**：设置新增资料库已用/剩余/上限容量；整库32MiB（加密头72字节计入），超限报错与无效密钥分开，原文件不覆盖，编辑内容保留；聊天记录独立保存。没有实施附件独立存储或数据迁移。

细节见 `Docs/AUDIT_FIXES.md`、`Docs/BUILD6.md`、`Docs/DEBT_MODEL.md`。

## 6. 特别注意：iOS 26 连续记账超时尚不能声称已完全验证解决

较早的构建 `4aa4a92...` 在 iOS26 连续聊天“创建笔记→记25元支出→记200元收入”时，收入请求之后发生应用空闲等待及界面查询超时；其他9项主流程UI测试通过。此前外观取样失败和历史页遗留键盘已另行处理。

后续 `6004fe3`、`1ab92b8` 做了滚动相关修改：

- 对话消息布局由 `LazyVStack` 改为 `VStack`。
- 最新消息变化后，用可取消 `.task(id: lastMessage)` 延迟40ms，在布局稳定后滚到底部，不在插入时同步 `scrollTo`。
- 新内容增高不被误判为用户离开底部；手势滚动时暂停自动跟随。

这是针对疑似布局/滚动循环的修复，**不要声称底层根因已证实，或最新专项已通过**。后来的主流程任务多次卡在模拟器启动；最新专项/主流程与巡检最后按用户要求取消，直接打包。

若用户以后反馈卡顿，优先复查此链路、长对话滚动与输入法；只有出现新任务需要时再做对应验证，不要仅为了补齐旧报告恢复已取消的长测试。

## 7. 实际验证状态与历史证据

**交付清单中的 `complete_UI_validation_verified=false` 是准确状态，不能改成 true。**

- 核心规则 **113项通过**，最近完整核心代码验证提交 `9e258fa...`；与打包提交之间 `App/Core` 无变化。
- 较早已通过：iOS18应用内36项 + 主流程UI10项，以及 iOS18巡检9项、iOS26巡检9项（`1ab92b8...`，应用代码与交付代码相同，后续仅改工作流）。它们是历史证据，不等于最新全量UI通过。
- `40125931764`：`1ab92b8...`，核心/18主流程/18巡检/26巡检通过，26主流程两次在模拟器启动步骤失败，未进入专项。
- `40124099758`：`4aa4a92...`，iOS26主流程出现上述收入超时。
- `40149473819`：`9e258fa...`，仅26两组，曾进入专项和巡检，后来用户要求取消；不要把 canceled 当 success。
- `40150071862`：`4d8ddb7...`，**直接设备打包成功**，没有主流程/巡检前置门槛，正是已交付IPA来源。

没有使用用户的真实 DeepSeek Key 做付费调用。模拟 HTTP/工具协议证明客户端协议与真实本地保存路径，不证明真实模型在每个问题下的理解。没有真机签名安装、实际 Face ID、相机/麦克风/Metal性能、后台通知送达的完整验证；未下载并运行约1.12GB本机模型。备份加密函数和导出入口有检查，系统文件选择、保存与完整恢复/导入链路没有穷举。

历史日志位置（目录不能自动当成当前构建结果，先看对应提交/运行号）：

- `/workspace/deliverables/build6-failed26-main/`：`4aa4a92` 的收入超时录屏、截图、日志。
- `/workspace/deliverables/build6-audit26/`：`1ab92b8` 的9项巡检通过证据。
- `/workspace/deliverables/build6-main18/`、`build6-audit18/`：`1ab92b8` 历史证据。
- `/workspace/deliverables/build6-main26/`：**更老的失败资料，不是最新成功结果**。
- `/workspace/tool-audit/build6-ready-run.json`：成功直接打包的运行与产物元数据。
- `/workspace/tool-audit/build6-ready-complete.log`：113项核心测试的云端日志。
- `/workspace/tool-audit/build6-final-secret-report.json`：最后源代码扫描0项泄漏发现。

`/workspace/deliverables/PersonalAssistant-iOS-3.5.1-build6-source.zip` 是**之前9e提交的快照**，没有之后新增的直接打包工作流，也没有本交接文件。它不是最新完整仓库快照，不要作为“最新完整源码”交付；最新源码以公开仓库为准。

## 8. 构建、环境与工具

当前是 Linux 工作区，本机没有 Xcode/交互式 iPhone 模拟器。真实云端模拟器由 GitHub Actions 的 XCTest 操作，读日志、截图与录屏进行复核，不能描述成本机手动操作模拟器。

两个手动工作流：

```bash
# 默认全验证：核心 + iOS26主流程/专项与巡检，通过后打包
# 不要为了补齐本轮报告擅自重启已取消的验证。
gh workflow run ios-build.yml

# 用户要求的直接设备打包，不等待两组UI测试
gh workflow run ios-package.yml
```

普通 push 不自动启动这两条流程。均使用标准公开仓库 runner，不是收费大规格机器。直接打包会复用 Native Metal 缓存（最近已命中），使用 `Scripts/build-ipa.sh` 生成 Release iOS arm64 包，并由 `Scripts/verify_ipa.py` 校验。

全验证流程已改成仅iOS26：新建干净模拟器，启动最多360秒，卡住时关闭并重试一次；26主流程先运行单独的连续记账专项，再运行完整主流程。以前预置模拟器多次启动卡住，不应把启动失败归因于产品测试失败。

有变更需要重新生成工程时：`python3 Scripts/generate_project.py` 自动扫描 App 与测试源文件。核心库在 `App/Core`，`Package.swift` 可运行核心测试；本机没有直接 `swift` 时，可用已配置的 Docker `swift:6.0.3-noble`，保留环境代理和CA设置。UIKit/SwiftUI必须用 macOS/Xcode 编译。不要修改 Vendor，除非任务确有需要；Vendor 内另有 AGENTS.md。

GitHub连接正常时优先使用连接器/gh；可在 `ALL_TOOLS` 搜索 workflow job logs、download artifact 等工具。进行中的 job 日志下载可能404，任务结束后再取；不是一定鉴权失效。长时间 `gh run watch` 曾因短期鉴权401退出，新一次工具调用中的 `gh run view` 通常可正常工作；不要交互式登录、打印环境或读取密钥明文来排查。

若环境显示 starting，需要文件时再等待恢复；连接器可先检查远端任务。不要把重试日志、测试夹具或临时缓存作为用户资料。

## 9. 校验脚本与旧文档的陷阱

- 实际交付用的是 `/workspace/tool-audit/verify-build6-direct-delivery.py`：校验真实IPA，并准确记录剩余UI按用户要求跳过。
- `/workspace/tool-audit/verify-build6-delivery.py` 是原先“所有UI通过才交付”的草案，带旧测试门槛；**不要拿它反推本轮全部UI通过**。它还会向源码ZIP追加校验文件，不可无脑重复执行。
- `/workspace/tool-audit/finalize-build6-docs.py` 是未执行草案，假定169次测试全部通过；**不能直接运行或发布**，否则会生成虚假的全通过报告。
- `/workspace/deliverables/SIMULATOR_AUDIT.md`、旧工作笔记和 checkpoint 的历史字段可能仍写“等待打包/尚未修复/等待全量验证”，应以本交接文件及最终交付清单为准。
- README、INSTALL、OPEN_SOURCE 中有旧的“iOS18/26”全流程描述尚未统一更新；工作流现为26-only，且另有直接打包流程。历史 BUILD2/3 等说明是历史版本记录。
- 不要为了整理文档重新发布同一版本IPA。若未来产生新的应用改动并再次交付，应统一考虑递增构建号（当前6）；涉及生成脚本、打包/校验脚本、产物名、About显示等多个位置，不要只改一处。

## 10. 下一窗口的建议起点

1. 读本文件，检查仓库与最终交付清单；确认用户的新需求，不要自行恢复旧的长流程。
2. 如果只是要下载，直接提供第3节链接；GitHub产物过期才按用户要求重新直接打包。
3. 若用户反馈安装或实际使用问题，先确认表现、签名/应用标识、所用构建号，按具体问题定位；保留旧资料，不擅自卸载、清空、重置或迁移。
4. 若用户要求继续测试，重点放在 iOS26连续聊天记账、长对话滚动和实际输入法，准确区分设备环境启动、测试脚本定位、产品问题。

可在新窗口直接发送：

> 请先读取仓库根目录 HANDOFF.md（或我附上的 HANDOFF_BUILD6.md），以其中已交付状态和最新用户决定为准，不要自动恢复已取消的验证。然后处理我的新需求。
