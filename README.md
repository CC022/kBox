# kBox

原生 macOS 工具箱（SwiftUI + Swift Charts），边栏选择不同工具。无第三方依赖。

## 构建与运行

```bash
scripts/build-app.sh --open
```

生成 `build/kBox.app`（ad-hoc 签名，可拖进「应用程序」或 Dock，双击即用）。

开发时：

```bash
swift build          # 编译
swift test           # 单元测试（Swift Testing）
open Package.swift   # 用 Xcode 打开，可直接 Run / 使用 Previews
```

数据保存在 `~/Library/Application Support/kBox/loan.json`。

## 工具

- **贷款计算器**：房价 / 首付 / 15·20·30 年期限 / 利率（⌘R 从 FRED 获取最新按揭利率，自动区分常规与巨额贷款）/ 房产税 / 保险 / HOA / PMI。
  「加入图表」（⌘↩）把当前方案加入对比表格，以 Swift Charts 堆叠面积图并排比较（累计支付 / 月供构成），悬停十字线在所有图之间同步。

## 结构

```
Sources/KBoxApp/     @main 入口（窗口、调试钩子）
Sources/KBoxKit/     全部界面与逻辑
  App/               边栏 + 工具注册（Tool.swift）
  Loan/Model/        房贷计算、FRED 利率、方案、状态（LoanStore）
  Loan/Views/        表单、月供卡片、方案表格、对比图表
Tests/KBoxKitTests/  计算、利率解析、图表数据、状态测试
scripts/             build-app.sh（打包 .app）、make-icon.swift（生成图标）
```

新增工具：在 `Tool.swift` 加一个 case 并填好标题/图标/分组，然后在 `RootView` 的 `detail` 里返回它的 View。

## 调试：命令行截图（仅 debug 构建）

```bash
KBOX_DEMO=1 KBOX_APPEARANCE=dark KBOX_SNAPSHOT=/tmp/kbox.png .build/debug/kBox
```

可选 `KBOX_CHART_MODE=monthly`、`KBOX_CARD_ACTIONS=1`、`KBOX_HOVER_YEAR=12`、`KBOX_FETCH=1`、`KBOX_SNAPSHOT_SIZE=1560x1400`。
用环境变量而不是命令行参数：AppKit 会把多余的参数当作要打开的文档，从而不创建主窗口。
