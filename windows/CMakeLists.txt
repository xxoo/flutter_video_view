cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "video_view")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "video_view_plugin")

add_library(${PLUGIN_NAME} SHARED
  "video_view_plugin.cpp"
)
if(MSVC)
  target_compile_options(${PLUGIN_NAME} PRIVATE "$<$<COMPILE_LANGUAGE:CXX>:-D_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR=1>")
endif()

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  windowsapp
)

set(video_view_bundled_libraries
  ""
  PARENT_SCOPE
)