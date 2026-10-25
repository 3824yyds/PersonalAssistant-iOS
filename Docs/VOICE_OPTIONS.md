# 中文语音方案：试听与费用

核对日期：2026-10-25。当前只比较，没有接入或调用付费语音服务。以下声音服务均可与现有 DeepSeek Flash / Pro 搭配，负责把回复文字说出来。

## 先用同一段中文试听

> 你好呀，今天过得怎么样？别着急，你慢慢说，我在听。

每家先听一个男声和一个女声，使用正常语速，再分别试偏慢和偏快。自然程度属于听感判断，不能仅根据价格下结论。

| 方案 | 官方试听入口 | 参考 API 费用（USD） | 选择要点 |
|---|---|---|---|
| Azure 标准神经语音 | [声音库](https://speech.microsoft.com/portal/voicegallery)，选中文普通话；可先听晓晓 / 云希 | East US 公开按量价约 $15 / 百万字符；10万字符约 $1.50 | 中文男/女音色明确，支持原生语速控制，适合先试低成本方案 |
| Azure Neural HD | 同一声音库中筛选 HD | East US 公开按量价约 $22 / 百万字符；10万字符约 $2.20 | HD 定位更自然，但官方不支持 SSML prosody 调速，需客户端另做播放变速 |
| ElevenLabs v4 / v4 Turbo | [中文试听](https://elevenlabs.io/text-to-speech/chinese)，使用当前页面提供的模型与音色 | v4 约 $0.08 / 千字符，10万字符约 $8；Turbo 约 $0.04 / 千字符，10万字符约 $4 | 重点比较聊天语气和情绪表现；API 提供 speed 配置，具体音色与模型确认后再接入 |
| OpenAI TTS | [OpenAI.fm](https://www.openai.fm/)，官方建议先比较 marin / cedar | 以 gpt-4o-mini-tts 为例：输入文本 $0.60 / 百万 token，输出音频 $12 / 百万 token | 支持音色和表达方式控制；中文需试听，官方提示声音主要针对英语优化 |

OpenAI 的音频 token 与文字字符不是同一计费单位，因此这里不把“10万字”直接换成 OpenAI 费用。需要用实际中文样本与语速估算。ChatGPT 订阅与 OpenAI API 费用分开。

Azure 标准神经语音的 F0 页面列有每月50万字符免费额度，需以账户、区域和所建资源是否符合该档位为准；不能把这个免费额度套到 HD 音色。以上按量价不包含套餐、税费或现有 DeepSeek 用量费，实际以所选区域和账户结算页面为准。

## 对这个应用的建议

先重点比较 Azure 标准神经语音与 ElevenLabs v4 / Turbo。前者便于控制成本及男/女声、语速，后者值得重点听口语与情绪表现。OpenAI.fm 可作为自然对话听感的另一组对照。Azure HD 如果最合口味，也能接入，但语速要另做客户端处理。

选定后再实现一套统一的声音设置：服务、男/女音色、具体声音、语速、试听与保存。声音列表来自实际可用资源，不通过抬高/降低同一声音的音调来假装男女声。

## 当前版本状态

Build 9 处理停顿自动发送故障，并给语音回复增加简短口语表达要求。新云端音色、男/女声选择与扩展调速尚未接入，按用户“先比较试听和费用再决定”的要求等待方案选择；现有系统朗读与三档语速保留。

## 核对来源

- [Azure 定价与免费档](https://azure.microsoft.com/en-us/pricing/details/cognitive-services/speech-services/)
- [Azure 零售价公开 API](https://prices.azure.com/api/retail/prices?%24filter=contains%28productName%2C%20%27Speech%27%29%20and%20armRegionName%20eq%20%27eastus%27)：S1 Neural Text To Speech Characters = 15 USD / 1M；Neural HD Text to Speech Characters = 22 USD / 1M。
- [Azure HD 支持的 SSML 元素](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/high-definition-voices)：prosody 对 DragonHD 和 Dragon HD Omni 均列为不支持。
- [ElevenLabs 当前 API 定价](https://elevenlabs.io/pricing/api)
- [ElevenLabs TTS 参数](https://elevenlabs.io/docs/api-reference/text-to-speech/convert)
- [OpenAI TTS 使用和试听说明](https://developers.openai.com/api/docs/guides/text-to-speech)
- [OpenAI mini TTS 模型单价](https://developers.openai.com/api/docs/models/gpt-4o-mini-tts)
