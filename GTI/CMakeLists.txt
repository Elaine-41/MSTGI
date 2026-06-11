cmake_minimum_required(VERSION 3.2)
project(GTI LANGUAGES CXX) 

set(CMAKE_BUILD_TYPE Release)

# Wolverine backend: -DGTI_USE_WOLVERINE=ON to enable Wolverine patch-delete for graph
option(GTI_USE_WOLVERINE "Use Wolverine for graph backend (patch-delete)" OFF)
# SHG backend: -DGTI_USE_SHG=ON to enable SHG (HEDS) with learned shortcuts
option(GTI_USE_SHG "Use SHG (HEDS) for graph backend with learned shortcuts" OFF)

# Wolverine and SHG cannot both be ON
if(GTI_USE_WOLVERINE AND GTI_USE_SHG)
    message(FATAL_ERROR "GTI_USE_WOLVERINE and GTI_USE_SHG cannot be both ON")
endif()

# GTI_N2_EXE_NAME: 当 GTI_USE_WOLVERINE=OFF 且 GTI_USE_SHG=OFF 时
if(NOT GTI_USE_WOLVERINE AND NOT GTI_USE_SHG)
  set(GTI_N2_EXE_NAME "GTI_n2" CACHE STRING "Executable name when building n2 backend (original GTI)")
endif()

set(EXECUTABLE_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/bin)
aux_source_directory(src SRC_LIST)
include_directories(include)

#OpenMP
find_package(OpenMP)
if (OPENMP_FOUND)
    set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OpenMP_C_FLAGS}")
    set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")
else()
    message(FATAL_ERROR "no OpenMP supprot")
endif()

add_definitions (-std=c++11 -O3 -lboost -march=native -Wall -DINFO)
include_directories(${PROJECT_SOURCE_DIR}/extern_libraries/n2/include)
include_directories(${PROJECT_SOURCE_DIR}/extern_libraries/n2/third_party/spdlog/include)
include_directories(${PROJECT_SOURCE_DIR}/extern_libraries/n2/third_party/eigen)
link_directories(${PROJECT_SOURCE_DIR}/extern_libraries/n2/build/lib)

if(GTI_USE_WOLVERINE)
    message(STATUS "GTI: Wolverine backend ENABLED")
    add_definitions(-DGTI_USE_WOLVERINE)
    include_directories(${PROJECT_SOURCE_DIR}/extern_libraries/hnsw_Wolverine)
    set(CMAKE_CXX_STANDARD 17)
elseif(GTI_USE_SHG)
    message(STATUS "GTI: SHG backend ENABLED")
    add_definitions(-DGTI_USE_SHG)
    include_directories(${PROJECT_SOURCE_DIR}/extern_libraries/hnsw_SHG/hnswlib)
    include_directories(${PROJECT_SOURCE_DIR}/extern_libraries/hnsw_SHG)
    set(CMAKE_CXX_STANDARD 17)
else()
    message(STATUS "GTI: n2 backend (default)")
endif()

add_subdirectory(src)