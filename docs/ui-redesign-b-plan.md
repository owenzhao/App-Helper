# App Helper 主界面改版执行计划（方案 B）

> 目标：把 `RulesView` 从「手写 `ScrollView + VStack` + 裸 `Text` 标题 + 手工 `Divider`」改为
> macOS 原生的 `Form` + `.formStyle(.grouped)` 设置页结构，一次性解决分组、间距、对齐、
> 深浅色适配四类问题，并顺带修掉若干可见缺陷。
>
> 约束：**不改动业务逻辑、不新增/重命名 `Defaults` 键、不改动 `SystemWatcher` 行为。**
> 改动只发生在视图层与本地化资源。

**状态：已执行完成，Debug 编译通过（BUILD SUCCEEDED，改动文件 0 warning）。**

---

## 1. 现状诊断（改版依据）

| # | 问题 | 证据位置 |
|---|---|---|
| 1 | 页面是 `ScrollView { VStack }`，所有 `Section { }` 在非 `Form`/`List` 上下文中**没有任何视觉效果**，分组感完全靠手写 `Divider()` 硬撑 | `RulesView.swift:59-74`、`:232/:243/:266/:296/:313/:341` |
| 2 | 用 `.title`(28pt) / `.title2`(22pt) 当分区标题，标题比正文抢眼；且层级不统一 | `:225`、`:241`、`:250`、`:273`、`:307` |
| 3 | `Monitor System Sleep` 把 `.font(.title.bold())` 直接加在 `Toggle` 上，开关与巨型标题同行 | `:327-329` |
| 4 | `Spacer()` 位于 `ScrollView` 的 `VStack` 内，不生效，属死代码 | `:71` |
| 5 | 会话级状态与持久化偏好混在一起：`preventScreensaver` 是 `@State`（退出即失效），`hideDesktop` 实际写入 Finder defaults（持久） | `:41-42`、`:150-165` |
| 6 | `HDR Status: Off` 为纯文本拼接，状态值无视觉权重；`Refresh HDR Status` 单独占一整行按钮 | `:311-312` |
| 7 | `Add App` 是游离按钮，与列表从属关系不清；删除按钮 `.destructive + .borderless` 在浅色背景近乎不可见 | `:274`、`:286-291` |
| 8 | 工具栏用 `Capsule + strokeBorder` 手搓 segmented control，与系统控件质感不一致 | `App_HelperApp.swift:385-429` |
| 9 | 窗口无最小尺寸约束（`NSWindow` 固定 800×600，无 `minWidth`） | `App_HelperApp.swift:160` |
| 10 | 部分 `Toggle` 字面量未带 `comment`，本地化条目可能缺失 | `:228-231` |

---

## 2. 目标结构

```
Form (.formStyle(.grouped))          frame(minWidth: 560, minHeight: 520)
├── Section header "Rules"           footer: 已启用 N / 6 条规则
│   └── 6 × AHRuleToggle（图标 + 主标题 + caption 说明 + switch）
├── Section header "Preferences"
│   └── AHRuleToggle  Notify User when a rule is matched.
├── Section header "Commands"
│   ├── AHRuleToggle  Prevent Screensaver.      （副标题标注「仅本次运行有效」）
│   └── AHRuleToggle  Hide Desktop.             （副标题标注「写入 Finder 设置并保持」）
├── Section header "Start other apps…" + 右侧 "+" 按钮
│   ├── 空态: "No apps added."
│   └── AHAppRow: 应用图标 + 名称 + switch + hover 高亮删除按钮
├── Section header "Display"
│   ├── borderless tinted Button  Toggle System Color Theme
│   └── LabeledContent "HDR Status" → AHStatusBadge（圆点+胶囊）+ 行内刷新图标按钮
├── Section header "System Sleep"
│   ├── AHRuleToggle  Monitor System Sleep
│   └── LabeledContent "Sleep Shortcut" → KeyboardShortcutView（未启用时 disabled）
└── Section（无标题）
    └── Button  Run in Background
```

**关键决策**

1. **不新增 Swift 文件。** `App Helper` 主组在 `project.pbxproj` 中是普通 `PBXGroup`（只有
   `Keyboard Watcher` 是 `PBXFileSystemSynchronizedRootGroup`），新增文件必须手工改 pbxproj。
   因此 `AHRuleToggle`、`AHStatusBadge`、`AHAppRow` 均以 `private struct` 形式写在
   `RulesView.swift` 内部，**零 pbxproj 改动**。

