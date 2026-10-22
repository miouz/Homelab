#!/usr/bin/env bash
# Download an Ubuntu cloud image, seed cloud-init, and boot a libvirt VM.
set -Eeuo pipefail
umask 077

usage() {
    cat <<'EOF'
Usage: bash create-vm.sh [options]
  --name NAME       VM name and hostname (default: ubuntu-lab)
  --dir PATH        Lab directory (default: current directory; files in .vm/)
  --ssh-key PATH    SSH public key (default: ~/.ssh/id_rsa.pub)
  --network NAME    Existing active libvirt network (default: default)
  --memory MIB      Guest RAM (default: 2048)
  --cpus NUMBER     Virtual CPUs (default: 2)
  --disk GIB        Virtual disk capacity (default: 20; minimum: 4)
  --force           Permanently delete and recreate the named VM and its lab files
  --help            Show this help without changing anything

Uses qemu:///system. Run as your normal user with libvirt access.
Requires curl, sha256sum, qemu-img, virsh, virt-install, xorriso, ssh-keygen, python3, sudo.
Downloads and cloud-init preparation stay in .vm/ under the lab directory.
Runtime disk and ISO go in /var/lib/libvirt/images/NAME (sudo required).
No software is installed and no networks are created or started.
On failure, partial files are retained for inspection; no automatic deletion.
--force immediately stops the old VM and deletes its data before rebuilding.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
set_defaults() {
    name=ubuntu-lab
    lab_dir=$PWD
    ssh_key=$HOME/.ssh/id_rsa.pub
    network=default
    memory=2048
    cpus=2
    disk=20
    uri=qemu:///system
    force=false
    image=noble-server-cloudimg-amd64.img
    base_url=https://cloud-images.ubuntu.com/noble/current
}

parse_args() {
    while (($#)); do
        case $1 in
            --help|-h) usage; exit 0 ;;
            --force) force=true; shift ;;
            --name|--dir|--ssh-key|--network|--memory|--cpus|--disk)
                (($# >= 2)) || die "Missing value for $1"
                case $1 in
                    --name) name=$2 ;; --dir) lab_dir=$2 ;;
                    --ssh-key) ssh_key=$2 ;; --network) network=$2 ;;
                    --memory) memory=$2 ;; --cpus) cpus=$2 ;; --disk) disk=$2 ;;
                esac
                shift 2 ;;
            *) die "Unknown option: $1 (see --help)" ;;
        esac
    done
}

validate_config() {
    local value
    [[ $name =~ ^[a-z][a-z0-9-]{0,61}[a-z0-9]$ ]] || die 'Use a lowercase hostname of 2–63 characters.'
    [[ $network =~ ^[a-zA-Z0-9_-]+$ ]] || die 'Invalid network name.'
    for value in "$memory" "$cpus" "$disk"; do
        [[ $value =~ ^[1-9][0-9]{0,6}$ ]] || die 'Resource sizes must be positive integers.'
    done
    ((disk >= 4)) || die 'Disk must be at least 4 GiB.'
    [[ $(uname -m) == x86_64 ]] || die 'This script uses the amd64 image and requires an x86_64 host.'
    ((EUID != 0)) || die 'Run as your normal user, not with sudo.'
}

