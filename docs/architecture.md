# lzc-player 架构文档

## 1. 项目概览

`lzc-player` 是一个基于 `Qt 6 + Qt Quick + libmpv` 的桌面视频播放器。

当前实现采用以下分层方式：

- 应用层：负责进程启动、命令行解析、日志初始化、QML 装配。
- 窗口层：负责主窗口生命周期、拖拽打开、系统文件选择，以及把渲染器挂到 `QQuickWindow`。
- 播放视图层：对 QML 暴露播放器能力、播放列表能力，并作为 UI 与 mpv 会话之间的桥接层。
- 播放会话层：直接操作 `libmpv`，负责媒体加载、属性观察、事件处理、轨道切换、外挂字幕注入。
- 渲染层：基于 `libmpv render API` 和 Qt Scene Graph 的 OpenGL 生命周期完成画面输出。
- QML 界面层：负责交互、快捷键、控制栏、空态和加载态显示。

项目当前以单一可执行程序形式组织，没有拆成独立静态库或插件。

## 2. 目录结构

### 顶层目录

- `src/app`：应用启动与主窗口实现。
- `src/player`：播放器核心逻辑、mpv 集成、渲染桥接、轨道映射。
- `src/common`：mpv 与 Qt 之间的通用类型转换辅助。
- `qml`：主界面与各类播放器控件。
- `assets`：图标、Linux 桌面集成资源。
- `scripts`：构建与打包脚本。
- `debian`：Debian 打包配置。
- `docs`：项目文档。

### 关键源码文件

- `src/app/main.cpp`：程序入口，完成启动参数解析、日志安装、QML 上下文注入与主窗口展示。
- `src/app/playerwindow.h/.cpp`：继承 `QQuickView` 的主窗口，处理拖拽和文件选择。
- `src/player/videoplayerview.h/.cpp`：QML 可直接使用的播放器视图对象。
- `src/player/mpvplayersession.h/.cpp`：对 `libmpv` 的封装。
- `src/player/mpvwindowrenderer.h/.cpp`：负责 mpv 的 OpenGL 渲染上下文和帧调度。
- `src/player/mpvtrackmapper.h/.cpp`：把 mpv `track-list` 映射成适合 QML 展示的数据结构。
- `qml/Main.qml`：播放器主页面。

## 3. 构建与运行时依赖

`CMakeLists.txt` 当前直接构建一个可执行文件 `lzc-player`，主要依赖：

- Qt 模块：`Core`、`Gui`、`Quick`、`OpenGL`、`Widgets`
- `libmpv`

运行时图形接口固定为 OpenGL：

- `main.cpp` 中调用 `QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL)`
- `MpvWindowRenderer` 基于 `mpv/render_gl.h` 完成渲染上下文接入

Windows 下支持通过 `MPV_ROOT`、`MPV_INCLUDE_DIR`、`MPV_LIBRARY`、`MPV_RUNTIME_DLL` 指定预编译 `libmpv`。

macOS 下也支持通过 `MPV_ROOT` 接入手动下载的 `libmpv` 包，推荐目录结构如下：

- `third_party/mpv/macos/include/mpv/*.h`
- `third_party/mpv/macos/lib/libmpv.dylib`
- `third_party/mpv/macos/lib/*.dylib`

也就是把 `libmpv.dylib` 以及它依赖的非系统 `.dylib` 放在同一个 `lib` 目录，头文件放在 `include/mpv`。配置时可传：

- `-DMPV_ROOT=/absolute/path/to/third_party/mpv/macos`
- 如需手工覆盖，也可传 `-DMPV_INCLUDE_DIR=...`
- 如需手工覆盖，也可传 `-DMPV_LIBRARY=...`
- 如需手工覆盖，也可传 `-DMPV_RUNTIME_LIBRARY=...`

在这种模式下，构建后的 `.app` 会自动把 `libmpv.dylib` 及其可解析到的运行时依赖修正并复制到 `lzc-player.app/Contents/Frameworks`，同时为可执行文件写入 `@executable_path/../Frameworks` 的 `rpath`。

如果不传 `MPV_ROOT`，非 Windows 平台仍默认走 `pkg-config` 查找 `mpv`。

## 4. 模块职责

### 4.1 应用入口层

