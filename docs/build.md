# lzc-player 编译指南

本文档说明如何在 macOS、Windows、Linux 上编译 `lzc-player`。

当前项目使用：

- CMake
- Qt 6.8+
- libmpv
- Ninja

如果你主要目标是在 macOS 上使用手动下载的 `libmpv.dylib` 编译，请优先看“macOS 编译”一节。

## 1. 通用要求

### 1.1 源码目录

假设项目目录为：

```text
~/Desktop/lzc-player
```

下文命令默认都在项目根目录执行。

### 1.2 Qt 要求

项目当前要求：

- Qt 6.8 或更高版本
- 组件至少包含：
  - `Core`
  - `Gui`
  - `Quick`
  - `OpenGL`
  - `Widgets`

### 1.3 libmpv 要求

项目编译时需要：

- 头文件
  - `mpv/client.h`
  - `mpv/render.h`
  - `mpv/render_gl.h`
  - `mpv/stream_cb.h`
- 运行库
  - macOS: `libmpv.dylib`
  - Windows: `libmpv-2.dll` 和对应 import library
  - Linux: 系统安装的 `libmpv`

如果你下载的 macOS 包里只有 `libmpv.dylib`，没有 `include/mpv/*.h`，那么不能直接编译，必须额外补齐头文件。

## 2. macOS 编译

### 2.1 前置依赖

你需要准备：

- Xcode Command Line Tools
- CMake
- Ninja
- Qt 6.8+
- 一套可用的 `libmpv` 开发文件

可先检查工具是否存在：

```bash
xcode-select -p
cmake --version
ninja --version
```

### 2.2 推荐目录结构

macOS 下推荐把 mpv 文件整理成以下结构：

```text
third_party/mpv/macos/
  include/mpv/client.h
  include/mpv/render.h
  include/mpv/render_gl.h
  include/mpv/stream_cb.h
  lib/libmpv.dylib
  lib/*.dylib
```

说明：

- `include/mpv` 放 mpv 头文件
- `lib/libmpv.dylib` 是主库
- `lib/*.dylib` 放 `libmpv.dylib` 依赖的非系统动态库
- `/System/Library` 和 `/usr/lib` 的系统库不需要拷贝

建议把头文件和 `libmpv.dylib` 尽量保持同版本或同来源。

### 2.3 确认 `libmpv.dylib` 依赖

先看库的基本依赖：

```bash
otool -L third_party/mpv/macos/lib/libmpv.dylib
```

查看 install name：

```bash
otool -D third_party/mpv/macos/lib/libmpv.dylib
```

如果想看库里可能包含的版本字符串：

```bash
strings third_party/mpv/macos/lib/libmpv.dylib | rg -i 'mpv|libmpv|version|git'
```

你要重点确认：

- 是否依赖了额外的 `.dylib`
- 这些依赖库是否已经放在 `third_party/mpv/macos/lib`

### 2.4 如果缺少头文件

如果你的 macOS mpv 包只有 `libmpv.dylib`，没有头文件：

1. 找同版本或接近版本的 mpv 开发头文件
2. 把 `include/mpv/*.h` 放到 `third_party/mpv/macos/include/mpv/`
3. 至少补齐这 4 个头：
   - `client.h`
   - `render.h`
   - `render_gl.h`
   - `stream_cb.h`

不要直接拿和当前动态库差异很大的最新头文件去配旧库。

### 2.5 Qt 路径

你需要知道 Qt 安装根目录，例如：

```text
/Users/yourname/Qt/6.8.3/macos
```

这个路径会传给 `CMAKE_PREFIX_PATH`。

### 2.6 配置命令

在项目根目录执行：

```bash
cmake -S . -B build/macos \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/Users/yourname/Qt/6.8.3/macos \
  -DMPV_ROOT=$PWD/third_party/mpv/macos
```

如果你的头文件或动态库目录不是默认结构，也可以手工覆盖：