2. **不改动既有本地化键的原文。** 现有键（如 `Prevent Screensaver.`、`Hide Desktop.`、
   `Restart Monitor Control When System Preferences App Quits`）一律原样保留，zh-Hans 译文不丢失。
   只**新增**副标题 / 头部 / 状态类键。

3. **只重写视图层。** `HDRReader`、`refreshHDRStatus`、`migrateLegacyAutoStartAppsIfNeeded`、
   `chooseAutoStartApp`、`appendAutoStartApp`、`removeAutoStartApp`、
   `disableScreenSleep`/`enableScreenSleep`、`showDesktop`/`refreshDesktopVisibility`
   以及全部 `@Default` 属性**逐字保留**；`WindowBinder`、全部 `.onChange` / `.onReceive` /
   `.confirmationDialog` / `.alert` 修饰符也逐字保留。

4. **`Section` 只在 `Form` 内生效**，这是本次改版的技术前提；`Form` 自动提供卡片背景、
   内边距、行高与分隔线，故删除全部手写 `Divider()`。

5. **`AHTabPicker` / `AHStyle` / `AHTab.iconView` 直接删除**（原计划「暂时保留」，实际执行时
   确认全仓库仅被 `MainAppView` 一处引用，故按死代码清除，避免留下两套并存的分段控件实现）。

---

## 3. 执行记录

### 步骤 0 · 基线校验
- [x] `git status` 干净
- [x] 确认可编译路径：外部 `~/Library/Developer/Xcode/DerivedData` 与
      `~/Library/Caches/org.swift.swiftpm` 在 workspace-write 沙箱下不可写，
      基线构建失败于 `Could not resolve package dependencies`。改用全盘权限后构建正常。
- [x] 基线 Debug 构建通过

### 步骤 1 · 重写 `RulesView.swift` 视图层
- [x] `ScrollView { VStack }` → `Form { … }.formStyle(.grouped).frame(minWidth: 560, minHeight: 520)`
- [x] 删除 6 处 `Divider()` 与死 `Spacer()`
- [x] 每个 `Section` 补 `header:` / `footer:`
- [x] 删除 `.font(.title.bold())` / `.title2`
- [x] 新增 `AHRuleToggle`（图标 + 主标题 + caption 副标题 + `.toggleStyle(.switch)`）
- [x] 新增 `AHStatusBadge`（绿 / 灰 / 橙 三态圆点胶囊）
- [x] 新增 `AHAppRow`（App 图标 + hover 高亮删除按钮，`opacity 0.35 → 1`）
- [x] `HDR` 行改 `LabeledContent`，刷新动作收进行内 `arrow.clockwise`
- [x] `autoStartSection` 头部加 `+` 按钮
- [x] `systemSleepSection` 标题与开关拆行
- [x] 统一 toggle 为 switch（原先 rules 是 checkbox、sleep 是 switch，风格不一致）

### 步骤 2 · 工具栏改为原生 segmented
- [x] `MainAppView.swift`：`AHTabPicker` → `Picker(...).pickerStyle(.segmented)`，placement 由
      `.automatic` 改为 `.principal`（居中）
- [x] 删除 `AHStyle`、`AHTabPicker`、`AHTab.iconView`、`AHTab.emoji`（共 95 行）

### 步骤 3 · 本地化资源同步
- [x] 新增 14 个键 + zh-Hans 译文（见 §4）
- [x] 为 17 个既有键补齐 `comment`（见 §5）
- [x] JSON 校验通过，78 个键全部具备 zh-Hans 翻译

### 步骤 4 · 验证
- [x] `xcodebuild -scheme "App Helper" -configuration Debug` → **BUILD SUCCEEDED**
- [x] 改动文件 0 warning
- [x] 产物 `App Helper.app/Contents/Resources/zh-Hans.lproj/Localizable.strings` 中确认
      `"System Sleep" => "系统休眠"`、`"HDR Status" => "HDR 状态"`、
      `"Sleep Shortcut" => "睡眠快捷键"`、`"%lld of %lld rules enabled" => "已启用 %lld / %lld 条规则"`

---

## 4. 新增本地化键（共 14 个）

