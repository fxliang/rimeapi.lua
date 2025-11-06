cmake_minimum_required(VERSION 3.16)

project(rimeapi.lua LANGUAGES C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Choose the type of build" FORCE)
endif()

include(CMakeParseArguments)

if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
endif()

function(apply_common_settings target)
  set(options LINK_LUA)
  cmake_parse_arguments(APPLY "${options}" "" "" ${ARGN})

  target_compile_features(${target} PRIVATE cxx_std_17)

  if(NOT WIN32)
    target_compile_options(${target} PRIVATE
      $<$<COMPILE_LANGUAGE:C>:-fPIC>
      $<$<COMPILE_LANGUAGE:CXX>:-fPIC>)
  endif()

  if(APPLE OR DEFINED ENV{TERMUX_VERSION})
    target_compile_definitions(${target} PRIVATE RTLD_DEEPBIND=0)
  endif()

  target_compile_definitions(${target} PRIVATE
    RIME_EXPORTS
    $<$<CONFIG:Debug>:DEBUG>
    $<$<NOT:$<CONFIG:Debug>>:NDEBUG>)

  if(WIN32)
    target_include_directories(${target} PRIVATE ${CMAKE_SOURCE_DIR}/include)

    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
      target_link_directories(${target} PRIVATE ${CMAKE_SOURCE_DIR}/lib64)
    else()
      target_link_directories(${target} PRIVATE ${CMAKE_SOURCE_DIR}/lib)
    endif()

    if(MSVC)
      target_compile_options(${target} PRIVATE
        $<$<COMPILE_LANGUAGE:C>:/utf-8>
        $<$<COMPILE_LANGUAGE:CXX>:/utf-8>
        $<$<CONFIG:Debug>:/Od>
        $<$<CONFIG:Release>:/O2>
        $<$<CONFIG:RelWithDebInfo>:/O2>
        $<$<CONFIG:MinSizeRel>:/O2>)
    else()
      target_link_libraries(${target} PRIVATE pthread dl)
      target_compile_options(${target} PRIVATE
        $<$<CONFIG:Debug>:-g>
        $<$<CONFIG:Debug>:-O0>
        $<$<NOT:$<CONFIG:Debug>>:-O2>)
      # ${target} link static runtime
      target_compile_options(${target} PRIVATE
        $<$<COMPILE_LANGUAGE:C>:-static-libgcc -static-libstdc++ -static>
        $<$<COMPILE_LANGUAGE:CXX>:-static-libgcc -static-libstdc++ -static>)
      # ${target} link static
      target_link_options(${target} PRIVATE "-static")
    endif()

  else()
    target_link_libraries(${target} PRIVATE pthread dl)
    target_compile_options(${target} PRIVATE
      $<$<CONFIG:Debug>:-g>
      $<$<CONFIG:Debug>:-O0>
      $<$<NOT:$<CONFIG:Debug>>:-O2>)

    if(APPLE)
      target_link_options(${target} PRIVATE "-Wl,-rpath,@loader_path")
    else()
      target_link_options(${target} PRIVATE "-Wl,-rpath,$ORIGIN")
    endif()
  endif()

  if(APPLY_LINK_LUA)
    add_dependencies(${target} lua5.4)
    target_link_libraries(${target} PRIVATE lua5.4)
  endif()
endfunction()

file(GLOB CORE_C_SOURCES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/*.c")
file(GLOB CORE_CXX_SOURCES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/src/*.cc")

add_library(core OBJECT ${CORE_C_SOURCES} ${CORE_CXX_SOURCES})
if(NOT WIN32)
  set_target_properties(core PROPERTIES POSITION_INDEPENDENT_CODE ON)
endif()
apply_common_settings(core)
target_include_directories(core PRIVATE ${CMAKE_SOURCE_DIR}/lua5.4)

add_executable(lua lua5.4/onelua.c)
target_compile_features(lua PRIVATE c_std_99)
if (NOT WIN32)
  target_compile_definitions(lua PRIVATE LUA_USE_LINUX)
  target_compile_options(lua PRIVATE -fPIC)
  target_link_libraries(lua PRIVATE m)
endif()

add_library(lua5.4 STATIC lua5.4/onelua.c)
target_compile_features(lua5.4 PRIVATE c_std_99)
target_compile_definitions(lua5.4 PUBLIC MAKE_LIB)
target_include_directories(lua5.4 PUBLIC ${CMAKE_SOURCE_DIR}/lua5.4)
if(NOT WIN32)
  target_compile_definitions(lua5.4 PRIVATE LUA_USE_LINUX)
  set_target_properties(lua5.4 PROPERTIES POSITION_INDEPENDENT_CODE ON)
  target_link_libraries(lua5.4 PUBLIC m)
endif()

add_executable(rimeapi.app src/main.cpp)
target_sources(rimeapi.app PRIVATE $<TARGET_OBJECTS:core>)
apply_common_settings(rimeapi.app LINK_LUA)

add_library(rimeapi_lua SHARED src/main.cpp)
target_sources(rimeapi_lua PRIVATE $<TARGET_OBJECTS:core>)
target_compile_definitions(rimeapi_lua PRIVATE BUILD_AS_LUA_MODULE)
set_target_properties(rimeapi_lua PROPERTIES OUTPUT_NAME "rimeapi_lua")
if(NOT WIN32)
  set_target_properties(rimeapi_lua PROPERTIES PREFIX "")
elseif(NOT MSVC)
  set_target_properties(rimeapi_lua PROPERTIES PREFIX "")
endif()
apply_common_settings(rimeapi_lua LINK_LUA)

if(WIN32)
  if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(RIME_DLL_PATH "${CMAKE_SOURCE_DIR}/lib64/rime.dll")
  else()
    set(RIME_DLL_PATH "${CMAKE_SOURCE_DIR}/lib/rime.dll")
  endif()
endif()

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${CMAKE_SOURCE_DIR}" CACHE PATH "Install path prefix" FORCE)
endif()

install(TARGETS lua rimeapi.app
  RUNTIME DESTINATION .)

install(TARGETS rimeapi_lua
  LIBRARY DESTINATION .
  RUNTIME DESTINATION .)

if(WIN32 AND RIME_DLL_PATH AND EXISTS "${RIME_DLL_PATH}")
  install(FILES "${RIME_DLL_PATH}" DESTINATION .)
endif()
