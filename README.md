# LinguaType 0.1 — macOS 伴随式语言学习工具

LinguaType 在 macOS 26 上以 Companion App 运行：继续使用系统拼音、鼠须管等已安装中文输入法，Companion 通过 Accessibility 读取当前文本，并在光标附近异步显示外语翻译和学习词汇。

> 重要：源码中仍包含基于 RIMES/InputMethodKit 的 `LinguaType.app`，但本地 ad-hoc 签名的输入法在 macOS 26 无法进入系统 Input Sources。真正发布该输入法需要 Developer ID 签名并经过 Apple notarization；当前一键构建默认安装的是 `LinguaTypeCompanion.app`，不是名为 LinguaType 的系统输入源。

## 0.1 已实现

- 可与系统拼音、鼠须管等现有中文输入法配合使用的 Companion App。
- 屏幕右上角常驻“字”入口；中文提交后在光标附近显示学习浮层。
- 独立产品身份：
  - Bundle ID: `io.linguatype.inputmethod`
  - Input Source: `io.linguatype.inputmethod.Hans`
  - App: `LinguaType.app`
  - Executable: `LinguaType`
  - Rime 用户目录: `~/Library/RimeLinguaType`
- 中文候选稳定约 280 ms 后触发学习层。
- 默认显示：法语 + 英语。
- 可切换成日语、法语、英语等 Apple Translation 支持的目标语言。
- Apple Translation 本地翻译，不接 OpenAI/Claude/DeepSeek。
- 学习层与输入 hot path 分离；翻译失败不影响中文输入。
- Secure Input / 密码输入场景自动隐藏学习层。
- 当前高亮候选改变时重新翻译（普通候选左右移动、翻页）。
- 通过 `NLTokenizer` 从当前中文候选中挑一个学习词，并额外显示词级翻译。
- 本地记录词汇 exposure：`~/Library/Application Support/LinguaType/learning-exposure.json`。
- 同一词 30 秒内重复显示只算一次 exposure。
- 内存翻译缓存，减少当前会话重复翻译。

## 为什么不是直接给你一个已经编译好的 `.pkg`

本包中的 Swift/InputMethodKit/Translation 代码必须由 macOS 15+ 的 Apple SDK 编译。当前生成本包的环境不是 macOS，因此无法在这里真实运行 Xcode、InputMethodKit、`codesign` 和 `pkgbuild` 验证最终二进制。

所以这里交付的是 **Mac 一键构建包**：你不需要自己修改代码。脚本会拉取锁定版本的 RIMES、应用 LinguaType 补丁、构建、注册输入法，并在你的 Mac 上生成本地 `.pkg`。

这比在非 macOS 环境伪造一个“可安装 pkg”可靠得多。

## 要求

- macOS 15 或更高
- Apple Silicon 或 Intel Mac
- Xcode / Xcode Command Line Tools
- 能访问 GitHub
- 首次使用某个 Apple Translation 语言时，系统可能需要准备/下载对应翻译模型

检查开发工具：

```bash
xcode-select -p
swift --version
```

如果 `xcode-select -p` 报错，可先安装 Command Line Tools：

```bash
xcode-select --install
```

## 一键安装

解压后在 Terminal 进入本目录：

```bash
cd ~/Downloads/LinguaType-bootstrap-0.1.0
./build-linguatype.sh
```

脚本会：

1. 克隆 `scholay/rimes`
2. 锁定到 commit `eba5185a3ed637b6df9ca9149fbfc49740bd58b2`
3. 应用 LinguaType 身份隔离补丁
4. 加入 `LinguaTypeLearning.swift`
5. 构建 librime/RIME 输入法
6. 构建未公证的 `LinguaType.app` 供后续正式签名，但不注册到 Input Sources
7. 安装并启动 `~/Applications/LinguaTypeCompanion.app`
8. 在 `dist/` 生成 `LinguaType-Companion-0.1.0-local.pkg`

完成后先在“系统设置 → 隐私与安全性 → 辅助功能”中允许 **LinguaTypeCompanion**，再用 `Control + Space` 切换到你原有的中文输入法。

右上角“字”入口由 Companion 提供；它不是系统输入源菜单中的一项。

## 默认学习语言

默认：

- 主语言：法语 `fr`
- 辅助语言：英语 `en`

切换为日语 + 英语：

```bash
./configure-languages.sh ja en
```

只想法语：

```bash
./configure-languages.sh fr off
```

英语 + 日语：

```bash
./configure-languages.sh en ja
```

修改后切走 LinguaType 再切回来一次。

## 当前交互

例如输入拼音得到高亮中文候选：

```text
这个方案还需要再优化一下
```

Learning Layer 会异步出现类似：

```text
语言学习
🇫🇷  Cette approche doit encore être améliorée.
🇬🇧  This approach still needs some refinement.
词汇  优化  →  améliorer / optimize
```

中文候选窗和学习窗是两条独立链。Apple Translation 慢、语言包不可用或翻译失败时，Rime 中文输入仍继续工作。

## 本地数据

Rime：

```text
~/Library/RimeLinguaType/
```

学习 exposure：

```text
~/Library/Application Support/LinguaType/learning-exposure.json
```

0.1 不上传学习历史，不配置任何 LLM API。

## 本地 pkg

`build-linguatype.sh` 成功后：

```text
dist/LinguaType-0.1.0-local.pkg
```

这是 **本地 unsigned pkg**，不是 Developer ID 签名/Apple notarized 的公开发行包。当前 Mac 已由 build 脚本直接完成 per-user 安装，所以通常不需要再安装 pkg。

如果想把同一次构建拿到另一台自己的 Mac，可将整个目录（含 `dist/`）复制过去并运行：

```bash
./install-pkg-on-another-mac.sh
```

管理员密码是系统级 `/Library/Input Methods` 安装所需。

## 0.1 有意没有做

- 设置 GUI（目前用 `configure-languages.sh`）
- SRS 复习页面
- 发音
- CEFR/JLPT 分级
- AI 语法解释
- 云同步
- Anki 导出
- 用户账户
- 多设备同步

先验证最关键假设：**“日常中文输入过程中持续看到自己的外语表达”是否真的能带来低摩擦语言学习。**

## 回滚 / 卸载

删除用户级安装：

```bash
pkill -x LinguaType 2>/dev/null || true
rm -rf "$HOME/Library/Input Methods/LinguaType.app"
```

然后注销/登录一次。

如需删除本地学习数据：

```bash
rm -rf "$HOME/Library/Application Support/LinguaType"
rm -rf "$HOME/Library/RimeLinguaType"
```

## 上游与许可证

本构建包不重新分发完整 RIMES 源码，而是在用户机器上从 GitHub 拉取锁定 commit 并应用补丁。RIMES 自有代码使用 MIT License；它携带的 Rime schema、字典、OpenCC/Lua 等资产可能使用各自许可证。构建后请保留上游 `LICENSE`、`THIRD_PARTY_NOTICES.md` 和 `rime-data/licenses/`。

## 开发说明

本包对 RIMES 的侵入点刻意很小：

- `CandidateWindow.update()`：候选更新后通知 Learning Layer
- `CandidateWindow.moveSelection()`：高亮候选变化后通知
- `CandidateWindow.movePage()`：翻页后通知
- `CandidateWindow.hide()/hideAll()`：同步关闭 Learning Layer

翻译桥使用附着在 Learning Panel 内的 1×1 SwiftUI Translation view；这是为了让 `TranslationSession` 保持真实 view lifecycle，而不是在输入事件里直接做网络/翻译工作。
