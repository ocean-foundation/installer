#!/usr/bin/env bash
set -euo pipefail

target=$1
work=$2
notices=$3
arch=${target%-*}
os=${target#*-}

# ocean target installs the host tools and target sysroots under the bundle tag.
bundle_paths=("$OCEAN_TARGET_DIR"/*/"$target")
test "${#bundle_paths[@]}" -eq 1
bundle=${bundle_paths[0]}
test -f "$bundle/installed"
tools="$(dirname "$bundle")/host-aarch64-macos/bin"

mkdir -p "$work" "$notices"
cd "$work"
prefix="$work/prefix"
downloads="$(dirname "$work")/downloads"
mkdir -p "$downloads"
export PKG_CONFIG_PATH=
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"

fetch() {
  local url=$1 digest=$2 archive="$downloads/${1##*/}"
  if [[ ! -f "$archive" ]]; then
    curl --fail --silent --show-error --location --retry 3 "$url" -o "$archive.part"
    mv "$archive.part" "$archive"
  fi
  printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c -
  tar -xf "$archive"
}

# Match the compiler's managed Clang invocation when building C dependencies.
export TARGET_CLANG="$tools/clang"
export TARGET_LINKER="$tools/ld.lld"
export TARGET_BUNDLE="$bundle"
export TARGET_OS="$os"
if [[ "$os" == linux ]]; then
  export TARGET_TRIPLE="$arch-unknown-linux-gnu"
else
  export TARGET_TRIPLE="$arch-w64-windows-gnu"
  resources=("$bundle"/lib/clang/*)
  test "${#resources[@]}" -eq 1
  export TARGET_RESOURCE_DIR="${resources[0]}"
fi
cat > "$work/target-cc" <<'CC'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$TARGET_OS" == linux ]]; then
  flags=(--sysroot="$TARGET_BUNDLE/sysroot"
    --gcc-toolchain="$TARGET_BUNDLE/sysroot/usr"
    "-Wl,-rpath-link,$TARGET_BUNDLE/lib")
else
  flags=(--sysroot="$TARGET_BUNDLE" --rtlib=compiler-rt
    -resource-dir="$TARGET_RESOURCE_DIR")
fi
exec "$TARGET_CLANG" --no-default-config -Qunused-arguments --target="$TARGET_TRIPLE" \
  -fuse-ld=lld --ld-path="$TARGET_LINKER" -L"$TARGET_BUNDLE/lib" "${flags[@]}" "$@"
CC
chmod +x "$work/target-cc"
export CC="$work/target-cc" AR="$tools/llvm-ar" RANLIB="$tools/llvm-ranlib"

build_cmake() {
  local source=$1
  shift
  cmake -S "$source" -B "$source-build" -G Ninja \
    -DCMAKE_SYSTEM_NAME="$cmake_system" -DCMAKE_SYSTEM_PROCESSOR="$arch" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_AR="$AR" -DCMAKE_RANLIB="$RANLIB" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$prefix" "$@"
  cmake --build "$source-build" --parallel 3
  cmake --install "$source-build"
}

fetch https://github.com/libffi/libffi/releases/download/v3.8.0/libffi-3.8.0.tar.gz \
  7da3e2d9a171eb0a038f592ecad3ff2bb2550f3496d87b3b29ad0cf4430c0db4
cp libffi-3.8.0/LICENSE "$notices/libffi.txt"

if [[ "$os" == linux ]]; then
  cmake_system=Linux
  case "$arch" in
    x86_64) openssl_target=linux-x86_64 ;;
    aarch64) openssl_target=linux-aarch64 ;;
    riscv64) openssl_target=linux64-riscv64 ;;
  esac
  fetch https://github.com/openssl/openssl/releases/download/openssl-3.5.8/openssl-3.5.8.tar.gz \
    a8f84a39918ec6415ce765d9b429d313ba97b8143169c172e734b9514464f5b2
  (
    cd openssl-3.5.8
    ./Configure "$openssl_target" no-shared no-module no-dso no-tests \
      --prefix="$prefix" --libdir=lib --openssldir=/etc/ssl
    make -j3 build_libs
    make install_dev
  )
  cp openssl-3.5.8/LICENSE.txt "$notices/openssl.txt"

  fetch https://github.com/c-ares/c-ares/releases/download/v1.34.9/c-ares-1.34.9.tar.gz \
    9364b70a12eb59a06830fb488d9357f90100dff0d98b23ea3593a183d43e6f2f
  build_cmake c-ares-1.34.9 -DCARES_STATIC=ON -DCARES_SHARED=OFF -DCARES_BUILD_TOOLS=OFF
  cp c-ares-1.34.9/LICENSE.md "$notices/c-ares.txt"

  (
    cd libffi-3.8.0
    ./configure --build="$(./config.guess)" --host="$TARGET_TRIPLE" \
      --prefix="$prefix" --enable-static --disable-shared
    make -j3
    make install
  )
  # Ocean's managed linker searches here for -lffi and its headers.
  cp "$prefix/lib/libffi.a" "$bundle/lib/"
  cp "$prefix/include/ffi.h" "$prefix/include/ffitarget.h" "$bundle/include/"

  tls_dns=(-DCURL_USE_OPENSSL=ON -DOPENSSL_USE_STATIC_LIBS=ON -DOPENSSL_ROOT_DIR="$prefix"
    -DCURL_DISABLE_OPENSSL_AUTO_LOAD_CONFIG=ON -DCURL_CA_FALLBACK=ON
    -DCURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt -DCURL_CA_PATH=/etc/ssl/certs
    -DENABLE_ARES=ON -DCARES_LIBRARY="$prefix/lib/libcares.a"
    -DCARES_INCLUDE_DIR="$prefix/include" -DENABLE_THREADED_RESOLVER=OFF)
else
  cmake_system=Windows
  test -f "$bundle/lib/libffi.a"
  if [[ -f "$bundle/lib/libffi.dll.a" ]]; then
    mv "$bundle/lib/libffi.dll.a" "$work/"
  fi
  tls_dns=(-DCURL_USE_SCHANNEL=ON -DCURL_USE_OPENSSL=OFF
    -DENABLE_ARES=OFF -DENABLE_THREADED_RESOLVER=ON)
fi

fetch https://github.com/curl/curl/releases/download/curl-8_23_0/curl-8.23.0.tar.xz \
  8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5
build_cmake curl-8.23.0 \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF \
  -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_LDAPS=ON -DCURL_USE_GSSAPI=OFF \
  -DCURL_USE_LIBSSH=OFF -DCURL_USE_LIBSSH2=OFF -DCURL_USE_LIBPSL=OFF -DUSE_LIBIDN2=OFF \
  -DUSE_NGHTTP2=OFF -DUSE_NGHTTP3=OFF -DUSE_NGTCP2=OFF -DUSE_QUICHE=OFF \
  -DCURL_ZLIB=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF "${tls_dns[@]}"
cp curl-8.23.0/COPYING "$notices/curl.txt"
test -f "$prefix/lib/libcurl.a"
# Ocean searches the managed bundle before pkg-config's -L directories.
# Name the private curl archive explicitly so the bundle cannot shadow it.
curl_pc="$prefix/lib/pkgconfig/libcurl.pc"
awk '/^Libs:/ { for (i=2; i<=NF; i++) if ($i == "-lcurl") $i="-Wl,${libdir}/libcurl.a" }
  { print }' "$curl_pc" > "$curl_pc.tmp"
mv "$curl_pc.tmp" "$curl_pc"
pkg-config --static --libs libcurl
