#!/usr/bin/env bash

# Create a per-developer Ubuntu cloud VM and start it with QEMU acceleration.
set -Eeuo pipefail

usage() {
    cat <<'USAGE'
Usage:
  VM_DIR=/path/to/vm VM_USERNAME=yourname SSH_PUBLIC_KEY=~/.ssh/id_rsa.pub \
    ./create-vm.sh

On Linux, the default VM directory is /goinfre/$USER/vm and QEMU uses KVM.
On macOS, the default is ~/vm and QEMU uses Hypervisor.framework (HVF).
Install QEMU first (for example, `brew install qemu` on macOS). The script
downloads the pinned Ubuntu 24.04 LTS cloud image matching the host
architecture, makes a private writable copy, and configures its first boot
with your SSH public key.

Optional environment settings:
  VM_DIR             VM working directory (default: /goinfre/$USER/vm on Linux; ~/vm on macOS)
  VM_USERNAME        Guest account (default: current host username)
  VM_HOSTNAME        Guest hostname (default: dev-<VM_USERNAME>)
  SSH_PUBLIC_KEY     Public key file (default: ~/.ssh/id_rsa.pub)
  DISK_SIZE_GB       Virtual disk maximum in GiB (default: 50)
  VM_MEMORY          Guest RAM (default: 6G)
  VM_CPUS            Guest vCPUs (default: 4)
  SSH_PORT           Host port forwarded to guest port 22 (default: 2222)
  VM_DEBUG           Show guest VGA window and serial console in foreground (default: 0; set to 1 to debug)
  DOCKER_ENGINE_VERSION   Docker Engine/CLI apt version (default: 5:29.9.0-1~ubuntu.24.04~noble)
  DOCKER_COMPOSE_VERSION  Docker Compose plugin apt version (default: 5.6.0-1~ubuntu.24.04~noble)
  DOCKER_BUILDX_VERSION   Docker Buildx plugin apt version (default: 0.38.0-1~ubuntu.24.04~noble)
  CONTAINERD_VERSION      containerd.io apt version (default: 2.4.1-2~ubuntu.24.04~noble)
  AMD64_UEFI_CODE    AMD64 OVMF code firmware file, if not auto-detected
  AMD64_UEFI_VARS    AMD64 OVMF writable variables template, if not auto-detected
  ARM_UEFI_CODE      ARM64 UEFI code firmware file, if not auto-detected
  ARM_UEFI_VARS      ARM64 UEFI writable variables template, if not auto-detected
USAGE
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
(( $# == 0 )) || { usage >&2; exit 2; }

host_os=$(uname -s)
case "$host_os" in
    Linux)
        acceleration=kvm
        ;;
    Darwin)
        acceleration=hvf
        ;;
    *) fail "unsupported host operating system: $host_os (supported: Linux, macOS)." ;;
esac

host_arch=$(uname -m)
case "$host_arch" in
    x86_64)
        image_arch=amd64
        qemu_bin=qemu-system-x86_64
        ;;
    aarch64|arm64)
        image_arch=arm64
        qemu_bin=qemu-system-aarch64
        ;;
    *) fail "unsupported host architecture: $host_arch (supported: x86_64, aarch64)." ;;
esac

# An ARM64 Ubuntu guest on Apple silicon can use HVF for native CPU execution.
# Running the amd64 image there would require slow, fully emulated CPU execution.
if [[ "$host_os" == Darwin && "$image_arch" != arm64 ]]; then
    fail "macOS support is for Apple-silicon hosts (arm64) and starts a native ARM64 Ubuntu guest."
fi

for command_name in "$qemu_bin" qemu-img python3; do
    command -v "$command_name" >/dev/null 2>&1 || fail \
        "required command '$command_name' was not found."
done
if [[ "$acceleration" == kvm ]]; then
    [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]] || fail \
        "KVM is not accessible to this user at /dev/kvm. Ask your administrator to enable user access; this script will not use sudo."
fi