入口位于 `src/app/main.cpp`，职责包括：

- 设置应用名和版本号。
- 在 Windows 下为 Qt Quick Controls 设置 `Basic` 风格。
- 初始化文件日志，并把 Qt 日志输出同时写入日志文件和标准错误。
- 解析命令行参数和 JSON 配置文件。
- 注册 QML 类型 `VideoPlayerView`。
- 创建 `PlayerWindow`。
- 通过 `QQmlContext` 向 QML 注入启动上下文。

当前注入给 QML 的上下文对象和数据有：

- `playerWindow`：`PlayerWindow` 实例。
- `initialFile`：启动时直接播放的文件或 URL。
- `initialPlaylist`：启动时播放列表。
- `initialStartPosition`：启动 seek 位置。

### 4.2 主窗口层

`PlayerWindow` 继承自 `QQuickView`，是 QML 场景的宿主窗口。

它的职责不是承载播放器状态，而是承载窗口级行为：

- 管理 `MpvWindowRenderer` 生命周期。
- 接收 `VideoPlayerView` 注册和解绑。
- 处理拖拽事件，向 QML 发出 `fileDropped(path)`。
- 打开系统文件选择器，向 QML 发出 `fileSelected(path)`。
- 通过 `dropActive` 属性驱动 QML 中的拖拽高亮态。

窗口层与播放控制逻辑保持解耦，文件打开后的实际播放由 QML 调用 `VideoPlayerView` 完成。

### 4.3 播放视图层

`VideoPlayerView` 是播放器能力对 QML 的统一出口，继承自 `QQuickItem`，但自身不直接绘制画面。

主要职责：

- 持有 `MpvPlayerSession`。
- 把 `MpvPlayerSession` 的状态透传成 QML `Q_PROPERTY`。
- 维护播放列表状态：
  - `playlistItems`
  - `playlistIndex`
  - `playlistCount`
  - `hasPlaylist`
- 在播放列表模式下完成选集切换和自动播下一集。
- 在渲染上下文就绪前暂存待播放文件与外挂字幕列表。
- 在 `windowChanged` 时向 `PlayerWindow` 注册或解绑自身。

可以把它理解为“QML 友好的播放器 Facade”。

### 4.4 播放会话层

`MpvPlayerSession` 是播放器核心状态机，直接面向 `libmpv`。

主要职责：

- 创建并初始化 `mpv_handle`。
- 设置 mpv 运行参数，例如：
  - `hwdec=auto`
  - `gpu-context=auto`
  - `vo=libmpv`
  - `keep-open=yes`
  - `video-sync=display-resample`
  - `interpolation=yes`
- 根据应用属性注入网络相关参数：
  - `lzcPlayerCookie`
  - `lzcPlayerInputIpcServer`
- 观察 mpv 属性变化并同步到 Qt 属性。
- 处理 `FILE_LOADED`、`END_FILE`、`PROPERTY_CHANGE` 等 mpv 事件。
- 支持暂停、seek、倍速、音量、视频轨、字幕轨切换。
- 在媒体加载后注入外挂字幕，并尝试恢复字幕偏好。

这一层不关心具体界面布局，只关心播放器行为和状态同步。

### 4.5 渲染层

`MpvWindowRenderer` 负责把 `VideoPlayerView` 持有的 `mpv_handle` 接入 Qt Scene Graph。

核心职责：

- 在 `beforeRenderPassRecording` 阶段渲染视频帧。
- 在场景图失效时释放 `mpv_render_context`。
- 通过 `mpv_render_context_set_update_callback` 接收 mpv 帧更新通知。
- 调用 `QQuickWindow::update()` 触发下一帧刷新。
- 在首个渲染上下文创建成功后通知 `VideoPlayerView`“可以开始真正加载媒体”。

当前实现中，媒体加载被有意延后到渲染上下文准备完成之后，避免 mpv 在目标渲染环境尚未可用时提前进入播放流程。

### 4.6 QML 界面层

QML 以 `qml/Main.qml` 为根页面，负责：

- 启动时根据 `initialPlaylist` 或 `initialFile` 自动开始播放。
- 空态页面展示和拖拽高亮。
- 加载动画、网络速度角标、控制栏显隐。
- 键盘快捷键映射。
- 文件拖拽和文件选择后的打开逻辑。

