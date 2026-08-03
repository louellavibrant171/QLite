# QLite

一个原生的 macOS SQLite 数据库查看器：打开数据库、管理数据表与表结构、编辑表中数据、
执行复杂查询，并且支持在 Finder 中用 QuickLook 直接预览 `.sqlite` 文件。

[English](README.md) · [更新日志](CHANGELOG.md) · [参与贡献](CONTRIBUTING.md)

## 功能

**浏览与编辑数据**
- 分页浏览（每页 50–1000 行），排序和 `WHERE` 过滤都下推到 SQLite 执行，百万行表也不卡。
- 插入、修改、删除行。优先用 `rowid` 定位行，`WITHOUT ROWID` 表退回主键定位；视图会被
  正确识别为只读。
- NULL、BLOB 和数值类型在表格中区分显示；BLOB 在行编辑器里以 `x'…'` 十六进制字面量往返。

**管理表结构**
- 图形化建表：列类型、主键、自增、非空、唯一、默认值、复合主键、`WITHOUT ROWID`。
- 增加 / 重命名 / 删除列，重命名和删除表，创建和删除索引。
- 「Structure」标签页查看列、外键、索引；「DDL」标签页查看原始 `CREATE` 语句。

**执行查询**
- 支持多语句的 SQL 编辑器，`⌘R` 执行，可查看 `EXPLAIN QUERY PLAN`、耗时和影响行数。
- 查询结果或当前表页可导出为 CSV、TSV、JSON 或 `INSERT` 语句。

**QuickLook**
- 在 Finder 中选中 `.sqlite`/`.db`/`.sqlite3` 文件按空格，即可看到库中的表、字段、行数
  以及若干条示例数据，无需打开应用。
- Finder 缩略图会显示一张数据库卡片，列出前几张表的名字。
- 两个扩展都可以在设置里开关，也可以一键重新注册。

**临时文件（WAL / journal）**
- 读取 `-wal`、`-shm`、`-journal`：已提交到预写日志、但还没合并进主库的数据也能看到，
  应用内和 QuickLook 预览都一样。
- 当这些文件无法就地打开时（只读卷、沙盒中的预览扩展），QLite 会退回到「把整套文件复制到
  临时目录再打开」，仍不行才退回 `immutable` 只读模式，并明确标注当前显示的是最后一次
  合并后的状态。
- 直接打开 `foo.db-wal` 会自动打开 `foo.db`。信息标签页会列出这些文件及其大小，并提供
  **合并 WAL 日志** 操作。

**设置**
- **通用** —— 语言（跟随系统 / English / 简体中文）、是否读取临时文件。
- **文件类型** —— 哪些后缀名算数据库、添加自定义后缀名、把它们绑定为由 QLite 默认打开。
- **QuickLook** —— 分别开关预览和缩略图扩展，并重新向系统注册。

**多语言**
- 支持英文和简体中文，切换后立即生效、无需重启。翻译文件位于
  `Resources/Localization/<语言>.lproj/Localizable.strings`。

**维护**
- `PRAGMA integrity_check`、`VACUUM`，以及包含页大小、编码、日志模式、user_version 的
  数据库信息面板。

## 安装

### 使用发行版