check_dependencies() {
    local tool
    local -a missing=()
    for tool in curl sha256sum qemu-img virsh virt-install xorriso ssh-keygen python3 sudo; do
        command -v "$tool" >/dev/null || missing+=("$tool")
    done
    ((${#missing[@]} == 0)) || die "Missing commands: ${missing[*]}"
}

validate_ssh_key() {
    [[ -f $ssh_key && $ssh_key == *.pub ]] || die 'Specify an existing .pub SSH public key.'
    ssh-keygen -lf "$ssh_key" >/dev/null || die 'Invalid SSH public key.'
}

resolve_paths() {
    [[ -d $lab_dir ]] || die 'The lab directory must already exist.'
    lab_dir=$(cd -- "$lab_dir" && pwd -P)
    [[ $lab_dir != *,* && $lab_dir != *$'\n'* ]] || die 'The lab path must not contain commas or newlines.'
    root=$lab_dir/.vm
    vm_dir=$root/$name
    storage_dir=/var/lib/libvirt/images/$name
    if ! $force; then
        [[ ! -e $vm_dir && ! -L $vm_dir ]] || die "Refusing to overwrite $vm_dir (use --force to replace it)"
    fi
    [[ ! -L $root ]] || die 'The .vm directory must not be a symlink.'
    [[ -d /var/lib/libvirt/images && -x /var/lib/libvirt/images ]] || die 'Storage directory /var/lib/libvirt/images must exist and be searchable.'
    if ! $force; then
        [[ ! -e $storage_dir && ! -L $storage_dir ]] || die "Refusing to overwrite $storage_dir (use --force to replace it)"
    fi
}

check_libvirt() {
    local active_networks found entry
    virsh --connect "$uri" list --all >/dev/null || die 'Cannot access system libvirt.'
    virsh --connect "$uri" pool-list --all >/dev/null || die 'Cannot access libvirt storage. Check virtstoraged.socket before retrying.'
    if virsh --connect "$uri" dominfo "$name" >/dev/null 2>&1; then
        $force || die "VM $name already exists (use --force to replace it)."
    fi
    active_networks=$(virsh --connect "$uri" net-list --name)
    found=false
    while IFS= read -r entry; do
        [[ $entry != "$network" ]] || found=true
    done <<< "$active_networks"
    $found || die "Network $network is not active."
}

replace_existing_vm() {
    $force || return 0
    local replacement_state domain_exists domain_active pool_exists pool_active
    # Inspect all references before stopping anything or deleting files.
    replacement_state=$(python3 - "$uri" "$name" "$vm_dir" "$storage_dir" <<'PY'
import pathlib, subprocess, sys, xml.etree.ElementTree as ET
uri, name, workspace, storage = sys.argv[1:]
roots = [pathlib.Path(workspace), pathlib.Path(storage)]
def fail(message):
    raise SystemExit('Refusing --force: ' + message)
def virsh(*args):
    return subprocess.check_output(['virsh', '--connect', uri, *args], text=True)
def names(*args):
    return virsh(*args).splitlines()
def inside(path):
    return any(path == root or root in path.parents for root in roots)
for root in roots:
    if root.resolve() != root:
        fail(f'symlink or unexpected resolved path: {root}')
    if root.exists() and not root.is_dir():
        fail(f'not a directory: {root}')
domains = names('list', '--all', '--name')
for domain in filter(None, domains):
    # A transient domain has no inactive definition.
    current = ET.fromstring(virsh('dumpxml', domain))
    definitions = [current]
    persistent = subprocess.run(
        ['virsh', '--connect', uri, 'dumpxml', domain, '--inactive'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if persistent.returncode == 0:
        definitions.append(ET.fromstring(persistent.stdout))
    for definition in definitions:
        for disk in definition.findall('./devices/disk'):
            source = disk.find('source')
            if source is None:
                continue
            path = source.get('file') or source.get('dev')
            if domain == name:
                allowed = {str(root / filename) for root in roots
                           for filename in ('disk.qcow2', 'seed.iso')}
                if path not in allowed or pathlib.Path(path).resolve() != pathlib.Path(path):
                    fail(f'VM {name} uses unexpected storage')
            elif path and inside(pathlib.Path(path).resolve()):
                fail(f'another VM ({domain}) uses the replacement directories')
            elif source.get('pool') == name:
                fail(f'another VM ({domain}) references the named pool')
pools = names('pool-list', '--all', '--name')
for pool in filter(None, pools):
    definitions = [ET.fromstring(virsh('pool-dumpxml', pool))]
    pending = subprocess.run(
        ['virsh', '--connect', uri, 'pool-dumpxml', pool, '--inactive'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if pending.returncode == 0:
        definitions.append(ET.fromstring(pending.stdout))
    for definition in definitions:
        target = definition.findtext('./target/path')
        if pool == name:
            if definition.get('type') != 'dir' or target not in (workspace, storage):
                fail(f'pool {name} has an unexpected target')
        elif target and inside(pathlib.Path(target).resolve()):
            fail(f'another pool ({pool}) uses the replacement directories')
active_domains = names('list', '--name')
active_pools = names('pool-list', '--name')
print(*(str(value).lower() for value in
        (name in domains, name in active_domains, name in pools, name in active_pools)))
PY
    ) || die 'Replacement safety checks failed; nothing has been deleted.'
    read -r domain_exists domain_active pool_exists pool_active <<< "$replacement_state"
    printf 'Replacing %s: permanently deleting VM data in %s and %s\n' \
        "$name" "$vm_dir" "$storage_dir"
    sudo -v || die 'Cannot obtain sudo access; nothing has been deleted.'
    if $domain_active; then
        virsh --connect "$uri" destroy "$name"
    fi
    if $domain_exists; then
        # Do not remove arbitrary attached storage or snapshot metadata.
        virsh --connect "$uri" undefine "$name"
    fi
    if $pool_active; then
        virsh --connect "$uri" pool-destroy "$name"
    fi
    if $pool_exists; then
        virsh --connect "$uri" pool-undefine "$name"
    fi
    # Exact validated directories only; refuse to cross mounted filesystems.
    rm -rf --one-file-system -- "$vm_dir"
    sudo rm -rf --one-file-system -- "$storage_dir"
}

prepare_workspace() {
    # Refuse to replace existing state even if another invocation races us.
    mkdir -p -- "$root"
    mkdir -- "$vm_dir"
    trap 'printf "Failed at line %s. Prepared files retained in %s; any runtime copies retained in %s\n" "$LINENO" "$vm_dir" "$storage_dir" >&2' ERR
}

download_image() {
    printf 'Downloading Ubuntu 24.04 and its checksum manifest...\n'
    curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' \
        "$base_url/SHA256SUMS" --output "$vm_dir/SHA256SUMS"
    curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' \
        "$base_url/$image" --output "$vm_dir/$image"
}

verify_image() {
    # Select exactly this image; never process arbitrary manifest paths.
    python3 - "$vm_dir" "$image" <<'PY'
import pathlib, re, sys
root, image = pathlib.Path(sys.argv[1]), sys.argv[2]
matches = []
for line in (root / 'SHA256SUMS').read_text().splitlines():
    fields = line.split()
    if len(fields) == 2 and fields[1].lstrip('*') == image:
        if re.fullmatch(r'[0-9a-fA-F]{64}', fields[0]):
            matches.append(fields[0])
if len(matches) != 1:
    raise SystemExit('Expected exactly one image checksum')
(root / 'image.sha256').write_text(f'{matches[0]}  {image}\n')
PY
    (cd -- "$vm_dir" && sha256sum --check image.sha256)
}

create_disk() {
    # A standalone copy avoids depending on a backing image after provisioning.
    qemu-img convert -f qcow2 -O qcow2 "$vm_dir/$image" "$vm_dir/disk.qcow2"
    qemu-img resize "$vm_dir/disk.qcow2" "${disk}G"
}

write_cloud_init() {
    # JSON is valid YAML and safely quotes the SSH key and hostname.
    python3 - "$vm_dir" "$name" "$ssh_key" <<'PY'
import json, pathlib, sys
root, name, key_path = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
key = key_path.read_text().strip()
if len(key.splitlines()) != 1:
    raise SystemExit('Expected one SSH public key')
config = {
    'hostname': name,
    'manage_etc_hosts': True,
    'disable_root': True,
    'ssh_pwauth': False,
    'users': [{
        'name': 'ubuntu', 'groups': ['sudo'], 'shell': '/bin/bash',
        'sudo': ['ALL=(ALL) NOPASSWD:ALL'], 'lock_passwd': True,
        'ssh_authorized_keys': [key],
    }],
}
(root / 'user-data').write_text('#cloud-config\n' + json.dumps(config, indent=2) + '\n')
(root / 'meta-data').write_text(json.dumps({'instance-id': name, 'local-hostname': name}) + '\n')
PY
}

create_seed_iso() {
    xorriso -as mkisofs -quiet -output "$vm_dir/seed.iso" -volid cidata \
        -joliet -rock "$vm_dir/user-data" "$vm_dir/meta-data"
}

copy_runtime_files() {
    printf 'Copying runtime disk and ISO to %s (requires sudo)...\n' "$storage_dir"
    # mkdir refuses an existing destination, including one created after preflight.
    # Keep the directory private until both copies have their final permissions.
    sudo mkdir -m 0700 -- "$storage_dir"
    sudo cp --sparse=always --no-clobber -- \
        "$vm_dir/disk.qcow2" "$vm_dir/seed.iso" "$storage_dir/"
    sudo chown root:root -- "$storage_dir/disk.qcow2" "$storage_dir/seed.iso"
    sudo chmod 0644 -- "$storage_dir/disk.qcow2" "$storage_dir/seed.iso"
    sudo chmod 0755 -- "$storage_dir"
}

start_vm() {
    printf 'Creating %s: %s MiB RAM, %s vCPUs, %s GiB disk, network %s\n' \
        "$name" "$memory" "$cpus" "$disk" "$network"
    virt-install --connect "$uri" --name "$name" --memory "$memory" --vcpus "$cpus" \
        --import --osinfo ubuntu24.04 \
        --disk "path=$storage_dir/disk.qcow2,format=qcow2,bus=virtio" \
        --disk "path=$storage_dir/seed.iso,device=cdrom" \
        --network "network=$network,model=virtio" \
        --graphics none --noautoconsole
}

print_next_steps() {
    printf '\nVM started; cloud-init may take a few minutes. Inspect its address with:\n'
    printf '  virsh --connect %s domifaddr %s\n' "$uri" "$name"
    printf 'Then SSH as ubuntu and verify provisioning with: sudo cloud-init status --wait\n'
    printf 'If no address appears, check your network DHCP server.\n'
}

# Configuration is shared by the workflow functions; scratch variables stay local.
main() {
    local name lab_dir ssh_key network memory cpus disk uri force
    local root vm_dir storage_dir image base_url

    set_defaults
    parse_args "$@"
    validate_config
    check_dependencies
    validate_ssh_key
    resolve_paths
    check_libvirt
    replace_existing_vm
    prepare_workspace
    download_image
    verify_image
    create_disk
    write_cloud_init
    create_seed_iso
    copy_runtime_files
    start_vm
    print_next_steps
}

main "$@"