`qml/components` 下的组件负责局部交互：

- `PlaybackControlsBar.qml`：底部控制栏容器。
- `PlaybackProgressBar.qml`：进度条与拖动 seek。
- `PlaybackSpeedSelector.qml`：倍速选择。
- `QualitySelector.qml`：视频清晰度选择。
- `SubtitleSelector.qml`：字幕轨选择。
- `VolumeSelector.qml`：音量控制。
- `EpisodeSelector.qml`：播放列表/选集切换。
- `ControlButton.qml`：统一按钮样式。

## 5. 启动流程

当前启动流程如下：

1. `main.cpp` 创建 Qt 应用对象并安装日志。
2. 解析命令行参数和可选 JSON 配置文件。
3. 把 cookie、IPC server 等配置写入 `QApplication` 属性。
4. 注册 `VideoPlayerView` 到 QML 类型系统。
5. 创建 `PlayerWindow`，注入上下文属性并加载 `qrc:/lzc-player/qml/Main.qml`。
6. `Main.qml` 中实例化 `VideoPlayerView`。
7. `VideoPlayerView` 在 `windowChanged` 时注册到 `PlayerWindow`。
8. `PlayerWindow` 把当前 `VideoPlayerView` 交给 `MpvWindowRenderer`。
9. `MpvWindowRenderer` 在首帧渲染准备阶段创建 `mpv_render_context`。
10. `MpvWindowRenderer` 通知 `VideoPlayerView` 渲染上下文已就绪。
11. `VideoPlayerView` 触发待播放文件真正加载。
12. `MpvPlayerSession` 调用 `mpv loadfile`，后续通过属性观察驱动 UI 更新。

## 6. 核心交互链路

### 6.1 文件打开链路

文件可以从三种入口进入：

- 启动参数中的 `file`
- QML 空态页点击“选择文件”
- 拖拽本地文件到窗口

统一链路为：

1. `PlayerWindow` 发出 `fileSelected` 或 `fileDropped`
2. `Main.qml` 调用 `openSelectedFile(path)`
3. `VideoPlayerView::loadFile(path)`
4. `VideoPlayerView::loadMedia(...)`
5. `MpvPlayerSession::loadFile(path)`
6. mpv 开始加载并回推属性变化

### 6.2 播放列表链路

播放列表由 `QVariantList` 驱动，入口包括：

- `--playlist-file`
- `--playlist-json`
- 配置文件中的 `playlist`、`playlistFile`、`playlistJson`

运行时行为：

1. `main.cpp` 把播放列表注入 `initialPlaylist`
2. `Main.qml` 在 `Component.onCompleted` 时调用 `videoPlayer.setPlaylistItems(initialPlaylist)`
3. 若列表非空，立即调用 `playEpisode(0)`
4. `VideoPlayerView` 记录当前 `playlistIndex`
5. 当 `MpvPlayerSession` 发出 `playbackFinished` 时，`VideoPlayerView::handlePlaybackFinished()` 自动播下一集

### 6.3 字幕链路

字幕处理分两层：

- `MpvTrackMapper` 把 `track-list` 中的字幕轨整理成适合 UI 展示的数据结构
- `MpvPlayerSession` 在文件加载后通过 `sub-add` 动态挂载外挂字幕

外挂字幕先由 `VideoPlayerView::normalizedSubtitles()` 规范化，再传给 `MpvPlayerSession`。

## 7. 数据模型约定

### 7.1 播放列表项

当前 `VideoPlayerView::loadEpisodeAtIndex()` 依赖的播放列表项至少需要：

```json
{
  "url": "https://example.com/video.mp4",
  "subtitles": []
}
```

其中：

- `url`：当前集媒体地址，不能为空。
- `subtitles`：可选，外挂字幕列表。

`EpisodeSelector.qml` 直接把 `playlistItems` 作为模型使用，因此业务侧如果希望在 UI 中展示标题、集数等信息，可以继续在对象中附带其他字段，QML 组件会按当前实现自行读取。

### 7.2 外挂字幕项

`VideoPlayerView::normalizedSubtitles()` 当前会保留并规范以下字段：

