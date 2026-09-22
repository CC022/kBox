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

数据保存在各平台自己的 Application Support 目录里（`~/Library/Application Support/kBox/loan.json`）。**mac 和 iPad 的方案数据相互独立，不会同步。**

## 工具

- **贷款计算器**：房价 / 首付 / 15·20·30 年期限 / 利率（⌘R 或工具栏刷新按钮从 FRED 获取最新按揭利率，自动区分常规与巨额贷款）/ 房产税 / 保险 / HOA / PMI，以及可选的「其他开销」（维护、地震险、特别税、水电、一次性成交费用）。
  「加入图表」（⌘↩）把当前方案加入对比表格，以 Swift Charts 堆叠面积图并排比较（累计支付 / 月供构成）。macOS 上鼠标悬停、iPad 上点按或拖动，十字线和数值在所有图之间同步。

## 结构

```
kBox.xcodeproj       多平台 app target（macOS + iOS，SDKROOT=auto）
App/                 @main 入口、平台胶水、Assets.xcassets（应用图标）
Packages/KBoxKit/    本地 Swift 包：全部界面与逻辑
  Sources/KBoxKit/App/        边栏 + 工具注册（Tool.swift）
  Sources/KBoxKit/Loan/Model/ 房贷计算、FRED 利率、方案、状态（LoanStore）
  Sources/KBoxKit/Loan/Views/ 表单、月供卡片、方案表格、对比图表
  Sources/KBoxKit/Shared/     格式化、存储、平台差异（PlatformUI.swift）
  Tests/KBoxKitTests/         计算、利率解析、图表数据、状态测试
scripts/             build-app.sh（打包 mac 版）、make-icon.swift（生成图标）
```

平台差异都集中在 `#if os(macOS)` 分支里：macOS 用两列 + `HSplitView`，iPadOS 用三列（工具 | 表单 | 图表）；触摸端没有悬停，所以图表用点按/拖动选择、卡片的删除按钮常显；`Toggle(.checkbox)`、`onDeleteCommand` 等 macOS 专属 API 只在 mac 上编译。

新增工具：在 `Tool.swift` 加一个 case 并填好标题/图标/分组，然后在 `RootView` 里返回它的 View。

## 调试：命令行截图（仅 debug 构建，macOS）

```bash
KBOX_DEMO=1 KBOX_APPEARANCE=dark KBOX_SNAPSHOT=/tmp/kbox.png build/dd/Build/Products/Debug/kBox.app/Contents/MacOS/kBox
```

可选 `KBOX_CHART_MODE=monthly`、`KBOX_EXTRAS=1`、`KBOX_CARD_ACTIONS=1`、`KBOX_HOVER_YEAR=12`、`KBOX_FETCH=1`、`KBOX_SNAPSHOT_SIZE=1560x1400`。
用环境变量而不是命令行参数：AppKit 会把多余的参数当作要打开的文档，从而不创建主窗口。
