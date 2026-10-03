cmake_minimum_required(VERSION 3.22.1)
project(edge_llm)

# Path to the llama.cpp directory (6 levels up from src/main/cpp)
set(LLAMA_DIR "../../../../../../llama.cpp")

# Important options for compiling llama.cpp for Android
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "Don't build tests")
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "Don't build examples")
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "Don't build server")

# Add llama.cpp as a subdirectory to build it natively
add_subdirectory(${LLAMA_DIR} llama_cpp_build)

# Add our own C++ binding code
add_library(llama_binding SHARED llama_binding.cpp)

# Include the llama.cpp header directories so our binding can find "llama.h"
target_include_directories(llama_binding PRIVATE ${LLAMA_DIR}/include)

# Link our code to the compiled llama.cpp library and Android's native logging
target_link_libraries(llama_binding log llama)