```json
{
  "id": "sub-1",
  "url": "https://example.com/subtitle.ass",
  "name": "简中",
  "lang": "zh-CN",
  "format": "ass",
  "default": true
}
```

其中真正的硬性要求只有：

- `id`
- `url`

缺少这两个字段的字幕项会被直接忽略。

### 7.3 轨道展示模型

`MpvTrackMapper` 会把 mpv 原始轨道映射成两个主要列表：

- `videoTracks`
- `subtitleTracks`

其中：

- 视频轨包含 `id`、`label`、`detail`、`width`、`height`、`bitrate`
- 字幕轨包含 `id`、`title`、`detail`、`lang`、`source`、`isExternal`、`isDefault`

字幕轨列表默认会额外注入一个关闭选项：

- `id = 0`
- `title = "关闭"`

## 8. 状态同步机制

播放器 UI 主要依赖 `Q_PROPERTY + signal` 驱动。

同步链路如下：

1. `libmpv` 属性变化
2. `MpvPlayerSession::processMpvEvents()`
3. `handlePropertyChange()` / `handleTrackListChange()`
4. 更新 `MpvPlayerSession` 内部状态并发射 Qt 信号
5. `VideoPlayerView` 直接透传对应信号
6. QML 绑定自动刷新

当前已接入的关键状态包括：

- 播放状态：`playing`
- 播放进度：`timePos`、`duration`
- 缓冲状态：`bufferDuration`、`bufferEnd`、`bufferingProgress`
- 网络速度：`networkSpeed`
- 加载与 seek 状态：`loading`、`buffering`、`seeking`
- 音视频轨道：`videoTracks`、`videoId`、`subtitleTracks`、`subtitleId`
- 播放控制：`playbackSpeed`、`volume`
- 控制台状态：`consoleOpen`

## 9. 输入与控制

QML 当前承担了大部分交互编排工作。

### 快捷键

`Main.qml` 中已经接入：

- `MediaNext`：下一集
- `MediaPrevious`：上一集
- `Space`：播放/暂停
- `I`：切换 mpv stats 面板
- `` ` ``：打开 mpv console
- `Esc`：在 console 打开时转发给 mpv

当 mpv console 打开时，部分文本输入和方向键也会被转发到 mpv 的 `keypress` 命令。

### 控制栏显隐

`Main.qml` 基于以下状态控制底部控件显隐：

- 是否有媒体
- 是否正在播放
- 是否有浮层打开
- mpv console 是否打开
- 鼠标 Hover 状态

## 10. 日志与错误处理

当前日志策略在 `main.cpp` 中统一初始化：

- 日志文件默认写到 `QStandardPaths::AppLocalDataLocation`
- 如果该路径不可用，则回退到应用目录下 `logs/lzc-player.log`
- Qt 消息被安装为自定义 `messageHandler`

启动期错误处理包括：

- 配置文件解析失败
- QML 加载失败
- scene graph 错误日志记录
- C++ 未捕获异常弹窗提示

这意味着项目当前已经具备基本的启动诊断能力，但播放中行为异常仍主要依赖 mpv 与 Qt 日志排查。

## 11. 当前架构特点

当前实现有几个比较明确的架构特征：

- C++ 负责底层能力、状态同步和渲染接入。
- QML 负责交互编排和界面展示。
- `VideoPlayerView` 是 C++ 与 QML 之间的核心边界对象。
- `MpvPlayerSession` 与 `MpvWindowRenderer` 分别处理“播放状态”和“画面渲染”，职责分离较清晰。
- 播放列表、外挂字幕等业务数据以 `QVariantList/QVariantMap` 形式跨越 C++ 和 QML，集成成本低，但类型约束相对较弱。

## 12. 后续适合继续演进的方向

如果后续继续扩展项目，当前架构比较适合沿着以下方向演进：

- 为播放列表项、字幕项引入更稳定的结构化类型，降低 `QVariantMap` 字段漂移风险。
- 把启动配置解析从 `main.cpp` 拆成独立模块，减少入口文件体积。
- 为播放器会话增加更明确的错误上报通道，例如媒体加载失败、轨道切换失败、字幕注入失败。
- 视需求把 UI 状态编排从 `Main.qml` 继续拆分，降低主页面复杂度。

以上内容描述的是仓库当前已经落地的实现结构，而不是理想化设计图。
