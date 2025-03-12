#!/bin/bash
set -e

# Default build config
BUILD_TYPE="local"
OS_TYPE="ubuntu2204"
BUILD_DIR="build-local"

# Parse arguments
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  cat <<EOF
HF3FS Build System

Usage: $0 [OPTION]

Options:
  docker-ubuntu2204    Build using Ubuntu 22.04 Docker container
  docker-ubuntu2004    Build using Ubuntu 20.04 Docker container  
  docker-centos9       Build using CentOS 9 Docker container
  -h, --help           Show this help message

Environment:
  - Local builds use host system tools with clang-14
  - Docker builds create isolated environments with version-specific toolchains
  - Build artifacts are stored in separate directories:
    - build-local/              : Default local build
    - build-docker-ubuntu2204/  : Ubuntu 22.04 Docker build
    - build-docker-ubuntu2004/  : Ubuntu 20.04 Docker build
    - build-docker-centos9/     : CentOS 9 Docker build

Examples:
  ./build.sh                    # Local build with clang-14
  ./build.sh docker-ubuntu2204  # Docker build with Ubuntu 22.04
  ./build.sh docker-ubuntu2004  # Docker build with Ubuntu 20.04
  ./build.sh docker-centos9     # Docker build with CentOS 9

EOF
  exit 0
elif [[ "$1" == "docker-ubuntu2204" ]]; then
  BUILD_TYPE="docker"
  OS_TYPE="ubuntu2204"
  BUILD_DIR="build-docker-ubuntu2204"
elif [[ "$1" == "docker-ubuntu2004" ]]; then
  BUILD_TYPE="docker"
  OS_TYPE="ubuntu2004"
  BUILD_DIR="build-docker-ubuntu2004"
elif [[ "$1" == "docker-centos9" ]]; then
  BUILD_TYPE="docker"
  OS_TYPE="centos9" 
  BUILD_DIR="build-docker-centos9"
elif [[ -n "$1" ]]; then
  echo "Error: Invalid option '$1'"
  echo "Try './build.sh --help' for usage information"
  exit 1
fi

# Common build parameters
CPU_CORES=$(nproc)
CMAKE_FLAGS=(
  -DCMAKE_CXX_COMPILER=clang++-14
  -DCMAKE_C_COMPILER=clang-14
  -DCMAKE_BUILD_TYPE=RelWithDebInfo
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
)

local_build() {
  echo "Starting local build..."
  mkdir -p ${BUILD_DIR} && cd ${BUILD_DIR}
  cmake -S . -B ${BUILD_DIR} ${CMAKE_FLAGS[@]}
  cmake --build ${BUILD_DIR} -j\${BUILD_JOBS}
}

docker_build() {
  echo "Starting Docker build for ${OS_TYPE}..."
  DOCKER_IMAGE="hf3fs-dev-${OS_TYPE}"
  docker build -t "${DOCKER_IMAGE}" -f "dockerfile/dev.${OS_TYPE}.dockerfile" .
  docker run --rm \
    -v "${PWD}:/build/src" \
    --cpus="${CPU_CORES}" \
    -e BUILD_JOBS="${CPU_CORES}" \
    "${DOCKER_IMAGE}" /bin/bash -c "
      set -ex
      cd /build/src
      mkdir -p '${BUILD_DIR}'
      cmake -S . -B '${BUILD_DIR}' ${CMAKE_FLAGS[*]}
      cmake --build '${BUILD_DIR}' -j\${BUILD_JOBS}
    "
}

# Execute build
if [[ "${BUILD_TYPE}" == "docker" ]]; then
  docker_build || echo "Docker build failed"
else
  local_build || echo "Local build failed"
fi
