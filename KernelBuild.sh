#!/bin/bash
info() {
  tput setaf 3  
  echo "[INFO] $1"
  tput sgr0
}

# Setting
# Android Version
export ANDROID_VER="14"
# Kernel Version
export KERNEL_VER="6.1"
# Security Patch
export SEC_PATCH="2025-05"
# KERNEL_SUFFIX="" meaning remove dirty suffix
# or using custom suffix to replace it
export KERNEL_SUFFIX="ab13050921"
# System Time
export BUILD_TIME="2025-05-31 00:12:14 UTC"

info "Android Version：Android $ANDROID_VER"
info "Kernel Version：$KERNEL_VER"
info "Security Patch：$SEC_PATCH"
if [[ "$KERNEL_SUFFIX" == "" ]]; then
  info "Kernel release will remove dirty suffix"
else
  info "Using $KERNEL_SUFFIX to replace dirty suffix"
fi
info "Build Time：$BUILD_TIME"
echo

info "Modify the script before starting"
echo

info "After startup, press Ctrl+C to exit"
read -n 1 -s -p "Press any key to continue"
echo

# Setup for KPM
while true; do
  read -p "KPM Feature (y=Enable, n=Disable): " kpm
  if [[ "$kpm" == "n" || "$kpm" == "y" ]]; then
    export KERNEL_KPM="$kpm"
    break
  else
    info "[Error] Please select：y(yes) or n(no)"
  fi
done

#Download Toolkit
info "Install Toolkit"
sudo apt update && sudo apt upgrade -y
sudo apt-get install -y build-essential bc bison python3 curl git zip wget

#Git for GKI
git config --global user.name "user"
git config --global user.email "user@gmail.com"

#Download Repo
info "Install repo"
curl https://storage.googleapis.com/git-repo-downloads/repo > $HOME/PixelGKI/repo
chmod a+x $HOME/PixelGKI/repo
sudo mv $HOME/PixelGKI/repo /usr/local/bin/repo

#Sync Generic Kernel Image Source Code
info "Sync GKI source code"
mkdir kernelbuild && cd kernelbuild
repo init -u https://android.googlesource.com/kernel/manifest -b common-android$ANDROID_VER-$KERNEL_VER-$SEC_PATCH --depth=1
repo sync

#Download SukiSU-Ultra susfs dev
info "Setup SukiSU-Ultra susfs dev"
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-dev

#Setup SUSFS & Patch
info "Setup SUSFS & Patch"
cd $HOME/PixelGKI/kernelbuild
git clone https://gitlab.com/simonpunk/susfs4ksu.git -b gki-android$ANDROID_VER-$KERNEL_VER
git clone https://github.com/SukiSU-Ultra/SukiSU_patch.git
cp susfs4ksu/kernel_patches/50_add_susfs_in_gki-android$ANDROID_VER-$KERNEL_VER.patch ./common/
cp susfs4ksu/kernel_patches/fs/* ./common/fs/
cp susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/
cd common
patch -p1 < 50_add_susfs_in_gki-android$ANDROID_VER-$KERNEL_VER.patch || true
cp ../SukiSU_patch/hooks/syscall_hooks.patch ./
patch -p1 -F 3 < syscall_hooks.patch

#Add these configuration to kernel
info "Added susfs configuration to kernel"
cd $HOME/PixelGKI/kernelbuild

CONFIGS=(
  "CONFIG_KSU=y"
  "CONFIG_KSU_SUSFS_SUS_SU=n"
  "CONFIG_KSU_MANUAL_HOOK=y"
  "CONFIG_KSU_SUSFS=y"
  "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y"
  "CONFIG_KSU_SUSFS_SUS_PATH=y"
  "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
  "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y"
  "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y"
  "CONFIG_KSU_SUSFS_SUS_KSTAT=y"
  "CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n"
  "CONFIG_KSU_SUSFS_TRY_UMOUNT=y"
  "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y"
  "CONFIG_KSU_SUSFS_SPOOF_UNAME=y"
  "CONFIG_KSU_SUSFS_ENABLE_LOG=y"
  "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"
  "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y"
  "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y"
)

for CONFIG in "${CONFIGS[@]}"; do
  echo "$CONFIG" >> common/arch/arm64/configs/gki_defconfig
done

# KPM feature
if [ "$KERNEL_KPM" = "y" ]; then
  info "Enable KPM feature"
  cd $HOME/PixelGKI/kernelbuild  
  # Add KPM configuration
  echo "CONFIG_KPM=y" >> common/arch/arm64/configs/gki_defconfig
  cd common
  info "Added KPM configuration to kernel"
else
  info "Disable KPM feature"
fi

# Modify kernel Suffix
cd $HOME/PixelGKI/kernelbuild || exit
sudo sed -i 's/check_defconfig//' ./common/build.config.gki
if [[ "$KERNEL_SUFFIX" == "" ]]; then
  info "Remove dirty suffix"
  sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' common/scripts/setlocalversion
else
  info "Custom suffix to replace dirty suffix"
  sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' common/scripts/setlocalversion
  sed -i '$s|echo "\$res"|echo "\$res-ab13050921"|' ./common/scripts/setlocalversion
  sudo sed -i "s/ab13050921/$KERNEL_SUFFIX/g" ./common/scripts/setlocalversion
fi

#Unix timestamp converter
info "Set kernel build time"
SOURCE_DATE_EPOCH=$(date -d "$BUILD_TIME" +%s)
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}
info "$BUILD_TIME" 

# Build kernel
cd $HOME/PixelGKI/kernelbuild || exit
info "Building kernel"
sed -i '/^[[:space:]]*"protected_exports_list"[[:space:]]*:[[:space:]]*"android\/abi_gki_protected_exports_aarch64",$/d' ./common/BUILD.bazel
rm -rf ./common/android/abi_gki_protected_exports_*
tools/bazel run --config=fast --config=stamp --lto=thin //common:kernel_aarch64_dist -- --destdir=dist

# KPM patching
if [ "$KERNEL_KPM" = "y" ]; then
  info "Patching Image file..."
  cd dist
  curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/patch_linux" -o patch
  chmod 777 patch
  ./patch
  rm -rf Image
  mv oImage kernel
  info "Added KPM feature"
else
  info "KPM not Patched"
  mv dist/Image dist/kernel
fi

info "Compilation successful"
info "The kernel is in PixelGKI/kernelbuild/dist"
info "Use magiskboot repack to boot.img"
