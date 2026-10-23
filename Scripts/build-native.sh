#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
cmake -S Vendor/llama.cpp -B NativeBuild/iphoneos/build -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk_path" -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_INSTALL_PREFIX="$PWD/NativeBuild/iphoneos" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DBUILD_SHARED_LIBS=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF -DLLAMA_BUILD_COMMON=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_ACCELERATE=ON \
  -DGGML_OPENMP=OFF -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=OFF -DLLAMA_CURL=OFF
cmake --build NativeBuild/iphoneos/build --config Release --parallel 3
mkdir -p NativeBuild/iphoneos/lib
find NativeBuild/iphoneos/build -name '*.a' -type f -exec cp '{}' NativeBuild/iphoneos/lib/ \;
for library in llama ggml ggml-base ggml-cpu ggml-metal ggml-blas; do
  test -s "NativeBuild/iphoneos/lib/lib${library}.a"
done
