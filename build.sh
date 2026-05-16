#!/bin/bash
# ================================================================
# APTKernel Local Build Script
# ================================================================

set -e

# ─── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ─── Config ───────────────────────────────────────────────────
KERNEL_SOURCE="https://github.com/MiCode/Xiaomi_Kernel_OpenSource"
KERNEL_BRANCH="alioth-s-oss"
DEFCONFIG="apt_alioth_defconfig"
ARCH="arm64"
ROOT_MANAGER="${ROOT_MANAGER:-KernelSU}"   # KernelSU | ReSukiSU | SukiSU-Ultra | None
SUSFS="${SUSFS:-true}"
JOBS=$(nproc --all)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
KERNEL_DIR="$BUILD_DIR/kernel"
OUT_DIR="$KERNEL_DIR/out"
TOOLCHAIN_DIR="$BUILD_DIR/toolchains"

echo -e "${CYAN}${BOLD}"
echo "================================"
echo "   APTKernel Build Script"
echo "   alioth — Snapdragon 870"
echo "================================"
echo -e "${NC}"

# ─── Install deps ─────────────────────────────────────────────
install_deps() {
    echo -e "${YELLOW}[*] Installing dependencies...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        git curl wget zip bc bison flex \
        libssl-dev libelf-dev python3 \
        make gcc gcc-aarch64-linux-gnu \
        gcc-arm-linux-gnueabi \
        cpio ccache lz4 zstd pigz \
        pkg-config dwarves pahole
}

# ─── Toolchain ────────────────────────────────────────────────
setup_toolchain() {
    echo -e "${YELLOW}[*] Setting up ZyC Clang 20...${NC}"
    mkdir -p "$TOOLCHAIN_DIR/zyc-clang"

    if [ ! -f "$TOOLCHAIN_DIR/zyc-clang/bin/clang" ]; then
        ZYC_URL=$(curl -s "https://raw.githubusercontent.com/ZyCromerZ/Clang/main/Clang-20-link.txt" | head -1)
        wget -q --show-progress "$ZYC_URL" -O /tmp/zyc-clang.tar.gz
        tar -xzf /tmp/zyc-clang.tar.gz -C "$TOOLCHAIN_DIR/zyc-clang"
        rm /tmp/zyc-clang.tar.gz
    else
        echo -e "${GREEN}[✓] ZyC Clang already present${NC}"
    fi

    export PATH="$TOOLCHAIN_DIR/zyc-clang/bin:$PATH"
    echo -e "${GREEN}[✓] Clang: $(clang --version | head -1)${NC}"
}

# ─── Kernel Source ────────────────────────────────────────────
clone_kernel() {
    if [ ! -d "$KERNEL_DIR/.git" ]; then
        echo -e "${YELLOW}[*] Cloning kernel source ($KERNEL_BRANCH)...${NC}"
        git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_SOURCE" "$KERNEL_DIR"
    else
        echo -e "${GREEN}[✓] Kernel source already cloned${NC}"
    fi
}

# ─── Root Manager ─────────────────────────────────────────────
integrate_root() {
    cd "$KERNEL_DIR"
    case "$ROOT_MANAGER" in
        KernelSU)
            echo -e "${YELLOW}[*] Integrating KernelSU...${NC}"
            KSU_TAG=$(curl -s "https://api.github.com/repos/tiann/KernelSU/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
            curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s "$KSU_TAG"
            ;;
        ReSukiSU)
            echo -e "${YELLOW}[*] Integrating ReSukiSU...${NC}"
            curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -
            ;;
        SukiSU-Ultra)
            echo -e "${YELLOW}[*] Integrating SukiSU-Ultra...${NC}"
            curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -
            ;;
        None)
            echo -e "${YELLOW}[*] No root manager${NC}"
            ;;
    esac
}

# ─── SuSFS ────────────────────────────────────────────────────
integrate_susfs() {
    if [ "$SUSFS" != "true" ]; then return; fi
    echo -e "${YELLOW}[*] Integrating SuSFS...${NC}"
    cd "$KERNEL_DIR"
    git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs4ksu
    for patch in /tmp/susfs4ksu/kernel_patches/4.19/*.patch; do
        [ -f "$patch" ] && git apply "$patch" 2>/dev/null || true
    done
}

# ─── APT Patches ──────────────────────────────────────────────
apply_patches() {
    echo -e "${YELLOW}[*] Applying APT patches...${NC}"
    cd "$KERNEL_DIR"
    for patch in "$SCRIPT_DIR/../patches"/*.patch; do
        [ -f "$patch" ] || continue
        echo "  Applying: $(basename "$patch")"
        git apply "$patch" 2>/dev/null || \
        patch -p1 < "$patch" 2>/dev/null || \
        echo -e "  ${RED}[SKIP]${NC} $(basename "$patch")"
    done
}

# ─── Build ────────────────────────────────────────────────────
build_kernel() {
    echo -e "${YELLOW}[*] Building kernel...${NC}"
    cd "$KERNEL_DIR"

    # Copy defconfig
    cp "$SCRIPT_DIR/../arch/arm64/configs/$DEFCONFIG" \
       arch/arm64/configs/

    export KBUILD_BUILD_USER="APT"
    export KBUILD_BUILD_HOST="APTKernel"
    export CCACHE_DIR="$BUILD_DIR/.ccache"

    MAKE_ARGS=(
        O=out
        ARCH=arm64
        CC="ccache clang"
        CLANG_TRIPLE=aarch64-linux-gnu-
        CROSS_COMPILE=aarch64-linux-gnu-
        CROSS_COMPILE_ARM32=arm-linux-gnueabi-
        LLVM=1
        LLVM_IAS=1
        -j"$JOBS"
    )

    make "${MAKE_ARGS[@]}" "$DEFCONFIG"
    make "${MAKE_ARGS[@]}" 2>&1 | tee "$BUILD_DIR/build.log"

    if [ -f "out/arch/arm64/boot/Image" ]; then
        echo -e "${GREEN}${BOLD}[✓] Kernel built successfully!${NC}"
    else
        echo -e "${RED}[✗] Build FAILED — check $BUILD_DIR/build.log${NC}"
        exit 1
    fi
}

# ─── Package ──────────────────────────────────────────────────
package_kernel() {
    echo -e "${YELLOW}[*] Packaging AnyKernel3...${NC}"
    BUILD_DATE=$(date +%Y%m%d-%H%M)
    AK_DIR="$BUILD_DIR/anykernel_${BUILD_DATE}"

    cp -r "$SCRIPT_DIR/../AnyKernel3" "$AK_DIR"
    cp "$KERNEL_DIR/out/arch/arm64/boot/Image" "$AK_DIR/"
    cp "$KERNEL_DIR/out/arch/arm64/boot/dts/qcom/"*alioth*.dtbo "$AK_DIR/" 2>/dev/null || true

    cd "$AK_DIR"
    ZIP_NAME="APTKernel-${BUILD_DATE}-alioth-${ROOT_MANAGER}.zip"
    zip -r9 "$BUILD_DIR/$ZIP_NAME" . -x "*.git*"

    echo -e "${GREEN}${BOLD}"
    echo "================================"
    echo "   Build Complete!"
    echo "   $ZIP_NAME"
    echo "================================"
    echo -e "${NC}"
}

# ─── Main ─────────────────────────────────────────────────────
mkdir -p "$BUILD_DIR"

install_deps
setup_toolchain
clone_kernel
integrate_root
integrate_susfs
apply_patches
build_kernel
package_kernel
