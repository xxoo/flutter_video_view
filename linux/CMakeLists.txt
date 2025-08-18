cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "video_view")
project(${PROJECT_NAME} LANGUAGES C)

set(PLUGIN_NAME "video_view_plugin")

add_library(${PLUGIN_NAME} SHARED
  "video_view_plugin.c"
)

apply_standard_settings(${PLUGIN_NAME})
pkg_check_modules(mpv REQUIRED IMPORTED_TARGET mpv)
pkg_check_modules(icuuc REQUIRED IMPORTED_TARGET icu-uc)

target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::GTK
  PkgConfig::mpv
  PkgConfig::icuuc
)

set(video_view_bundled_libraries
  ""
  PARENT_SCOPE
)