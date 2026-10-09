#!/usr/bin/env bash
set -euo pipefail
kit=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
release=6.18.54.1-microsoft-standard-WSL2-CustomShahmKernal
source_dir=/usr/src/shahm-kernel-$release
mode=${2:-original}
[[ $mode == original || $mode == rebuilt ]] || { echo 'Invalid artifact mode.' >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ $(uname -m) == x86_64 && $(uname -r) == *WSL2* ]] || {
    echo 'This kit is for x86-64 Kali under WSL2, not a native/GRUB installation.' >&2; exit 1;
}
. /etc/os-release
[[ $ID == kali ]] || { echo 'The selected distribution must be Kali Linux.' >&2; exit 1; }

case ${1:-} in
prepare)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends build-essential flex bison libssl-dev libelf-dev bc dwarves python3 cpio kmod dkms
    mkdir -p "$source_dir"
    tar -xzf "$kit/assets/kernel-source.tar.gz" -C "$source_dir"
    install -m 644 "$kit/config/kernel.config" "$source_dir/.config"
    metadata="$kit/assets/kernel-build-metadata.tar.gz"
    [[ $mode != rebuilt ]] || metadata="$kit/rebuilt/kernel-build-metadata.tar.gz"
    tar -xzf "$metadata" -C "$source_dir"
    make -C "$source_dir" -j"$(nproc)" modules_prepare
    cmp "$source_dir/.config" "$kit/config/kernel.config"
    tar -xzf "$kit/assets/driver-sources.tar.gz" -C /
    tar -xzf "$kit/assets/firmware.tar.gz" -C /
    tar -xzf "$kit/assets/driver-settings.tar.gz" -C /
    # Keep unrelated WSL settings; systemd is the captured boot setting.
    python3 - <<'PY'
import configparser
from pathlib import Path
p = Path('/etc/wsl.conf')
c = configparser.ConfigParser(interpolation=None)
c.optionxform = str
if p.exists():
    c.read(p)
if not c.has_section('boot'):
    c.add_section('boot')
c.set('boot', 'systemd', 'true')
with p.open('w') as f:
    c.write(f, space_around_delimiters=False)
PY
    ;;
activate)
    [[ $(uname -r) == "$release" ]] || { echo "WSL did not boot $release." >&2; exit 1; }
    if [[ $mode == original ]]; then
        tar -xzf "$kit/assets/extra-modules.tar.gz" -C /
    fi
    ln -sfn "$source_dir" "/lib/modules/$release/build"
    for spec in \
        'realtek-rtl8814au:5.8.5.1~git20250903.8d82854' \
        'realtek-rtl88xxau:5.6.4.2~git20250330.c3fb89a' \
        'xtrx:0.0.1+git20190320.5ae3a3e'; do
        name=${spec%%:*}; version=${spec#*:}
        if [[ -z $(dkms status -m "$name" -v "$version") ]]; then
            dkms add -m "$name" -v "$version"
        fi
    done
    # Only XTRX was installed on this kernel. Realtek's old DKMS sources
    # explicitly exclude kernel >= 6.15; retain them without overriding that limit.
    if [[ $mode == original ]]; then
        if ! dkms status -m xtrx -v '0.0.1+git20190320.5ae3a3e' -k "$release" | grep -q ': installed'; then
            dkms ldtarball "$kit/assets/xtrx-dkms.tar.gz" --force
            dkms install -m xtrx -v '0.0.1+git20190320.5ae3a3e' -k "$release" --kernelsourcedir "$source_dir"
        fi
    else
        dkms build -m xtrx -v '0.0.1+git20190320.5ae3a3e' -k "$release" --kernelsourcedir "$source_dir" --force
        dkms install -m xtrx -v '0.0.1+git20190320.5ae3a3e' -k "$release" --kernelsourcedir "$source_dir" --force
    fi
    depmod -a "$release"
    echo "Activated $release with captured modules, firmware and driver settings."
    ;;
*) echo 'Usage: install-linux.sh prepare|activate' >&2; exit 2 ;;
esac
