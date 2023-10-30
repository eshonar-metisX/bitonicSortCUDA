cmake_minimum_required(VERSION 3.18 FATAL_ERROR)
project(bitonicSort)

include(CheckLanguage)
check_language(CUDA)

enable_language(CUDA)

set(CMAKE_CUDA_ARCHITECTURES 8.9)
#set_target_properties( bitonicSort
#                       PROPERTIES CUDA_SEPARABLE_COMPILATION OFF)

include_directories(${CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES})

add_executable(bitonicSort bitonicSort.cu)