# Homebrew installs the EDK II firmware that QEMU needs to boot an ARM64 cloud
# image under its QEMU share directory. Keep the standard locations too, so a
# manually installed QEMU can still be used by setting ARM_UEFI_{CODE,VARS}.
macos_qemu_share_dirs=()
if [[ "$host_os" == Darwin ]]; then
    if command -v brew >/dev/null 2>&1; then
        qemu_brew_prefix=$(brew --prefix qemu 2>/dev/null || true)
        [[ -z "$qemu_brew_prefix" ]] || macos_qemu_share_dirs+=("$qemu_brew_prefix/share/qemu")
    fi
    macos_qemu_share_dirs+=(/opt/homebrew/share/qemu /usr/local/share/qemu)
fi

login_name=${USER:-$(id -un)}
if [[ "$host_os" == Darwin ]]; then
    default_vm_dir=$HOME/vm
else
    default_vm_dir=/goinfre/$login_name/vm
fi
vm_dir=${VM_DIR:-$default_vm_dir}
vm_username=${VM_USERNAME:-$login_name}
vm_hostname=${VM_HOSTNAME:-dev-$vm_username}
ssh_public_key=${SSH_PUBLIC_KEY:-$HOME/.ssh/id_rsa.pub}
disk_size_gb=${DISK_SIZE_GB:-50}
vm_memory=${VM_MEMORY:-6G}
vm_cpus=${VM_CPUS:-4}
ssh_port=${SSH_PORT:-2222}
vm_debug=${VM_DEBUG:-0}
# Pin Docker's packages so every VM rebuild receives the same toolchain.
docker_engine_version=${DOCKER_ENGINE_VERSION:-5:29.9.0-1~ubuntu.24.04~noble}
docker_compose_version=${DOCKER_COMPOSE_VERSION:-5.6.0-1~ubuntu.24.04~noble}
docker_buildx_version=${DOCKER_BUILDX_VERSION:-0.38.0-1~ubuntu.24.04~noble}
containerd_version=${CONTAINERD_VERSION:-2.4.1-2~ubuntu.24.04~noble}
# Pin one published image build so teammates start from matching guest images.
ubuntu_image_release=20260926
disk_path=$vm_dir/ubuntu-server-cloud-$image_arch-$ubuntu_image_release.qcow2
image_dir=$vm_dir/images
base_image=$image_dir/ubuntu-24.04-server-cloudimg-$image_arch-$ubuntu_image_release.img
seed_dir=$vm_dir/cloud-init-$ubuntu_image_release
needs_first_boot=false

