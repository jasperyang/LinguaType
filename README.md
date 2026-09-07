# LinguaType

LinguaType 是一个 macOS 菜单栏语言学习助手。你继续使用系统拼音、鼠须管等中文输入法；当中文提交到当前文本框后，LinguaType 在光标附近展示法语、英语、日语表达，以及最多 3 个值得学习的词。

> 当前产品是 `LinguaTypeCompanion.app`，不是系统输入源。仓库中保留的 RIMES/InputMethodKit 原型需要 Developer ID 签名与 Apple 公证，不能靠本地 ad-hoc 签名稳定加入新版 macOS 的输入法列表。

## 当前体验

- 菜单栏使用原生 `NSStatusItem`，图标为 `A·あ`，不再占用屏幕右上角的浮动“字”方块。
- 浮窗右上角的语言下拉框默认显示 `法语⌄`；勾选框决定显示哪些语言，点击语言名称可把它设为主学习语言。收起状态只显示主语言，不显示 `+2` 一类计数。
- 主学习语言完整显示；英语、日语等辅助语言默认单行收起，点击译文或箭头可展开，并且一次只展开一种。
- 每种译文右侧都有一键复制按钮，只复制该语言的完整译文；成功后按钮短暂显示对勾。
- 最多挑选 3 个有学习价值的词，以双栏学习卡展示当前语境、精简中文释义和已勾选语言的词形。
- 英语、法语显示 IPA；日语显示假名和本地生成的罗马字。
- 结果逐步出现，不等待所有翻译和词典请求完成。
- 浮窗默认 12 秒后隐藏，鼠标悬停会暂停计时；点击图钉可固定当前会话中的浮窗，新输入会更新同一窗口。取消固定后重新开始 12 秒倒计时。
- 左键点击 `A·あ` 切换浮窗；右键打开学习开关、联网查词、模型状态、清缓存、隐私说明和退出。

## 隐私边界

- 完整中文句子只交给 Apple Translation，在本机处理。
- 联网词典只收到单个词，不收到完整句子、应用名称或窗口标题。
- 日志只记录字符数、服务名、状态与耗时，不记录原句和查询词。
- 不使用 OpenAI、Claude、DeepSeek 等生成式 AI 服务。

联网查词使用中文/法语/英语 Wiktionary、Free Dictionary API 和 Jotoba/JMdict。成功结果缓存 30 天；查无结果或临时失败缓存 10 分钟。英语免费词典不可用时自动回退到英语 Wiktionary。

## 要求

- macOS 15 或更高
- Xcode Command Line Tools
- 首次使用法语、英语或日语时，系统可能需要准备 Apple Translation 语言模型
- Accessibility（辅助功能）权限，用于读取当前聚焦文本框

## 构建和安装

只构建现在实际使用的 Companion：

```bash
./build-companion.sh
```

脚本会先运行回归测试，然后构建、ad-hoc 签名并安装到：

```text
~/Applications/LinguaTypeCompanion.app
```

首次启动后，到“系统设置 → 隐私与安全性 → 辅助功能”，开启 **LinguaType Companion**。随后在 TextEdit、备忘录或聊天软件中用任意中文输入法输入中文即可。

本地构建使用 ad-hoc 签名。每次重新构建后，macOS 可能把它视为新的辅助功能客户端；如果能看到菜单栏图标但输入后没有浮窗，请先删除系统设置里旧的 **LinguaType Companion** 条目，再把当前的 `~/Applications/LinguaTypeCompanion.app` 加回并重新启动应用。

运行测试：

```bash
./test-companion.sh
```

旧的完整 RIMES 构建仍可运行：

```bash
./build-linguatype.sh
```

它会下载并构建体积较大的 RIMES 工作区。日常开发和更新 Companion 不需要运行它。

## 数据位置

```text
~/Library/Caches/LinguaType/dictionary-cache-v2.json
~/Library/Application Support/LinguaType/learning-exposure.json
```

可以从 `A·あ` 右键菜单清除词典缓存。主学习语言和勾选的显示语言会保存在本机偏好设置中；浮窗固定状态只在当前应用会话内有效。

## 自动启动与卸载

```bash
./activate-linguatype.sh
./activate-linguatype.sh --status
./activate-linguatype.sh --uninstall
```

卸载命令会停止并移除 LaunchAgent，但保留 app；如需完全删除，再移除 `~/Applications/LinguaTypeCompanion.app`。

## 开发结构

- `LinguaTypeCompanion/Sources/`：菜单栏、Accessibility 观察、Apple Translation 桥、学习卡片和词典适配器。
- `LinguaTypeCompanion/Tests/`：无第三方依赖的 macOS 回归测试。
- `docs/superpowers/specs/`：已确认的产品与技术设计。
- `docs/superpowers/plans/`：实现计划。

输入观察、翻译队列和联网词典彼此隔离；任何学习功能失败都不会影响原本的中文输入。

## 发布说明

当前构建是本机 ad-hoc 签名版本，适合开发和自用。向其他用户分发需要 Apple Developer ID 签名和公证。

仓库还没有选择开源许可证。公开可见不等于已授权复制、修改或再分发；正式开放贡献前应补充明确许可证。
