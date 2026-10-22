# Ubuntu VM provisioning

Create an Ubuntu Server 24.04 cloud-image VM using KVM/QEMU, libvirt, and cloud-init.
See the [project roadmap](../README.md) for objectives and planned phases.

## Requirements

- An x86_64 Linux host with working KVM/QEMU and system libvirt access.
- Run as your normal user with access to `qemu:///system`, not as root.
- Commands: `curl`, `sha256sum`, `qemu-img`, `virsh`, `virt-install`, `xorriso`,
  `ssh-keygen`, `python3`, and `sudo`.
- An existing SSH public key; the default is `~/.ssh/id_rsa.pub`.
- An existing active libvirt network; the default is `default`.
- Working libvirt storage access and an existing, searchable
  `/var/lib/libvirt/images/` directory.
- Host firewall rules permitting guest DHCP, DNS, and intended forwarded traffic.
  See the [network troubleshooting note](../notes/Virtualisation/VM%20networking%20troubleshooting.md).

The script does not install software, start networks, or configure the firewall.

## Create a VM

Run from this directory:

```bash
bash create-vm.sh --help
bash create-vm.sh --name ubuntu-lab
```

Defaults: 2048 MiB RAM, 2 vCPUs, and a 20 GiB virtual disk.
For a different public key:

```bash
bash create-vm.sh --name ubuntu-lab --ssh-key ~/.ssh/id_ed25519.pub
```

The script downloads and checks the image, prepares cloud-init, copies runtime
files with `sudo`, and registers and starts the VM. Existing VM definitions and
preparation/runtime destinations are protected by default.

## Storage

| Location | Purpose |
|---|---|
| `.vm/<name>/` under the lab directory | Download, checksum, cloud-init preparation, and initial disk copy; ignored by Git |
| `/var/lib/libvirt/images/<name>/` | Runtime `disk.qcow2` and `seed.iso` |

`--dir PATH` selects an existing lab directory; it defaults to the current directory.
After boot, the runtime disk changes independently of the preparation copy.
The preparation copy is not a backup. On failure, partial files remain for inspection.

## Replace a VM

```bash
bash create-vm.sh --force --name ubuntu-lab
```

**This permanently deletes the previous VM's data.** After preflight checks,
`--force` immediately stops the VM, removes its definition and matching pool
definition, and deletes both `.vm/<name>/` under the selected lab directory and
`/var/lib/libvirt/images/<name>/` before rebuilding.

Unexpected storage paths or detected shared storage block replacement. There is
no rollback: a failed rebuild does not restore the old VM. Use the same `--dir`
when replacing a VM created with a custom lab directory.

## Connect and verify

On the host, find the current guest address:

```bash
virsh --connect qemu:///system domifaddr ubuntu-lab
```

Connect with `ssh ubuntu@<guest-ip>`, replacing `<guest-ip>` with that address.
Then inside the guest:

```bash
sudo cloud-init status --wait
```

For network checks and expected results, see the notes below.

## Learning notes

- [Homelab overview](../notes/Homelab%20overview.md)
- [Ubuntu lab: concepts and verified state](../notes/Virtualisation/Ubuntu%20lab.md)
- [VM networking troubleshooting: evidence and fixes](../notes/Virtualisation/VM%20networking%20troubleshooting.md)
- [Libvirt commands: inspection and administration](../notes/Virtualisation/Libvirt%20commands.md)