```bash
cmake -S . -B build/macos \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/Users/yourname/Qt/6.8.3/macos \
  -DMPV_ROOT=$PWD/third_party/mpv/macos \
  -DMPV_INCLUDE_DIR=$PWD/third_party/mpv/macos/include \
  -DMPV_LIBRARY=$PWD/third_party/mpv/macos/lib/libmpv.dylib \
  -DMPV_RUNTIME_LIBRARY=$PWD/third_party/mpv/macos/lib/libmpv.dylib
```

如果 `libmpv.dylib` 的依赖库不在同一个目录，可以额外指定搜索路径：

```bash
-DMPV_BUNDLE_SEARCH_PATHS="/path/a;/path/b;/path/c"
```

### 2.7 编译

```bash
cmake --build build/macos --parallel
```

### 2.7.1 推荐脚本

仓库提供了一个 macOS 一键构建脚本：

```bash
QT_ROOT=/Users/yourname/Qt/6.8.3/macos \
bash scripts/build-macos.sh
```

默认行为：

- 使用 `third_party/mpv/macos` 作为 `MPV_ROOT`
- 显式传入 `MPV_INCLUDE_DIR`、`MPV_LIBRARY`、`MPV_RUNTIME_LIBRARY`
- 构建 `build/macos/lzc-player.app`
- 调用 `macdeployqt -qmldir=qml`
- 补齐 `QtQuickControls2.framework`、`QtQuickControls2Impl.framework`、`QtQuickTemplates2.framework`
- 补齐 `QtSvg.framework`、`QtSvgWidgets.framework`
- 补齐 `PlugIns/imageformats/libqsvg.dylib`、`PlugIns/iconengines/libqsvgicon.dylib`
- 批量修正 `Contents/PlugIns/*.dylib` 的 `rpath`

可选环境变量：

- `QT_ROOT=/Users/yourname/Qt/6.8.3/macos`
- `MPV_ROOT=/absolute/path/to/mpv-package`
- `BUILD_DIR=/absolute/path/to/build/macos`
- `CLEAN_BUILD_DIR=1`
- `RUN_MACDEPLOYQT=0`
- `COPY_EXTRA_QT_RUNTIME=0`
- `FIX_QT_PLUGIN_RPATHS=0`

如果脚本检测到 `libmpv.dylib` 带有 `-Dgl=disabled`，会直接失败，因为当前项目使用的是 `mpv/render_gl.h` 路线，与这种构建不兼容。

### 2.8 产物位置

通常生成的 `.app` 位于：

```text
build/macos/lzc-player.app
```

可执行文件通常位于：

```text
build/macos/lzc-player.app/Contents/MacOS/lzc-player
```

### 2.9 当前构建系统会自动做什么

当你使用 `MPV_ROOT` 或显式指定 `MPV_RUNTIME_LIBRARY` 时，当前 CMake 会在 macOS 上自动做这些事：

- 用预编译 `libmpv.dylib` 参与链接
- 给主程序写入 `@executable_path/../Frameworks` 的 `rpath`
- 在构建后把 `libmpv.dylib` 和能从搜索目录中解析到的依赖复制到：
  - `lzc-player.app/Contents/Frameworks`
- 修正 bundle 内部依赖，使 `.app` 更适合独立运行

### 2.10 运行前自检

可以检查最终 `.app` 中是否包含 mpv 运行库：

```bash
find build/macos/lzc-player.app/Contents/Frameworks -maxdepth 1 -type f
```

查看主程序对动态库的引用：

```bash
otool -L build/macos/lzc-player.app/Contents/MacOS/lzc-player
```

你应当能看到类似：

```text
@executable_path/../Frameworks/libmpv.dylib
```

### 2.11 常见错误

#### 1. `fatal error: 'mpv/client.h' file not found`

说明没有找到头文件。检查：

- `third_party/mpv/macos/include/mpv/client.h` 是否存在
- `-DMPV_ROOT` 是否传对
- 如果结构不是默认的，是否显式传了 `-DMPV_INCLUDE_DIR`

#### 2. CMake 提示找不到 `libmpv`

检查：

