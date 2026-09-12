#!/bin/bash
#
# Reproducible rebuild of the /usr/local ffmpeg used by Video_Convert_2.
#
# Adds over the previous build:
#   libsvtav1   AV1 encoding           (vc1.sh --av1)
#   libvmaf     quality metric         (vc1.sh --verify)
#   cuda-llvm   scale_cuda et al       (vc1.sh assumed these existed; they did not)
#   libzimg     colorspace-aware scaling (zscale)
#   libsoxr     high quality audio resampling
#   libplacebo  HDR -> SDR tonemapping
#   x265        rebuilt MULTILIB (8/10/12-bit); the old local build was 8-bit only
#
# Two things this deliberately does NOT do, both verified on this host:
#
#   1. --enable-cuda-nvcc is not used. CUDA 12.9 cannot compile here:
#        vs gcc 15.3.1  -> "unsupported GNU version! gcc versions later than 14
#                          are not supported!"
#        vs gcc-14      -> "mathcalls.h: exception specification is incompatible
#                          with that of previous function 'cospi'"
#      glibc 2.42 declares the C23 sinpi/cospi/tanpi that CUDA also declares, and
#      cuda-nvcc-12-9 is the newest available. --enable-cuda-llvm builds the same
#      filters with clang's NVPTX backend and needs no CUDA toolkit; configure
#      accepts either (scale_cuda_filter_deps_any="cuda_nvcc cuda_llvm").
#      NOTE: --enable-libnpp is NOT used either, and no CUDA toolkit is needed at
#      all. Upstream ffmpeg has REMOVED libnpp ("WARNING: libnpp has been removed
#      and enabling it does nothing"), so scale_npp no longer exists; scale_cuda
#      via cuda-llvm covers it. This build therefore does not link anything out
#      of /usr/local/cuda-*, so installing or removing a CUDA toolkit cannot
#      break it.
#
#   2. The system (RPMFusion) x265 is not used. It shares soname libx265.so.215
#      with the local build, so mixing them risks loading the wrong library at
#      runtime. x265 is rebuilt multilib in place instead.
#
# Local x264 and fdk-aac builds in /usr/local are kept as-is (full fdk-aac is
# preferable to Fedora's stripped fdk-aac-free). dav1d comes from the system.

set -euo pipefail

BUILD_ROOT="${BUILD_ROOT:-$HOME/source/ffmpeg_build}"
PREFIX="${PREFIX:-/usr/local}"
JOBS=$(nproc)

# x265 release to build. Must be a real tag: see the x265 section below for why
# a tagless or shallow checkout silently produces an 8-bit-only install.
X265_TAG="${X265_TAG:-4.2}"

say () { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die () { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ -d $BUILD_ROOT/ffmpeg ]] || die "no ffmpeg source tree at $BUILD_ROOT/ffmpeg"
[[ -d $BUILD_ROOT/x265   ]] || die "no x265 source tree at $BUILD_ROOT/x265"

# ---------------------------------------------------------------- dependencies
say "Installing build dependencies"
sudo dnf install -y \
  clang \
  libdav1d-devel svt-av1-devel libaom-devel \
  libvmaf-devel zimg-devel soxr-devel \
  libplacebo-devel vulkan-loader-devel \
  numactl-devel cmake nasm yasm \
  libass-devel libvpx-devel opus-devel lame-devel xvidcore-devel \
  openssl-devel freetype-devel fontconfig-devel harfbuzz-devel fribidi-devel

# clang must be able to target the GPU, or --enable-cuda-llvm silently disables
clang -print-targets | grep -q nvptx64 \
  || die "this clang has no nvptx64 target; --enable-cuda-llvm will not work"

# ----------------------------------------------------------- x265 (multilib)
say "Rebuilding x265 with 8/10/12-bit support"
cd "$BUILD_ROOT/x265"

# x265's CMakeLists guards the shared-library install with
#   if(X265_LATEST_TAG OR NOT GIT_FOUND)   # shared library is not installed if a tag is not found
# so a checkout that `git describe` cannot resolve installs ONLY libx265.a, the
# headers and the CLI -- silently leaving the previous .so in place. That is how
# a perfectly good multilib build still left ffmpeg linked against an 8-bit
# libx265, and why x265 printed "HEVC encoder version unknown" on every run.
#
# Fetching tags is not sufficient on its own: this tree was a SHALLOW clone, so
# the tag commits were not connected ancestors and `git describe` still failed
# with "No tags can describe ...". Unshallow first, then build from a real
# release tag so X265_LATEST_TAG resolves.
[[ $(git rev-parse --is-shallow-repository) == 'false' ]] \
  || git fetch --unshallow || die "could not unshallow the x265 checkout"
git fetch --tags --force origin || die "could not fetch x265 tags"
git checkout "$X265_TAG" || die "no such x265 tag: $X265_TAG"
git describe --abbrev=0 --tags >/dev/null 2>&1 \
  || die "git describe cannot resolve a tag at $X265_TAG; the shared library would not install"

cd "$BUILD_ROOT/x265/build/linux"
# The 2025 build left artifacts directly in build/linux/; clear them too or a
# stale CMakeCache here can shadow the new out-of-tree builds.
rm -rf 8bit 10bit 12bit CMakeCache.txt CMakeFiles libx265.a libx265.so libx265.so.*
mkdir -p 8bit 10bit 12bit

( cd 12bit && cmake ../../../source \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DHIGH_BIT_DEPTH=ON -DMAIN12=ON \
    -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF >/dev/null
  make -j"$JOBS" )