[[ "$vm_username" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || fail \
    "VM_USERNAME must be a valid simple Linux username."
[[ "$vm_hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || fail \
    "VM_HOSTNAME must contain only letters, digits, dots, and hyphens."
[[ -r "$ssh_public_key" ]] || fail \
    "SSH public key not found at '$ssh_public_key'. Create one with ssh-keygen or set SSH_PUBLIC_KEY."
[[ "$disk_size_gb" =~ ^[1-9][0-9]*$ ]] || fail \
    "DISK_SIZE_GB must be a positive whole number of GiB (for example, 50)."
[[ "$vm_cpus" =~ ^[1-9][0-9]*$ ]] || fail \
    "VM_CPUS must be a positive whole number (for example, 4)."
[[ "$ssh_port" =~ ^[0-9]+$ ]] && (( ssh_port >= 1 && ssh_port <= 65535 )) || fail \
    "SSH_PORT must be a TCP port between 1 and 65535."
[[ "$vm_memory" =~ ^[1-9][0-9]*[GgMm]$ ]] || fail \
    "VM_MEMORY must be a positive number followed by G or M (for example, 6G)."
[[ "$vm_debug" == 0 || "$vm_debug" == 1 ]] || fail \
    "VM_DEBUG must be 0 or 1."
for package_version in "$docker_engine_version" "$docker_compose_version" "$docker_buildx_version" "$containerd_version"; do
    [[ "$package_version" =~ ^[A-Za-z0-9:.+~=-]+$ ]] || fail \
        "Docker package versions may contain only letters, digits, colon, dot, plus, tilde, equals, and hyphen."
done

read -r key_type key_data _ < "$ssh_public_key"
[[ "$key_type" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))$ && -n "$key_data" ]] || fail \
    "'$ssh_public_key' does not look like a supported OpenSSH public key."
ssh_key=$(<"$ssh_public_key")

mkdir -p "$vm_dir" "$image_dir"
chmod 700 "$vm_dir"

if [[ ! -e "$disk_path" ]]; then
    # Ubuntu publishes cloud-init-enabled KVM images separately per CPU architecture.
    image_name="ubuntu-24.04-server-cloudimg-$image_arch.img"
    release_url="https://cloud-images.ubuntu.com/releases/noble/release-$ubuntu_image_release"
    image_url="$release_url/ubuntu-24.04-server-cloudimg-$image_arch.img"
    checksum_url="$release_url/SHA256SUMS"

    python3 - "$base_image" "$image_url" "$checksum_url" "$image_name" <<'PYTHON'
import hashlib
import os
import sys
import urllib.request

image_path, image_url, checksum_url, image_name = sys.argv[1:]
print(f"Fetching Ubuntu checksum list: {checksum_url}", flush=True)
with urllib.request.urlopen(checksum_url, timeout=60) as response:
    checksum_lines = response.read().decode("ascii").splitlines()
expected = None
for line in checksum_lines:
    fields = line.split()
    if len(fields) == 2 and fields[1].lstrip("*") == image_name:
        expected = fields[0].lower()
        break
if expected is None:
    raise SystemExit(f"No SHA-256 checksum for {image_name} in {checksum_url}")

def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

if os.path.exists(image_path):
    actual = sha256_file(image_path)
    if actual != expected:
        raise SystemExit(f"Cached Ubuntu image checksum mismatch: {image_path}")
    print(f"Using verified cached image: {image_path}", flush=True)
    raise SystemExit(0)

partial_path = image_path + ".part"
try:
    print(f"Downloading Ubuntu cloud image: {image_url}", flush=True)
    with urllib.request.urlopen(image_url, timeout=60) as response, open(partial_path, "wb") as image:
        total = int(response.headers.get("Content-Length", "0"))
        downloaded = 0
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            image.write(chunk)
            downloaded += len(chunk)
            if total:
                print(f"\rDownloaded {downloaded / (1024 ** 2):.0f} / {total / (1024 ** 2):.0f} MiB", end="", flush=True)
    if total:
        print(flush=True)
    actual = sha256_file(partial_path)
    if actual != expected:
        raise RuntimeError(f"SHA-256 verification failed: expected {expected}, got {actual}")
    os.replace(partial_path, image_path)
    print(f"Verified and cached cloud image: {image_path}", flush=True)
except Exception:
    try:
        os.remove(partial_path)
    except FileNotFoundError:
        pass
    raise
PYTHON

    printf 'Creating independent writable VM disk: %s\n' "$disk_path"
    qemu-img convert -f qcow2 -O qcow2 "$base_image" "$disk_path"
    qemu-img resize "$disk_path" "${disk_size_gb}G"

    # No password is embedded in the image. Each first boot receives this
    # developer's account name and public key through a read-only NoCloud seed.
    mkdir -p "$seed_dir"
    chmod 700 "$seed_dir"
    instance_id="dev-${login_name}-$(date +%s)"
    python3 - "$seed_dir" "$vm_username" "$vm_hostname" "$instance_id" "$ssh_key" \
        "$image_arch" "$docker_engine_version" "$docker_compose_version" "$docker_buildx_version" "$containerd_version" <<'PYTHON'
import json
import os
import sys

(
    seed_dir,
    username,
    hostname,
    instance_id,
    public_key,
    architecture,
    docker_engine_version,
    docker_compose_version,
    docker_buildx_version,
    containerd_version,
) = sys.argv[1:]
docker_architecture = {"amd64": "amd64", "arm64": "arm64"}[architecture]
docker_source = "\n".join([
    "Types: deb",
    "URIs: https://download.docker.com/linux/ubuntu",
    "Suites: noble",
    "Components: stable",
    f"Architectures: {docker_architecture}",
    "Signed-By: /etc/apt/keyrings/docker.asc",
    "",
])
runcmd = [
    ["install", "-m", "0755", "-d", "/etc/apt/keyrings"],
    ["curl", "-fsSL", "https://download.docker.com/linux/ubuntu/gpg", "-o", "/etc/apt/keyrings/docker.asc"],
    ["chmod", "a+r", "/etc/apt/keyrings/docker.asc"],
    ["apt-get", "update"],
    [
        "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y",
        f"docker-ce={docker_engine_version}",
        f"docker-ce-cli={docker_engine_version}",
        f"containerd.io={containerd_version}",
        f"docker-buildx-plugin={docker_buildx_version}",
        f"docker-compose-plugin={docker_compose_version}",
    ],
    ["systemctl", "enable", "--now", "docker"],
    ["usermod", "-aG", "docker", username],
]
cloud_config = "\n".join([
    "#cloud-config",
    f"hostname: {json.dumps(hostname)}",
    "manage_etc_hosts: true",
    "ssh_pwauth: false",
    "disable_root: true",
    "ssh_deletekeys: true",
    "ssh_genkeytypes: [ed25519]",
    "users:",
    f"  - name: {username}",
    "    groups: [adm, sudo]",
    "    shell: /bin/bash",
    '    sudo: "ALL=(ALL) NOPASSWD:ALL"',
    "    lock_passwd: true",
    "    ssh_authorized_keys:",
    f"      - {json.dumps(public_key)}",
    "packages:",
    "  - openssh-server",
    "  - ca-certificates",
    "  - curl",
    "package_update: true",
    "write_files:",
    "  - path: /etc/apt/sources.list.d/docker.sources",
    "    permissions: '0644'",
    f"    content: {json.dumps(docker_source)}",
    "runcmd:",
    *[f"  - {json.dumps(command)}" for command in runcmd],
    "",
])
files = {
    "user-data": cloud_config,
    "meta-data": f"instance-id: {instance_id}\nlocal-hostname: {hostname}\n",
}
for name, contents in files.items():
    path = os.path.join(seed_dir, name)
    with open(path, "w", encoding="utf-8") as stream:
        stream.write(contents)
    os.chmod(path, 0o600)
PYTHON
    chmod 700 "$seed_dir"
    needs_first_boot=true
else
    [[ -f "$disk_path" ]] || fail "VM disk path exists but is not a regular file: $disk_path"
    image_info=$(qemu-img info "$disk_path") || fail "could not read VM disk: $disk_path"
    [[ "$image_info" == *"file format: qcow2"* ]] || fail \
        "existing VM disk is not qcow2; refusing to use it: $disk_path"
    [[ -f "$seed_dir/user-data" && -f "$seed_dir/meta-data" ]] || fail \
        "cloud-init seed is missing. Refusing to boot without the original per-VM identity files: $seed_dir"
fi

qemu_args=(
    -m "$vm_memory"
    -smp "$vm_cpus"
    -drive "file=$disk_path,format=qcow2,if=virtio"
    -blockdev "driver=vvfat,node-name=cloudseed,read-only=on,dir=$seed_dir,label=CIDATA"
    -device virtio-blk-pci,drive=cloudseed
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${ssh_port}-:22"
    -device virtio-net-pci,netdev=net0
)

if [[ "$image_arch" == amd64 ]]; then
    qemu_args+=( -accel "$acceleration" -cpu host -boot order=c )
    firmware_code=${AMD64_UEFI_CODE:-}
    firmware_vars_template=${AMD64_UEFI_VARS:-}
    for firmware_pair in \
        /usr/share/edk2/ovmf/OVMF_CODE.fd\|/usr/share/edk2/ovmf/OVMF_VARS.fd \
        /usr/share/OVMF/OVMF_CODE_4M.fd\|/usr/share/OVMF/OVMF_VARS_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd\|/usr/share/OVMF/OVMF_VARS.fd; do
        candidate_code=${firmware_pair%%|*}
        candidate_vars=${firmware_pair#*|}
        [[ -n "$firmware_code" || ! -r "$candidate_code" ]] || firmware_code=$candidate_code
        [[ -n "$firmware_vars_template" || ! -r "$candidate_vars" ]] || firmware_vars_template=$candidate_vars
    done
    [[ -r "$firmware_code" ]] || fail \
        "AMD64 OVMF UEFI code firmware was not found; install the host OVMF package or set AMD64_UEFI_CODE."
    [[ -r "$firmware_vars_template" ]] || fail \
        "AMD64 OVMF UEFI variables template was not found; install the host OVMF package or set AMD64_UEFI_VARS."
    firmware_vars=$vm_dir/amd64-uefi-vars-$ubuntu_image_release.fd
    if [[ ! -e "$firmware_vars" ]]; then
        cp "$firmware_vars_template" "$firmware_vars"
        chmod 600 "$firmware_vars"
    fi
    qemu_args+=(
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$firmware_code"
        -drive "if=pflash,format=raw,unit=1,file=$firmware_vars"
    )
else
    qemu_args+=( -machine "virt,accel=$acceleration" -cpu host -boot order=c )
    firmware_code=${ARM_UEFI_CODE:-}
    firmware_vars_template=${ARM_UEFI_VARS:-}
    for candidate in /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw; do
        [[ -n "$firmware_code" || ! -f "$candidate" ]] || firmware_code=$candidate
    done
    for candidate in /usr/share/AAVMF/AAVMF_VARS.fd /usr/share/edk2/aarch64/vars-template-pflash.raw; do
        [[ -n "$firmware_vars_template" || ! -f "$candidate" ]] || firmware_vars_template=$candidate
    done
    for qemu_share_dir in "${macos_qemu_share_dirs[@]}"; do
        candidate=$qemu_share_dir/edk2-aarch64-code.fd
        [[ -n "$firmware_code" || ! -r "$candidate" ]] || firmware_code=$candidate
        candidate=$qemu_share_dir/edk2-arm-vars.fd
        [[ -n "$firmware_vars_template" || ! -r "$candidate" ]] || firmware_vars_template=$candidate
    done
    [[ -r "$firmware_code" ]] || fail \
        "ARM64 UEFI code firmware was not found; install QEMU with Homebrew or set ARM_UEFI_CODE."
    [[ -r "$firmware_vars_template" ]] || fail \
        "ARM64 UEFI variables template was not found; install QEMU with Homebrew or set ARM_UEFI_VARS."
    firmware_vars=$vm_dir/arm64-uefi-vars-$ubuntu_image_release.fd
    if [[ ! -e "$firmware_vars" ]]; then
        cp "$firmware_vars_template" "$firmware_vars"
        chmod 600 "$firmware_vars"
    fi
    qemu_args+=(
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=$firmware_code"
        -drive "if=pflash,format=raw,unit=1,file=$firmware_vars"
    )
fi

printf '\nStarting Ubuntu 24.04 LTS %s VM\n' "$image_arch"
printf '  Disk: %s\n' "$disk_path"
printf '  User: %s (SSH key login; password login disabled)\n' "$vm_username"
printf '  RAM: %s   CPUs: %s\n' "$vm_memory" "$vm_cpus"
printf '  SSH: localhost:%s -> guest:22\n' "$ssh_port"
if [[ "$needs_first_boot" == true ]]; then
    printf '  First boot will create the guest user and unique SSH host keys using cloud-init.\n'
fi

# Cloud-init is non-interactive, so normal boots run headlessly in the
# background. Debug mode keeps QEMU in the foreground, opens the guest VGA
# display, and connects the serial console and monitor to this terminal.
if [[ "$vm_debug" == 1 ]]; then
    printf 'Debug mode: QEMU stays in the foreground with a display window; use Ctrl-A C to switch between the serial console and QEMU monitor.\n'
    if [[ "$host_os" == Darwin ]]; then
        qemu_args+=( -display default -serial mon:stdio )
    else
        qemu_args+=( -display gtk -serial mon:stdio )
    fi
else
    qemu_args+=( -display none -daemonize )
fi

exec "$qemu_bin" "${qemu_args[@]}"