| Key (en) | zh-Hans |
|---|---|
| `System Sleep` | 系统休眠 |
| `HDR Status` | HDR 状态 |
| `Sleep Shortcut` | 睡眠快捷键 |
| `%lld of %lld rules enabled` | 已启用 %lld / %lld 条规则 |
| `Restart Monitor Control after a system settings app quits.` | 系统设置类应用退出后自动重启 Monitor Control。 |
| `Watch Xcode's CPU usage and clean up when it stays above the threshold.` | 持续监控 Xcode 的 CPU 占用，超过阈值后自动清理。 |
| `Kill SourceKitService as soon as Xcode quits.` | Xcode 一退出就结束 SourceKitService。 |
| `Kill the Open and Save panel service when any app quits.` | 任意应用退出后结束打开与存储面板服务。 |
| `Remove leftover Web Content processes when an app quits.` | 应用退出后清理残留的 Web Content 进程。 |
| `Also clean up Safari-related leftovers more aggressively.` | 更激进地清理 Safari 相关残留。 |
| `Send a system notification when a rule fires.` | 规则命中时发送系统通知。 |
| `Only applies until App Helper quits.` | 仅在 App Helper 退出前有效。 |
| `Writes to Finder settings and persists.` | 写入 Finder 设置并保持。 |
| `Run the shortcut below when the system is about to sleep.` | 系统即将休眠时执行下方的快捷键。 |

> 注：`HDR Status: %@` 与 `Sleep Shortcut:` 两个旧键已不再被引用，暂时保留在目录中未删除，
> 以免影响其他潜在引用。`HDR Status: %@` 为死键，可在下次清理时移除。

## 5. 补齐 `comment` 的既有键（共 17 个）

`Cancel`、`Clean Up Safari Remains Aggressively`、`Clean Up Web Content Remains When an App Quits`、
`Commands`、`Force Quitting Open and Save Panel Service When an App Quits`、
`Force Quitting SourceKitService When Xcode Quits`、`Hide Desktop.`、`Monitor System Sleep`、
`No apps added.`、`Notify User when a rule is matched.`、`Preferences`、`Prevent Screensaver.`、
`Refresh HDR Status`、`Remove`、`Restart Monitor Control When System Preferences App Quits`、
`Run in Background`、`Start other apps after self starts`。

---

## 6. 风险与回滚

| 风险 | 处置 |
|---|---|
| `Form` 内 `Toggle` 标签在窄窗口下被截断 | 标签加 `.fixedSize(horizontal: false, vertical: true)`；窗口 `minWidth: 560` |
| `LabeledContent` 内嵌 `KeyboardShortcutView` 布局异常 | 若异常则退回 `HStack { Text(…); Spacer(); KeyboardShortcutView(…) }` |
| 新 SF Symbol 在目标系统不存在 | 已用 `NSImage(systemSymbolName:)` 在本机逐个验证：`arrow.triangle.2.circlepath`、`cpu`、`hammer`、`xmark.octagon`、`trash`、`safari`、`bell.badge`、`eye`、`eye.slash`、`circle.lefthalf.filled`、`display`、`moon.zzz`、`arrow.down.right.and.arrow.up.left`、`plus`、`minus.circle.fill`、`arrow.clockwise` 全部 OK |
| 本地化键手写错误导致 JSON 损坏 | 已用 `json.load` 复核；出错则 `git checkout Localizable.xcstrings` |
| 整体回滚 | `git checkout -- "App Helper/RulesView.swift" "App Helper/MainAppView.swift" "App Helper/App_HelperApp.swift" Localizable.xcstrings` |

---

## 7. 交付物

| 文件 | 变化 |
|---|---|
| `App Helper/RulesView.swift` | +369 / −（重写视图层，逻辑不变） |
| `App Helper/MainAppView.swift` | 工具栏改原生 segmented |
| `App Helper/App_HelperApp.swift` | 删除 95 行死代码（`AHStyle` / `AHTabPicker` / `iconView`） |
| `Localizable.xcstrings` | +14 键、17 处补注释 |
| `docs/ui-redesign-b-plan.md` | 本文件 |

**未改动**：所有 `@Default` 键、`SystemWatcher`、`GlobalShortcutManager`、`LogProvider`、
`HDRReader` 逻辑、菜单栏行为。

---

# 追加：Logs 页面美化

**状态：已执行完成，Debug 编译通过（改动文件 0 warning）。**

## 8.1 现状问题

