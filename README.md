# kBox

多平台工具箱（SwiftUI + Swift Charts），同一套代码跑 **macOS** 和 **iPadOS**，边栏选择不同工具。无第三方依赖。

- macOS 15+
- iPadOS 26+（iPhone 能装能跑，但窄屏布局没有专门优化）

## 构建与运行

**macOS**：

```bash
scripts/build-app.sh --open
```

生成 `build/kBox.app`（ad-hoc 签名，可拖进「应用程序」或 Dock，双击即用）。

**iPad**：用 Xcode 打开 `kBox.xcodeproj`，选 `kBox` scheme：

- 模拟器：目标选任意 iPad 模拟器，直接 Run。
- 真机：在 target 的 Signing & Capabilities 里把 Team 选成你自己的 Apple ID（免费个人团队也行），目标选你的 iPad，Run。第一次需要在 iPad 的「设置 → 通用 → VPN 与设备管理」里信任开发者证书；免费团队的签名 7 天后过期，重新 Run 即可。

**开发**：

```bash
swift build --package-path Packages/KBoxKit   # 编译库
swift test  --package-path Packages/KBoxKit   # 单元测试（Swift Testing，跑在 macOS 上）
open kBox.xcodeproj                            # Xcode：Run / Previews
```

贷款方案保存在各平台自己的 Application Support 目录里（`~/Library/Application Support/kBox/loan.json`）。**mac 和 iPad 的方案数据相互独立，不会同步。**邮件查看器只读不写，不保存任何东西。

## 工具

- **贷款计算器**：房价 / 首付 / 15·20·30 年期限 / 利率（⌘R 或工具栏刷新按钮从 FRED 获取最新按揭利率，自动区分常规与巨额贷款）/ 房产税 / 保险 / HOA / PMI，以及可选的「其他开销」（维护、地震险、特别税、水电、一次性成交费用）。
  「加入图表」（⌘↩）把当前方案加入对比表格，以 Swift Charts 堆叠面积图并排比较（累计支付 / 月供构成）。macOS 上鼠标悬停、iPad 上点按或拖动，十字线和数值在所有图之间同步。
- **邮件查看器**：打开 mbox 文件（⌘O，macOS 上也可以把文件拖进窗口）——Gmail（Google Takeout）、Thunderbird 的邮箱文件，或 Apple Mail 导出的 `xxx.mbox` 文件夹；单个 .eml 也能打开。
  Apple Mail 式的列表（发件人、日期、主题、两行摘要、附件回形针，新邮件在前）+ 阅读区（头像、收件人/抄送、附件）。HTML 邮件用 WebKit 显示：页面脚本一律不执行，远程图片/样式默认屏蔽（可点「载入远程内容」），`cid:` 内嵌图片直接显示；纯文本邮件跟随深色模式，`>` 引用显示为引用条，链接可点。
  附件点按用「快速查看」预览，右键/长按「存储…」。搜索（⌘F）覆盖发件人、收件人、主题和正文，不区分大小写/全半角/重音，多个词须全部命中，可限定范围；命中的词在列表和正文里高亮。
  解码 RFC 2047 编码的标题、RFC 2231 文件名、base64 / quoted-printable、`format=flowed`，常见中文编码（GB2312 / GBK / GB18030 / Big5）、只在 HTML `<meta>` 里声明的编码、误标成 Latin-1 的 UTF-8，以及未声明编码的 8-bit 头部；缺 `Date:` 时依次用 `Received:` 和信封行的时间。内联转发的邮件和 digest 直接显示在正文下方。几百 MB 的邮箱几秒内读完（整份读进内存，全部摘要和搜索文本也在内存里）。
  键盘：点过邮件后 ↑/↓ 切换邮件，打开邮箱后直接按 ↓ 选中第一封；在搜索框里按 Esc 或回车回到列表。

## 结构

