cmake_minimum_required(VERSION 3.13)
project(armn64_av_tests C CXX)

if(NOT ARMN64_SOURCE OR NOT ARMN64_BUILD)
  message(FATAL_ERROR "Set ARMN64_SOURCE and ARMN64_BUILD to a patched source and its Vulkan build")
endif()
find_package(ZLIB REQUIRED)
find_package(Threads REQUIRED)

add_executable(armn64-av-smoke av.c
  "${ARMN64_SOURCE}/libretro/paks.c"
  "${ARMN64_SOURCE}/libretro/games.c"
  "${ARMN64_SOURCE}/libretro/vkpresent.c"
  "${ARMN64_SOURCE}/shared/libretro/options.c")
target_include_directories(armn64-av-smoke PRIVATE
  "${ARMN64_SOURCE}" "${ARMN64_SOURCE}/src" "${ARMN64_SOURCE}/shared"
  "${ARMN64_SOURCE}/shared/libretro" "${ARMN64_SOURCE}/deps/vulkan/include"
  "${ARMN64_BUILD}")
target_compile_definitions(armn64-av-smoke PRIVATE ARMN64_ZIP ARMN64_VULKAN N64_HAS_JIT)
target_compile_options(armn64-av-smoke PRIVATE -UNDEBUG)
target_link_libraries(armn64-av-smoke
  "${ARMN64_BUILD}/libn64.a" "${ARMN64_BUILD}/libglslang.a"
  ZLIB::ZLIB Threads::Threads ${CMAKE_DL_LIBS} m)
set_target_properties(armn64-av-smoke PROPERTIES LINKER_LANGUAGE CXX)

enable_testing()
add_test(NAME native-av COMMAND armn64-av-smoke)