| # | 问题 | 证据 |
|---|---|---|
| 1 | 行内只有「时间 + 文本」，两者同字号同字重，几百条记录无法扫读 | 原 `LogView.swift:22-26` |
| 2 | 没有按天分组，`Sep 19` 重复出现在每一行 | 截图可见 |
| 3 | 文本靠右对齐（`HStack { Text; Spacer; Text }`），长短不一时参差不齐 | 原 `:22-26` |
| 4 | 无事件类型区分：退出 / 启动 / 清理 / 失败 全是一个样子 | 截图可见 |
| 5 | 空态只有一行 `.font(.title)` 的 "No Logs" | 原 `:16-19` |
| 6 | 无搜索，日志只增不减，也没有清空入口 | 无 |
| 7 | `Font` 无等宽数字，时间列对不齐 | 原 `:23` |
| 8 | 工具栏 segmented 用 `Label` 在 macOS 上被渲染成纯图标（ruler / clock），无法辨认 | 截图可见，上一轮改动引入的回归 |

## 8.2 改动

```swift
if logs.isEmpty        → AHLogEmptyState(tray, "No Logs", 说明)
else if dayGroups.isEmpty → AHLogEmptyState(magnifyingglass, "No matching logs.", 说明)
else                   → List { ForEach(dayGroups) { Section { AHLogRow } header: AHLogDayHeader } }
                         .listStyle(.inset(alternatesRowBackgrounds: true))
```

- **按天分组**：`Dictionary(grouping:)` + `Calendar.startOfDay`，`Section` 标题显示
  「今天 / 昨天 / 9月19日 / 2025年9月19日」，并带一个当日条数胶囊
- **事件类型图标**：`AHLogKind` 通过 `AHAction.*.localizedString` 后缀与
  `SystemWatcher` 写入的格式串字面量前缀推断类型 →
  start=绿 `play.fill`／restart=蓝 `arrow.clockwise`／quit=灰 `stop.fill`／
  cleanup=青 `trash`／failure=红 `exclamationmark.triangle.fill`／warning=橙 `bolt.fill`
- **行布局**：`图标徽章 · 文本(可选中) · Spacer · 时间`，时间 `.monospacedDigit()` + `.secondary`
- **搜索**：`NSSearchField`（`NSViewRepresentable` 包装）放入工具栏，实时过滤；
  用原生 AppKit 搜索框而非 `.searchable`，因为本窗口没有 `NavigationStack` 祖先
- **清空**：工具栏垃圾桶按钮 + `confirmationDialog` 二次确认；
  用 `NSBatchDeleteRequest` + `mergeChanges(fromRemoteContextSave:)` 保证
  `@FetchRequest` 同步刷新
- **工具栏 segmented 回归修复**：`Label(...)` → `Text(tab.localizedString)`，
  让 macOS 显示 "Rules" / "Logs" 文字而非难以辨认的纯图标
- 顺带删除已无引用的 `AHTab.sfSymbolName`

## 8.3 新增本地化键（共 10 个）

| Key (en) | zh-Hans |
|---|---|
| `Today` | 今天 |
| `Yesterday` | 昨天 |
| `Search logs` | 搜索日志 |
| `Clear Logs` | 清空日志 |
| `Clear` | 清空 |
| `Clear All Logs?` | 清空所有日志？ |
| `This deletes every log entry and cannot be undone.` | 这将删除全部日志记录，且无法撤销。 |
| `No matching logs.` | 没有匹配的日志。 |
| `Try a different search term.` | 换个关键词试试。 |
| `Matched rules and cleanup events will show up here.` | 规则命中与清理事件会显示在这里。 |

## 8.4 顺带修正的既有错误译文

原 zh-Hans 译文存在明显错译，一并在本次修正：

| Key | 原译文 | 新译文 |
|---|---|---|
| `quit` | 辞去 | 已退出 |
| `failed` | 失败的 | 失败 |
| `Rule Applied` | 已应用的规则 | 规则已生效 |
| `started` | 已开始 | 已启动 |
| `restarted` | 重新启动 | 已重启 |

> 注意：旧日志是用旧译文写入的自由文本，切换语言或本次改译文后，历史条目的事件图标会
> 退化为默认的 `info` 图标（文字本身不受影响）。这是日志表无结构化类型字段的固有限制。

## 8.5 追加交付物

| 文件 | 变化 |
|---|---|
| `App Helper/LogView.swift` | 重写（+347 行） |
| `App Helper/MainAppView.swift` | segmented 改回文字标签 |
| `App Helper/App_HelperApp.swift` | 删除 `AHTab.sfSymbolName` |
| `Localizable.xcstrings` | +10 键、5 处译文修正 |
| `App Helper.xcodeproj/project.pbxproj` | **未由本次改动触碰**；06:48 的 `MARKETING_VERSION 2.6.2→2.7.0` / `CURRENT_PROJECT_VERSION 92→93` 是用户在 Xcode 中的操作 |
