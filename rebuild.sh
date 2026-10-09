#!/usr/bin/env bash
set -euo pipefail
kit=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
release=6.18.54.1-microsoft-standard-WSL2-CustomShahmKernal
[[ $EUID -eq 0 && $(uname -m) == x86_64 ]] || { echo 'Run with sudo inside x86-64 Kali.' >&2; exit 1; }
output="$kit/rebuilt"
[[ ! -e "$output" ]] || { echo 'rebuilt already exists; move it elsewhere before rebuilding.' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential flex bison libssl-dev libelf-dev bc dwarves python3 cpio kmod qemu-utils e2fsprogs
work=$(mktemp -d /var/tmp/shahm-kernel-build.XXXXXX)
echo "Building in $work. The work directory is retained for inspection."
mkdir -p "$work/source" "$work/modules" "$work/headers" "$work/perf" "$work/xtrx"
tar -xzf "$kit/assets/kernel-source.tar.gz" -C "$work/source"
install -m 644 "$kit/config/kernel.config" "$work/source/.config"
export KBUILD_BUILD_USER=kali KBUILD_BUILD_HOST=Shahm
make -C "$work/source" -j"${JOBS:-$(nproc)}"
[[ $(make -s -C "$work/source" kernelrelease) == "$release" ]]
cmp "$work/source/.config" "$kit/config/kernel.config"
make -C "$work/source" INSTALL_MOD_PATH="$work/modules" modules_install
make -C "$work/source" INSTALL_HDR_PATH="$work/headers" headers_install
tar -xzf "$kit/assets/driver-sources.tar.gz" -C "$work/xtrx"
driver="$work/xtrx/usr/src/xtrx-0.0.1+git20190320.5ae3a3e"
make -C "$work/source" M="$driver" modules
install -Dm644 "$driver/xtrx.ko" "$work/modules/lib/modules/$release/updates/dkms/xtrx.ko"
depmod -b "$work/modules" "$release"
mkdir "$output"
install -m 644 "$work/source/arch/x86/boot/bzImage" "$output/kernel"
bash "$work/source/Microsoft/scripts/gen_artifacts_vhdx.sh" \
    "$work/modules" "$work/headers" "$work/perf" "$release" "$work/modules.vhdx"
gzip -1 -c "$work/modules.vhdx" > "$output/modules.vhdx.gz"
tar -czf "$output/kernel-build-metadata.tar.gz" -C "$work/source" \
    Module.symvers include/config include/generated arch/x86/include/generated scripts/mod/modpost
(cd "$output" && sha256sum kernel modules.vhdx.gz kernel-build-metadata.tar.gz > SHA256SUMS)
echo 'Rebuild complete. On Windows run: .\Install.ps1 -Rebuilt'
