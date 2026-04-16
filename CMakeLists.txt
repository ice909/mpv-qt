cmake_minimum_required(VERSION 3.16)

project(lzc-player VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick OpenGL)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(lzc-player
    src/app/main.cpp
    src/player/mpvobject.cpp
    src/player/mpvobject.h
)

set_target_properties(lzc-player PROPERTIES QT_QML_MODULE_NO_IMPORT_SCAN TRUE)

qt_add_resources(lzc-player qml_resources
    PREFIX "/lzc-player"
    FILES
        qml/Main.qml
        qml/components/ControlButton.qml
        qml/components/PlaybackControlsBar.qml
        qml/components/PlaybackProgressBar.qml
        qml/components/PlaybackSpeedSelector.qml
        qml/components/QualitySelector.qml
        qml/components/SubtitleSelector.qml
        qml/components/VolumeSelector.qml
        qml/utils/PlayerFormat.js
        assets/icons/play.svg
        assets/icons/pause.svg
        assets/icons/seek-backward.svg
        assets/icons/seek-forward.svg
        assets/icons/subtitle.svg
        assets/icons/subtitle-hover.svg
        assets/icons/volume.svg
        assets/icons/volume-small.svg
        assets/icons/volume-mute.svg
        assets/icons/fullscreen.svg
        assets/icons/quit-fullscreen.svg
)

target_include_directories(lzc-player PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

target_compile_definitions(lzc-player
    PRIVATE
        LZC_PLAYER_VERSION="${PROJECT_VERSION}"
)

target_link_libraries(lzc-player
    PRIVATE
        PkgConfig::MPV
        Qt6::Core
        Qt6::Gui
        Qt6::OpenGL
        Qt6::Quick
)

set_target_properties(lzc-player PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

include(GNUInstallDirs)
install(TARGETS lzc-player
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