( cd 10bit && cmake ../../../source \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DHIGH_BIT_DEPTH=ON \
    -DEXPORT_C_API=OFF -DENABLE_SHARED=OFF -DENABLE_CLI=OFF >/dev/null
  make -j"$JOBS" )

cd 8bit
ln -sf ../10bit/libx265.a libx265_main10.a
ln -sf ../12bit/libx265.a libx265_main12.a
cmake ../../../source \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DEXTRA_LIB="x265_main10.a;x265_main12.a" -DEXTRA_LINK_FLAGS=-L. \
  -DLINKED_10BIT=ON -DLINKED_12BIT=ON \
  -DENABLE_SHARED=ON -DENABLE_CLI=ON >/dev/null
make -j"$JOBS"
sudo make install
sudo ldconfig

# Fail loudly rather than letting ffmpeg quietly link the old 8-bit library.
grep -q 'libx265\.so' install_manifest.txt \
  || die "x265 install did not include the shared library -- check that tags were fetched"

# The 8-bit-only build reported "8bit"; multilib reports "8bit+10bit+12bit".
x265ver=$("$PREFIX/bin/x265" --version 2>&1 | grep -o '\[64 bit\].*' || true)
say "x265 now reports: $x265ver"
[[ $x265ver == *10bit* ]] || die "installed x265 is still not multilib: $x265ver"

# --------------------------------------------------------------------- ffmpeg
say "Updating ffmpeg source"
cd "$BUILD_ROOT/ffmpeg"
git fetch --all --tags
git checkout master
git pull --ff-only
say "ffmpeg now at: $(git log --oneline -1)"

say "Configuring ffmpeg"
make distclean >/dev/null 2>&1 || true

PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
./configure \
  --prefix="$PREFIX" \
  --enable-shared \
  --enable-gpl --enable-nonfree --enable-version3 \
  --enable-libx264 --enable-libx265 --enable-libsvtav1 --enable-libaom \
  --enable-libvpx --enable-libxvid --enable-libdav1d \
  --enable-libfdk-aac --enable-libopus --enable-libmp3lame --enable-libsoxr \
  --enable-libass --enable-libfreetype --enable-libfontconfig \
  --enable-libharfbuzz --enable-libfribidi \
  --enable-libzimg --enable-libvmaf \
  --enable-nvenc --enable-nvdec --enable-cuda-llvm \
  --enable-libplacebo --enable-vulkan \
  --enable-openssl

say "Building with $JOBS jobs"
make -j"$JOBS"
sudo make install
sudo ldconfig

# --------------------------------------------------------------- verification
say "Verifying"
fail=0
# NOTE: never pipe a long listing straight into `grep -q` here. grep exits on the
# first match, ffmpeg takes SIGPIPE, and under `set -o pipefail` the whole check
# reports failure -- which made a perfectly good build look like 8 failures.
# Helpers below capture first, then match.
ff_filters=$("$PREFIX/bin/ffmpeg" -hide_banner -filters 2>/dev/null)
ff_encoders=$("$PREFIX/bin/ffmpeg" -hide_banner -encoders 2>/dev/null)
has_filter ()  { grep -qw -- "$1" <<< "$ff_filters"; }
has_encoder () { grep -qw -- "$1" <<< "$ff_encoders"; }

check () {
  if eval "$2" >/dev/null 2>&1; then
    printf '  \033[1;32mok\033[0m   %s\n' "$1"
  else
    printf '  \033[1;31mFAIL\033[0m %s\n' "$1"; fail=1
  fi
}

check "scale_cuda present"      "has_filter scale_cuda"
check "libvmaf filter present"  "has_filter libvmaf"
check "zscale filter"           "has_filter zscale"
check "libplacebo filter"       "has_filter libplacebo"
check "libsvtav1 encoder"       "has_encoder libsvtav1"
check "hevc_nvenc encoder"      "has_encoder hevc_nvenc"
# Asserted by a real encode, not by the pix_fmt listing: the listing is built at
# runtime from whatever libx265.so is actually loaded, so this is what proves the
# multilib library got installed rather than the old 8-bit one.
check "x265 10-bit encodes"     "$PREFIX/bin/ffmpeg -hide_banner -f lavfi -i testsrc2=s=320x180:r=24 -t 1 -c:v libx265 -pix_fmt yuv420p10le -f null -"
check "x265 12-bit encodes"     "$PREFIX/bin/ffmpeg -hide_banner -f lavfi -i testsrc2=s=320x180:r=24 -t 1 -c:v libx265 -pix_fmt yuv420p12le -f null -"
check "SVT-AV1 encodes"         "$PREFIX/bin/ffmpeg -hide_banner -f lavfi -i testsrc2=s=640x360:r=24 -t 1 -c:v libsvtav1 -f null -"
check "hevc_nvenc encodes"      "$PREFIX/bin/ffmpeg -hide_banner -f lavfi -i testsrc2=s=640x360:r=24 -t 1 -c:v hevc_nvenc -f null -"
check "scale_cuda runs"         "$PREFIX/bin/ffmpeg -hide_banner -f lavfi -i testsrc2=s=640x360:r=24 -t 1 -vf hwupload_cuda,scale_cuda=w=320:h=180 -c:v hevc_nvenc -f null -"

if (( fail )); then
  die "one or more checks failed"
fi

say "Done. ffmpeg $("$PREFIX/bin/ffmpeg" -hide_banner -version | head -1)"