- `third_party/mpv/macos/lib/libmpv.dylib` 是否存在
- 是否传了 `-DMPV_RUNTIME_LIBRARY`
- `MPV_ROOT` 下是否确实包含 `lib` 或 `Frameworks`

#### 3. 程序启动时报动态库缺失

先看：

```bash
otool -L build/macos/lzc-player.app/Contents/MacOS/lzc-player
find build/macos/lzc-player.app/Contents/Frameworks -maxdepth 1 -type f
```

常见原因：

- `libmpv.dylib` 的某个依赖没放进 `third_party/mpv/macos/lib`
- 依赖库虽然存在，但不在 `MPV_BUNDLE_SEARCH_PATHS` 里

#### 4. 编译通过但运行崩溃

优先怀疑：

- 头文件版本与 `libmpv.dylib` 版本不匹配
- Qt 或 OpenGL 运行环境异常

这类情况先确认头文件来源是否与动态库匹配。

## 3. Windows 编译

项目已提供 MSYS2 构建脚本。

### 3.1 前置环境

建议使用：

- MSYS2 MinGW64 shell
- Qt for MSYS2 或等价可用的 Qt 6.8+
- 一套 Windows `libmpv` 开发包

推荐目录结构：

```text
third_party/mpv/
  include/mpv/*.h
  libmpv.dll.a
  libmpv-2.dll
```

### 3.2 直接构建

在 `MSYS2 MinGW64` shell 中执行：

```bash
bash scripts/build-msys2.sh
```

如果 Qt 或 mpv 不在默认位置，可传环境变量：

```bash
QT_ROOT=/mingw64 MPV_ROOT=$PWD/third_party/mpv bash scripts/build-msys2.sh
```

### 3.3 产物

默认产物位于：

```text
build/msys2-mingw64/lzc-player.exe
```

## 4. Linux 编译

Linux 默认通过 `pkg-config` 查找系统安装的 `mpv`。

### 4.1 前置依赖

你需要安装：

- CMake
- Ninja
- Qt 6.8+
- `pkg-config`
- `libmpv` 开发包

在 Debian/Ubuntu 系一般需要类似：

```bash
sudo apt install cmake ninja-build pkg-config qt6-base-dev qt6-declarative-dev libmpv-dev
```

### 4.2 配置与构建

```bash
cmake -S . -B build/linux -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/linux --parallel
```

### 4.3 产物

可执行文件通常位于：

```text
build/linux/lzc-player
```

### 4.4 AppImage 打包

仓库也提供 Linux 打包脚本：

```bash
bash scripts/package-linux.sh
```

该脚本依赖：

- `linuxdeployqt`
- `appimagetool`

## 5. 快速排查清单

如果编译失败，先检查这几项：

1. Qt 版本是否至少为 6.8
2. CMake 是否找到 `Qt6::Core`、`Qt6::Quick`、`Qt6::OpenGL`
3. macOS/Windows 下是否同时具备 mpv 头文件和运行库
4. macOS 下 `libmpv.dylib` 的依赖库是否都在 bundle 搜索路径内
5. Linux 下 `pkg-config --modversion mpv` 是否能正常输出版本

## 6. 建议的 macOS 最小工作流

如果你只想尽快在 macOS 上编译成功，直接按下面做：

1. 准备 Qt 6.8+
2. 把 mpv 整理为：

```text
third_party/mpv/macos/include/mpv/*.h
third_party/mpv/macos/lib/libmpv.dylib
third_party/mpv/macos/lib/*.dylib
```

3. 执行配置：

```bash
cmake -S . -B build/macos \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/Users/yourname/Qt/6.8.3/macos \
  -DMPV_ROOT=$PWD/third_party/mpv/macos
```

4. 执行构建：

```bash
cmake --build build/macos --parallel
```

5. 检查 bundle：

```bash
otool -L build/macos/lzc-player.app/Contents/MacOS/lzc-player
find build/macos/lzc-player.app/Contents/Frameworks -maxdepth 1 -type f
```