从 [releases 页面](https://github.com/qlite-app/QLite/releases) 下载 `QLite-<版本>.dmg`，
把 **QLite.app** 拖到 **Applications**，然后启动一次，让系统注册 QuickLook 扩展。
也提供 `.pkg` 安装包，它会自动完成扩展注册。

默认使用 ad-hoc 签名。如果 Gatekeeper 拦截首次启动，右键选择「打开」，或执行
`xattr -dr com.apple.quarantine /Applications/QLite.app`。

### 从源码构建

```bash
brew install xcodegen
git clone https://github.com/qlite-app/QLite.git
cd QLite
make run
```

环境要求：macOS 14.4 及以上、Xcode 15.3+（Swift 5.9+）、
[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

### 为什么没有开启沙盒

App Sandbox 只会授予用户选中的那个文件的访问权限，不包含旁边的 `-wal` / `-shm` /
`-journal`，同时也禁止调用 `pluginkit` / `lsregister` 和设置默认打开方式。这三件事恰好都是
QLite 的核心功能，所以应用本体不开启沙盒，并且在 App Store 之外分发；两个 QuickLook 扩展
仍然是沙盒化的。

## 制作安装器

```bash
make dmg    # dist/QLite-<版本>.dmg —— 拖拽式安装
make pkg    # dist/QLite-<版本>.pkg —— 安装到 /Applications 并注册 QuickLook
```

正式分发时先导出签名身份：

```bash
export DEVELOPMENT_TEAM="ABCDE12345"
export CODE_SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)"
export INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (ABCDE12345)"
make pkg
```

只有配置了真实签名身份时，`Scripts/build.sh` 才会开启 hardened runtime。它不能和默认的
ad-hoc 签名一起用：hardened runtime 会启用库校验，要求 bundle 内所有二进制同属一个
Team ID，而 ad-hoc 签名没有 Team ID —— 应用会因为加载不了自己的 `QLiteKit.framework`
而在启动时崩溃。

## 目录结构

```
Sources/QLiteKit/        框架：SQLite 封装、表结构读写、数据存取、查询执行、导出。
                         不含 UI，有完整单元测试。
Sources/QLite/           AppKit + SwiftUI 应用本体。
Sources/QLitePreview/    QuickLook 预览扩展。
Sources/QLiteThumbnail/  QuickLook 缩略图扩展。
Tests/QLiteKitTests/     QLiteKit 单元测试。
Resources/Localization/  en 和 zh-Hans 的 Localizable.strings。
Examples/sample.sqlite   一个小的示例数据库（authors/books），方便上手试用。
Scripts/                 build.sh、make-dmg.sh、make-pkg.sh、check-localization.sh、
                         generate-icon.swift
project.yml              XcodeGen 工程定义（.xcodeproj 由它生成）。
.github/workflows/ci.yml 持续集成配置（见下文）。
```

应用和两个扩展共用 `QLiteKit`，所以 QuickLook 预览显示的内容和应用内完全一致。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘O` / `⌘N` | 打开 / 新建数据库 |
| `⌘1`–`⌘4` | 数据 · 结构 · 查询 · 信息 |
| `⌘T` | 新建表 |
| `⌘I` | 插入行 |
| `⌘R` | 执行查询 |
| `⌘F` | 定位到过滤输入框 |
| `⌘E` | 导出当前结果 |
| `⌘,` | 设置 |
| `⌘↩` | 刷新 |

## 开发

```bash
make project   # 修改 project.yml 或增删文件后重新生成 QLite.xcodeproj
make test      # 运行 QLiteKit 单元测试
make debug     # Debug 构建
make strings   # 检查各语言翻译的 key 是否一致
```

`QLite.xcodeproj` 是生成产物，不纳入版本管理；用 Xcode 打开前先执行 `make project`。

### 新增一种语言

1. 把 `Resources/Localization/en.lproj/Localizable.strings` 复制成
   `Resources/Localization/<语言代码>.lproj/Localizable.strings` 并翻译其中的值。
2. 在 `project.yml` 的 `CFBundleLocalizations` 里加上该语言代码，并在
   [`Sources/QLite/Preferences.swift`](Sources/QLite/Preferences.swift) 的 `AppLanguage`
   里加一个 case。
3. 执行 `make strings`：缺 key 或多 key 都会报错。

### 持续集成

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) 会在推送到 `main`、提交 PR，以及在
Actions 页面手动触发时运行：

- **test** —— 先检查各语言翻译是否同步，再用 XcodeGen 生成工程、跑单元测试，最后做一次
  Release 构建，用来暴露只在开启优化和代码签名时才出现的问题。
- **installers** —— 只在 `v` 开头的 tag 上运行。test 通过后构建 DMG 和 PKG 并作为
  workflow 产物上传，避免发布时用手工打的包。

## 文档

- [CHANGELOG.md](CHANGELOG.md) —— 各版本的变更记录。
- [CONTRIBUTING.md](CONTRIBUTING.md) —— 环境搭建、代码归属、PR 检查项。
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) —— 社区行为准则。
- [LICENSE](LICENSE) —— MIT。

## 许可

MIT，见 [LICENSE](LICENSE)。
