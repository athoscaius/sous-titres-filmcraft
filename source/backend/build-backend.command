#!/bin/bash
set -euo pipefail
# Usage: build-backend.command /absolute/path/App.app/Contents/Resources
# BACKEND_CACHE may point to a persistent build/download cache; no global install.
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:?Specify app Resources directory}"
CACHE="${BACKEND_CACHE:-${TMPDIR:-/tmp}/artcraft-subtitles-build-cache}"
COMMIT=d1be6fde11ac6e0407606b4e42fe72d34add8037
mkdir -p "$CACHE/models" "$DEST/bin" "$DEST/models" "$DEST/licenses"
fetch() {
    local url="$1" file="$2" checksum="$3"
    if [ -f "$file" ] && [ "$(shasum -a 256 "$file" | cut -d ' ' -f1)" = "$checksum" ]; then return; fi
    /usr/bin/curl --fail --location --retry 3 --output "$file.partial" "$url"
    printf '%s  %s\n' "$checksum" "$file.partial" | /usr/bin/shasum -a 256 --check
    mv "$file.partial" "$file"
}
fetch "https://github.com/ggml-org/whisper.cpp/archive/$COMMIT.tar.gz" "$CACHE/whisper.tar.gz" 645445da884df6dbd52b30f82d7be7c01d1767c938714e477e786b88d529e9f4
fetch https://github.com/Kitware/CMake/releases/download/v3.31.8/cmake-3.31.8-macos-universal.tar.gz "$CACHE/cmake.tar.gz" d1449f969c54d5c00886d5b643340d493dfb3c81cb39ee29b35453395c11ebf7
fetch https://huggingface.co/ggerganov/whisper.cpp/resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-large-v3-q5_0.bin "$CACHE/models/ggml-large-v3-q5_0.bin" d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1
fetch https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v6.2.0.bin "$CACHE/models/ggml-silero-v6.2.0.bin" 2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987
if [ ! -d "$CACHE/whisper.cpp-$COMMIT" ]; then tar -xzf "$CACHE/whisper.tar.gz" -C "$CACHE"; fi
if [ ! -d "$CACHE/cmake-3.31.8-macos-universal" ]; then tar -xzf "$CACHE/cmake.tar.gz" -C "$CACHE"; fi
CMAKE="$CACHE/cmake-3.31.8-macos-universal/CMake.app/Contents/bin/cmake"
"$CMAKE" -S "$CACHE/whisper.cpp-$COMMIT" -B "$CACHE/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod -DGGML_CCACHE=OFF
"$CMAKE" --build "$CACHE/build" --target whisper-cli -j 6
/usr/bin/swiftc -parse-as-library -O -target arm64-apple-macos14 -module-cache-path "$CACHE/swift-cache" "$SOURCE_DIR/Transcribe.swift" -o "$DEST/bin/transcribe"
cp "$CACHE/build/bin/whisper-cli" "$DEST/bin/whisper-cli"
cp "$CACHE/models/ggml-large-v3-q5_0.bin" "$CACHE/models/ggml-silero-v6.2.0.bin" "$DEST/models/"
cp "$SOURCE_DIR/WHISPER-CPP-LICENSE.txt" "$SOURCE_DIR/WHISPER-LICENSE.txt" "$SOURCE_DIR/SILERO-LICENSE.txt" "$DEST/licenses/"
cp "$SOURCE_DIR/DEPENDENCIES.json" "$DEST/licenses/"
chmod 755 "$DEST/bin/transcribe" "$DEST/bin/whisper-cli"
# Signing is performed by the app packaging script after all bundle files exist.
