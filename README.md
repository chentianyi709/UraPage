# UraPage

一个 iOS 原生多源内容阅读器：在同一个 App 内浏览、搜索、阅读与离线管理来自多个独立内容源的作品。仅适配 iPhone（iOS 26.0+），暂无 iPad、Mac 版本，也未适配 iPhone Duo 这类折叠屏机型。

技术上是一份**单 Target 的 SwiftUI 工程**：来源以编译期模块接入，公共层不认识任何具体来源，新增来源只需实现一套契约并在组合根注册。

> 📦 **[下载最新安装包（未签名 IPA）](https://github.com/chentianyi709/UraPage/releases)**：打开最新版本，在 **Assets** 中下载 `.ipa` 文件。

> 本项目仅用于技术学习与研究，不提供、不托管、不分发任何内容。详见文末免责声明。
>
> **代码全部由 AI 生成**，人负责需求、评审与验证；所参考的开源项目见「关于本项目」。

## 功能

**浏览**：来源切换、首页分区推荐、分类与排行列表、更新列表、站内搜索（含筛选菜单、热门词与搜索历史）。

**详情**：作品信息与章节列表、分类／标签／作者跳转、点赞。

**阅读**：连续滚动阅读、章节内页码定位、阅读进度记忆、进入章节后按需加载屏幕外的相邻页面；图片按页缓存，命中缓存时不再请求。

**离线**：整部作品下载（章节选择、暂停／继续／重试）、完成后离线阅读、导出为 ZIP 交系统分享。

**书架**：阅读历史、下载管理、书签（标签／作者／分类，可跨来源跳转回对应列表）。

**外观**：浅色／深色、图片缓存上限与数据清理。

## 环境要求

| 项 | 版本 |
| --- | --- |
| 系统 | iOS 26.0 及以上（受系统支持范围限制） |
| 设备 | **仅 iPhone**；不支持 iPad、Mac（无 iPad 版、无 Mac Catalyst）；**暂未适配 iPhone Duo 等可折叠机型**（展开后的窗口尺寸与多窗口交互），也没做横屏 |
| Xcode | 27.0（Swift 6，complete strict concurrency） |
| XcodeGen | 2.42.0 及以上 |
| 语言 | Swift 6 |

## 构建

```bash
brew install xcodegen
git clone https://github.com/chentianyi709/UraPage.git
cd UraPage
xcodegen generate
open UraPage.xcodeproj
```

工程文件 `.xcodeproj` 由 `project.yml` 生成，**不要手改**；改动 `project.yml` 或 `Configs/` 后重新执行 `xcodegen generate`。

### 签名

真机运行需要有开发者签名：

```bash
cp Configs/Local.xcconfig.example Configs/Local.xcconfig
# 填入自己的 DEVELOPMENT_TEAM
```

`Configs/Local.xcconfig` 已被 `.gitignore` 忽略，**不要提交**。

### 命令行构建

```bash
xcodebuild -project UraPage.xcodeproj \
  -scheme UraPage -configuration Release \
  -destination 'generic/platform=iOS' build
```

## 安装

本项目不在 App Store 发布。每次推 `v*` 标签，CI 会构建**未签名 IPA** 并发布到 [Releases](https://github.com/chentianyi709/UraPage/releases)，文件名形如 `UraPage-v1.1.0-alpha.3-unsigned.ipa`。

下载后需要用开发者证书自行签名再侧载（证书与签名配置不随仓库提供）。也可以从源码自行构建，再用自己的账号签名。

## 分支与版本

| 分支／标签 | 用途 |
| --- | --- |
| `main` | 开发主线，功能与文档改动先落在这里 |
| `release` | 发布分支，包含 GitHub Actions 工作流（`main` 上没有） |
| `v*` 标签 | 触发构建并把未签名 IPA 发布到 Releases（约定从 `release` 打） |

版本号三段式（如 `1.1.0`）写在 `project.yml`。预发布后缀按 SemVer 排序：内测 `-alpha.N`、公测 `-beta.N`，正式版不带后缀。

## 数据与隐私

- **全部数据留在本机**：书架、阅读历史、下载资产与书签存放在 App 的 `Application Support` 目录（各自的 SwiftData 库 + 文件），来源账号凭证存放在系统 Keychain。
- **没有自建服务器**：App 只与使用者自己配置的来源站点通信；本项目不收集使用数据，也不含统计、广告或崩溃上报 SDK。
- 卸载 App 会连同本地数据一起清除；「导出」是使用者主动触发的操作。

## 项目结构

```text
project.yml                # 唯一的工程配置来源（Target、依赖、资源、版本号）
Configs/                   # xcconfig：Base / Debug / Release + 本机签名模板
Targets/UraPageApp/
  Sources/
    App/                   # 组合根、来源注册、Shell、依赖注入
    Navigation/            # 公共路由与导航栈
    Core/                  # 公共模型、来源契约、网络、持久化、下载等非 UI 能力
    CommonUI/              # 通用组件、主题、图片管线
    Features/              # 跨来源业务页面（详情、阅读器、下载、书架）
    SourceModules/         # 各内容源的完整实现，互不引用
  Resources/               # Assets、Info.plist、预览资源
.swiftformat               # 格式化规则
```

被 `.gitignore` 忽略的本地目录不在此列。

依赖方向是单向的：`SourceModules` → `Core` / `CommonUI`；`Core` 与 `CommonUI` 不引用任何具体来源；`App` 负责把它们装配起来。

## 新增一个内容源

来源以编译期模块接入，全部实现放在 `Targets/UraPageApp/Sources/SourceModules/<来源>/`：

- 复用 `Core/SourceRuntime` 的通用流程，不复制公共网络、分页、图片与认证逻辑；
- 只写本源规则：请求与鉴权、DTO／HTML 映射、路由与跨源跳转目标；
- 在 `App/` 的组合根注册模块，不改动 `Core` 与 `CommonUI`；
- 不需要改 `project.yml`：`Sources/` 是整目录纳入，`xcodegen generate` 会带上新文件。

## 开发约定

- 工程由 `project.yml` 生成，不手改 `.xcodeproj`；改完重新 `xcodegen generate`。
- Swift 6 + complete strict concurrency；UI／App 层的非 View 类型标 `@MainActor`，公共基座与来源保持 nonisolated／actor。
- 依赖用 SPM 声明在 `project.yml`，新增前先确认用途、体积与许可证。
- 改动 Swift 后跑 `swiftformat Targets`（只带入自己的改动，不批量重排）。
- 边界：`SourceModules` 可依赖 `Core`／`CommonUI`，反向不允许；各来源之间互不引用。
- 不写单元测试与 UI 测试，改动按模拟器或真机手动回归。

项目内部的开发约定、逐文件职责清单与决策记录保存在作者本地，不随仓库分发。

## 关于本项目

### 代码由 AI 生成

本仓库的 Swift 代码**全部由 AI 编写**，人只负责提需求、做评审、验证行为与决定取舍。这意味着：

- 代码风格、注释与目录结构由 AI 按仓库规则统一产出，一致性较高，但**可能仍存在 AI 生成的疏漏或过度设计**；
- 没有测试覆盖，回归靠人工走查，因此不建议把本项目当作工程实践的样板；
- 架构上的错误归因于人（需求和评审），实现在 AI。

### 参考的开源项目

项目在**接口协议、页面组织与交互形态**上参考了以下开源项目；未直接复制其代码，也未与作者建立任何合作关系：

| 项目 | 是什么 | 参考的内容 |
| --- | --- | --- |
| [raoxwup/haka_comic](https://github.com/raoxwup/haka_comic) | 哔咔（PicACG）第三方跨平台客户端，Flutter | 浏览／详情／阅读的页面组织与交互流程 |
| [hect0x7/JMComic-APK](https://github.com/hect0x7/JMComic-APK) | 禁漫客户端的分发与接口资料整理仓库（GitHub Actions 跟踪 APK 更新） | 平台接口协议与客户端行为 |
| [deretame/Breeze](https://github.com/deretame/Breeze) | Flutter 漫画阅读器，通过插件提供来源支持 | 「阅读器 + 可插拔来源」的分层思路 |

感谢以上作者的开源工作。上述项目与本项目无隶属关系，也未参与本项目开发；版权归各自作者所有，若其中任何作者不希望被列名，请开 Issue 告知，会立即移除。若后续发现存在具体代码片段的沿用，以原项目的许可证为准。

## 已知限制

- **只支持 iOS 26.0 及以上的 iPhone**：没有 iPad 版，不支持 Mac（含 Mac Catalyst／Designed for iPad），也不支持横屏与多窗口，iPad 上一律以兼容模式运行且不在支持范围内。
- **未适配 iPhone Duo 等折叠屏机型**：界面按 iPhone 竖屏尺寸设计，展开／折叠切换带来的窗口变化与多窗口分屏没有对应布局，可能出现拉伸或留白，未做针对性验证。
- 不在 App Store 分发，安装包需自行签名；证书过期后要重新签名并重装。
- 内容源由第三方提供，其接口或页面结构变更会导致对应来源暂时不可用，需要更新源码后重新构建。
- 没有崩溃上报，问题定位依赖使用者的描述与截图。
- 书架「收藏」标签页仍是占位（书签是另一套已完成的本地收藏）。

## 反馈

提 Issue 请附上：来源名称、复现步骤、iOS 版本，以及**你从哪个 Release 标签安装的**（如 `v1.1.0-alpha.3`）。没有崩溃日志，录屏或截图能最快定位问题。

## 第三方依赖

| 库 | 用途 | 许可 |
| --- | --- | --- |
| [Alamofire](https://github.com/Alamofire/Alamofire) | 网络请求与会话管理 | MIT |
| [Kingfisher](https://github.com/onevcat/Kingfisher) | 图片下载与缓存 | MIT |
| [ReerCodable](https://github.com/reers/ReerCodable) | Codable 宏 | MIT |
| [SwiftUIIntrospect](https://github.com/siteline/swiftui-introspect) | SwiftUI 底层视图接入 | MIT |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | HTML 解析 | MIT |

## 免责声明

- 本项目仅为个人学习 iOS 开发与客户端架构的实践项目，**不提供、不托管、不镜像、不分发任何作品内容**，也不提供任何内容源服务。
- 所有内容均来自使用者自行配置的第三方来源，版权归原作者与相应平台所有。
- 本项目**代码**以 MIT 许可发布，但该许可不构成对任何第三方内容、接口或平台的授权；使用前请自行确认所在地区的法律法规与平台条款，使用者自行承担由此产生的全部责任，作者不承担任何连带责任。
- 如相关权利方认为本项目存在侵权，请通过 Issue 联系，作者将及时处理。

## 许可

本项目以 MIT 许可发布。

第三方依赖各自遵循其许可证（见上表）。
