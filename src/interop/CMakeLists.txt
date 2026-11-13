# This target is independent of Rime headers, loading policy and UI helpers.
add_library(lua_interop STATIC state.cc compat.c utf8.c)
target_compile_features(lua_interop PUBLIC cxx_std_17)
target_include_directories(lua_interop PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(lua_interop PUBLIC lua5.4)
find_package(Threads REQUIRED)
target_link_libraries(lua_interop PUBLIC Threads::Threads ${CMAKE_DL_LIBS})
target_compile_definitions(lua_interop PUBLIC $<$<CONFIG:Debug>:DEBUG>)
set_target_properties(lua_interop PROPERTIES POSITION_INDEPENDENT_CODE ON)
