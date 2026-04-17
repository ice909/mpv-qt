cmake_minimum_required(VERSION 3.16)

project(lzc-player VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick OpenGL)

qt_standard_project_setup(REQUIRES 6.8)

set(MPV_ROOT "" CACHE PATH "Root directory of a prebuilt libmpv package")
set(MPV_INCLUDE_DIR "" CACHE PATH "Directory containing mpv/client.h")
set(MPV_LIBRARY "" CACHE FILEPATH "Path to the libmpv import/static library")
set(MPV_RUNTIME_DLL "" CACHE FILEPATH "Path to the libmpv runtime DLL")

set(mpv_target "")
set(mpv_runtime_dll "")

if (WIN32)
    if (MPV_ROOT)
        if (NOT MPV_INCLUDE_DIR)
            set(MPV_INCLUDE_DIR "${MPV_ROOT}/include")
        endif()

        if (NOT MPV_LIBRARY)
            find_library(MPV_LIBRARY
                NAMES mpv libmpv mpv-2 libmpv.dll.a libmpv-2.dll.a mpv.dll.a libmpv.dll
                PATHS
                    "${MPV_ROOT}"
                    "${MPV_ROOT}/lib"
                    "${MPV_ROOT}/lib64"
                    "${MPV_ROOT}/bin"
                NO_DEFAULT_PATH
            )
        endif()

        if (NOT MPV_RUNTIME_DLL)
            find_file(MPV_RUNTIME_DLL
                NAMES libmpv-2.dll mpv-2.dll libmpv.dll mpv.dll
                PATHS
                    "${MPV_ROOT}"
                    "${MPV_ROOT}/bin"
                    "${MPV_ROOT}/lib"
                NO_DEFAULT_PATH
            )
        endif()
    endif()

    if (MPV_INCLUDE_DIR AND MPV_LIBRARY)
        add_library(mpv::mpv SHARED IMPORTED)
        set_target_properties(mpv::mpv PROPERTIES
            IMPORTED_IMPLIB "${MPV_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${MPV_INCLUDE_DIR}"
        )

        if (MPV_RUNTIME_DLL)
            set_target_properties(mpv::mpv PROPERTIES
                IMPORTED_LOCATION "${MPV_RUNTIME_DLL}"
            )
        endif()

        set(mpv_target mpv::mpv)
        set(mpv_runtime_dll "${MPV_RUNTIME_DLL}")
    endif()
endif()

if (NOT mpv_target)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(MPV REQUIRED IMPORTED_TARGET mpv)
    set(mpv_target PkgConfig::MPV)
endif()

if (WIN32 AND NOT mpv_target)
    message(FATAL_ERROR
        "libmpv was not found. Set MPV_ROOT or pass MPV_INCLUDE_DIR and MPV_LIBRARY "
        "when using the official Windows libmpv package.")
endif()

qt_add_executable(lzc-player
    src/app/main.cpp
    src/player/mpvplayerview.cpp
    src/player/mpvplayerview.h
    src/player/mpvplayersession.cpp
    src/player/mpvplayersession.h
    src/player/mpvtrackmapper.cpp
    src/player/mpvtrackmapper.h
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
        qml/components/EpisodeSelector.qml
        qml/components/QualitySelector.qml
        qml/components/SubtitleSelector.qml
        qml/components/VolumeSelector.qml
        qml/utils/PlayerFormat.js
        assets/icons/play.svg
        assets/icons/pause.svg
        assets/icons/seek-backward.svg
        assets/icons/seek-forward.svg
        assets/icons/next-episode.svg
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
        ${mpv_target}
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

if (WIN32 AND mpv_runtime_dll)
    add_custom_command(TARGET lzc-player POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${mpv_runtime_dll}"
            "$<TARGET_FILE_DIR:lzc-player>"
        VERBATIM
    )
endif()

include(GNUInstallDirs)
install(TARGETS lzc-player
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

if (WIN32 AND mpv_runtime_dll)
    install(FILES "${mpv_runtime_dll}"
        DESTINATION ${CMAKE_INSTALL_BINDIR}
    )
endif()
