# Ubuntu lab

Related: [[Homelab overview]], [[VM networking troubleshooting]], [[Libvirt commands]]

## Configuration observed on 2026-10-22

| Item | Value |
|---|---|
| Host | Omarchy / Arch Linux, also used as a desktop |
| VM | ubuntu-lab, Ubuntu Server 24.04 cloud image |
| Resources | 2 vCPUs, 2048 MiB RAM, 20 GiB virtual disk |
| Libvirt connection | qemu:///system |
| Network | default, NAT through virbr0 |
| Gateway and DNS | 192.168.122.1 |
| Observed guest IPv4 | 192.168.122.175 (DHCP; may change) |
| SSH user | ubuntu |
| Runtime files | /var/lib/libvirt/images/ubuntu-lab/ |

## What the components do

- KVM provides kernel virtualisation; QEMU runs the guest.
- Libvirt manages VM definitions, networks, and storage pools.
- A storage pool describes a location; Linux file permissions still apply.
- Cloud-init reads the seed ISO to configure the hostname, user, and SSH key.
- QCOW2 provides a virtual disk whose allocated space can be smaller than capacity.
- DHCP assigns an address, DNS resolves names, and NAT translates outbound traffic.

## Evidence collected

- Downloaded image matched its checksum manifest.
- Domain creation completed and console reached a login prompt.
- SSH connected successfully.
- `sudo cloud-init status --wait` returned `status: done`.
- DHCP lease showed 192.168.122.175.
- `getent ahostsv4 archive.ubuntu.com` returned IPv4 addresses.
- IPv4 HTTPS request returned `HTTP/1.1 200 OK` after UFW changes.

These checks do not establish reboot persistence, IPv6 connectivity, backups,
or workload performance. The 2 GiB recommendation warning did not block boot.

## Storage lesson

QEMU could not traverse the private home directory. Moving runtime files to
system libvirt storage avoided granting traversal through the home directory.
Preparation files remain in the project's ignored `.vm/` directory. After boot,
the runtime disk changes independently; the preparation copy is not a backup.

## Automation

See [the script and full setup history](../../virtualisation/README.md).
Run the script from the virtualisation directory as the normal user.
`--force` permanently removes the previous named VM and its matching lab files
before rebuilding. A failed rebuild does not restore the old VM.
