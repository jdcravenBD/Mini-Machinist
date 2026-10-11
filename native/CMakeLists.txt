# Builds the native item physics (ItemWorld) as a Godot extension into ../bin/.
#
#   cmake -S native -B native/build -G "Visual Studio 17 2022" -A x64
#   cmake --build native/build --config Release
#
# Close the Godot editor first: it locks the DLL while the project is open.

cmake_minimum_required(VERSION 3.17)
project(mini_machinist_physics LANGUAGES CXX)

set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot API version to build against")
add_subdirectory(godot-cpp)

add_library(physics SHARED src/register_types.cpp src/item_world.cpp src/pixel_world.cpp src/item_world.h)
target_link_libraries(physics PRIVATE godot-cpp)

# The physics must give bit-identical results everywhere, so never fuse multiply and add.
if(MSVC)
    target_compile_options(physics PRIVATE /fp:precise)
else()
    target_compile_options(physics PRIVATE -ffp-contract=off)
endif()

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set(OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../bin/")

set_target_properties(
    physics
    PROPERTIES
        CXX_STANDARD 17
        CXX_EXTENSIONS OFF
        POSITION_INDEPENDENT_CODE ON
        LIBRARY_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        RUNTIME_OUTPUT_DIRECTORY "$<1:${OUTPUT_DIR}>"
        ARCHIVE_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/lib>"
        PDB_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/pdb>"
        PREFIX ""
        OUTPUT_NAME "mini_machinist_physics${GODOTCPP_SUFFIX}"
)
