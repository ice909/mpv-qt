cmake_minimum_required(VERSION 3.16)

project(lzc-player VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick OpenGL Widgets)

qt_standard_project_setup(REQUIRES 6.8)

set(MPV_ROOT "" CACHE PATH "Root directory of a prebuilt libmpv package")
set(MPV_INCLUDE_DIR "" CACHE PATH "Directory containing mpv/client.h")
set(MPV_LIBRARY "" CACHE FILEPATH "Path to the libmpv import/static library")
set(MPV_RUNTIME_LIBRARY "" CACHE FILEPATH "Path to the libmpv runtime shared library")
set(MPV_RUNTIME_DLL "" CACHE FILEPATH "Path to the libmpv runtime DLL")
set(MPV_BUNDLE_SEARCH_PATHS "" CACHE STRING "Semicolon-separated directories used to locate libmpv runtime dependencies for bundling")

set(mpv_target "")
set(mpv_runtime_dll "")
set(mpv_runtime_library "")
set(mpv_bundle_search_paths "")

if (MPV_ROOT)
    if (NOT MPV_INCLUDE_DIR)
        set(MPV_INCLUDE_DIR "${MPV_ROOT}/include")
    endif()

    if (WIN32)
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
    else()
        if (NOT MPV_LIBRARY)
            find_library(MPV_LIBRARY
                NAMES mpv libmpv
                PATHS
                    "${MPV_ROOT}"
                    "${MPV_ROOT}/lib"
                    "${MPV_ROOT}/lib64"
                    "${MPV_ROOT}/Frameworks"
                NO_DEFAULT_PATH
            )
        endif()

        if (NOT MPV_RUNTIME_LIBRARY)
            find_file(MPV_RUNTIME_LIBRARY
                NAMES libmpv.dylib libmpv.2.dylib libmpv.so libmpv.so.2
                PATHS
                    "${MPV_ROOT}"
                    "${MPV_ROOT}/lib"
                    "${MPV_ROOT}/lib64"
                    "${MPV_ROOT}/Frameworks"
                NO_DEFAULT_PATH
            )
        endif()
    endif()
endif()

if (WIN32 AND MPV_RUNTIME_DLL AND NOT MPV_RUNTIME_LIBRARY)
    set(MPV_RUNTIME_LIBRARY "${MPV_RUNTIME_DLL}")
endif()

if (MPV_ROOT AND NOT MPV_BUNDLE_SEARCH_PATHS)
    list(APPEND mpv_bundle_search_paths
        "${MPV_ROOT}"
        "${MPV_ROOT}/bin"
        "${MPV_ROOT}/lib"
        "${MPV_ROOT}/lib64"
        "${MPV_ROOT}/Frameworks"
    )
elseif (MPV_BUNDLE_SEARCH_PATHS)
    set(mpv_bundle_search_paths "${MPV_BUNDLE_SEARCH_PATHS}")
endif()

if (MPV_INCLUDE_DIR)
    if (WIN32 AND MPV_LIBRARY)
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
        set(mpv_runtime_library "${MPV_RUNTIME_LIBRARY}")
    elseif ((APPLE OR UNIX) AND (MPV_LIBRARY OR MPV_RUNTIME_LIBRARY))
        if (NOT MPV_LIBRARY)
            set(MPV_LIBRARY "${MPV_RUNTIME_LIBRARY}")
        endif()

        if (NOT MPV_RUNTIME_LIBRARY)
            set(MPV_RUNTIME_LIBRARY "${MPV_LIBRARY}")
        endif()

        add_library(mpv::mpv SHARED IMPORTED)
        set_target_properties(mpv::mpv PROPERTIES
            IMPORTED_LOCATION "${MPV_RUNTIME_LIBRARY}"
            INTERFACE_INCLUDE_DIRECTORIES "${MPV_INCLUDE_DIR}"
        )

        set(mpv_target mpv::mpv)
        set(mpv_runtime_library "${MPV_RUNTIME_LIBRARY}")
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
    src/app/playerwindow.cpp
    src/app/playerwindow.h
    src/player/videoplayerview.cpp
    src/player/videoplayerview.h
    src/player/mpvwindowrenderer.cpp
    src/player/mpvwindowrenderer.h
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
        Qt6::Widgets
)

set_target_properties(lzc-player PROPERTIES
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

if (APPLE)
    set_target_properties(lzc-player PROPERTIES
        BUILD_RPATH "@executable_path/../Frameworks"
        INSTALL_RPATH "@executable_path/../Frameworks"
    )
endif()

if (WIN32 AND mpv_runtime_dll)
    add_custom_command(TARGET lzc-player POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${mpv_runtime_dll}"
            "$<TARGET_FILE_DIR:lzc-player>"
        VERBATIM
    )
endif()

if (APPLE AND mpv_runtime_library)
    list(REMOVE_DUPLICATES mpv_bundle_search_paths)
    list(FILTER mpv_bundle_search_paths EXCLUDE REGEX "^$")
    list(JOIN mpv_bundle_search_paths "|" mpv_bundle_search_paths_arg)

    add_custom_command(TARGET lzc-player POST_BUILD
        COMMAND ${CMAKE_COMMAND}
            -DAPP_BUNDLE=$<TARGET_BUNDLE_DIR:lzc-player>
            -DSEARCH_DIRS=${mpv_bundle_search_paths_arg}
            -DEXTRA_LIBS=${mpv_runtime_library}
            -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/fixup_macos_bundle.cmake"
        VERBATIM
    )
endif()

include(GNUInstallDirs)
install(TARGETS lzc-player
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

install(FILES assets/linux/lzc-player.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
)

install(FILES assets/linux/lzc-player.svg
    DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
)

if (WIN32 AND mpv_runtime_dll)
    install(FILES "${mpv_runtime_dll}"
        DESTINATION ${CMAKE_INSTALL_BINDIR}
    )
endif()

if (APPLE AND mpv_runtime_library)
    list(JOIN mpv_bundle_search_paths "|" mpv_bundle_search_paths_arg)
    install(CODE
        "set(APP_BUNDLE \"\${CMAKE_INSTALL_PREFIX}/lzc-player.app\")\n\
set(SEARCH_DIRS \"${mpv_bundle_search_paths_arg}\")\n\
set(EXTRA_LIBS \"${mpv_runtime_library}\")\n\
include(\"${CMAKE_CURRENT_SOURCE_DIR}/cmake/fixup_macos_bundle.cmake\")"
    )
endif()