```
kBox.xcodeproj       多平台 app target（macOS + iOS，SDKROOT=auto）
App/                 @main 入口、平台胶水、Assets.xcassets（应用图标）
Packages/KBoxKit/    本地 Swift 包：全部界面与逻辑
  Sources/KBoxKit/App/        边栏 + 工具注册（Tool.swift）
  Sources/KBoxKit/Loan/Model/ 房贷计算、FRED 利率、方案、状态（LoanStore）
  Sources/KBoxKit/Loan/Views/ 表单、月供卡片、方案表格、对比图表
  Sources/KBoxKit/Mail/Model/ mbox 切分、MIME 解码、日期/地址、搜索、阅读页 HTML、状态（MailStore）
  Sources/KBoxKit/Mail/Views/ 邮件列表、阅读区、WebKit 正文、附件、工具栏与搜索
  Sources/KBoxKit/Shared/     格式化、存储、平台差异（PlatformUI.swift）
  Tests/KBoxKitTests/         计算、利率解析、图表数据、mbox/MIME 解析、搜索、状态测试
scripts/             build-app.sh（打包 mac 版）、make-icon.swift（生成图标）
```

平台差异都集中在 `#if os(macOS)` 分支里：macOS 用两列 + `HSplitView`，iPadOS 用三列（工具 | 表单 | 图表）；触摸端没有悬停，所以图表用点按/拖动选择、卡片的删除按钮常显；`Toggle(.checkbox)`、`onDeleteCommand` 等 macOS 专属 API 只在 mac 上编译。

新增工具：在 `Tool.swift` 加一个 case 并填好标题/图标/分组，然后在 `RootView` 里返回它的 View。

## 调试：命令行截图（仅 debug 构建，macOS）

```bash
KBOX_DEMO=1 KBOX_APPEARANCE=dark KBOX_SNAPSHOT=/tmp/kbox.png build/dd/Build/Products/Debug/kBox.app/Contents/MacOS/kBox
```

可选 `KBOX_CHART_MODE=monthly`、`KBOX_EXTRAS=1`、`KBOX_CARD_ACTIONS=1`、`KBOX_HOVER_YEAR=12`、`KBOX_FETCH=1`、`KBOX_SNAPSHOT_SIZE=1560x1400`。

邮件查看器：

```bash
KBOX_TOOL=mail KBOX_MBOX=/path/to/mail.mbox KBOX_MAIL_SELECT=0 KBOX_SNAPSHOT=/tmp/kbox-mail.png build/dd/Build/Products/Debug/kBox.app/Contents/MacOS/kBox
```

可选 `KBOX_MAIL_SEARCH=发票`（预填搜索）、`KBOX_MAIL_FOCUS_SEARCH=1`（聚焦搜索框，显示搜索范围）。`KBOX_TOOL` 不会改动保存的工具选择。

`KBOX_UI` 在截图前按顺序合成真实的点按和按键（进程内发送，不需要辅助功能权限），用来检查焦点和快捷键，例如：

```bash
open -n -a build/dd/Build/Products/Debug/kBox.app --stderr /tmp/kbox.log --env KBOX_MBOX=/path/to/mail.mbox --env KBOX_SNAPSHOT_SIZE=1400x900 --env "KBOX_UI=click:440,180;key:down;key:cmd+f;key:escape;log" --env KBOX_SNAPSHOT=/tmp/kbox-ui.png
```

步骤用 `;` 分隔：`click:x,y`（窗口左上角为原点的 pt 坐标，和截图一致）、`key:down|up|return|escape|tab|space|字母`（可加 `cmd+`、`shift+`、`opt+`、`ctrl+`）、`wait:毫秒`、`log`（把第一响应者、当前工具和选中的邮件写到 stderr）。用 `open` 启动能保证 app 在前台；从终端直接启动时窗口可能不是 key window，点按的行为会不一样。
iPad 模拟器上用 `SIMCTL_CHILD_` 前缀传同样的变量：`SIMCTL_CHILD_KBOX_TOOL=mail SIMCTL_CHILD_KBOX_MBOX=/path/to/mail.mbox xcrun simctl launch booted local.kbox`。
用环境变量而不是命令行参数：AppKit 会把多余的参数当作要打开的文档，从而不创建主窗口。
