# Libvirt commands

Related: [[Ubuntu lab]], [[VM networking troubleshooting]]

All commands in the next sections run on the **host**. Names such as vnet1 and
the DHCP address can change; inspect current state before reusing them.

## Read-only inspection

```bash
# VM state and guest address reported from leases
virsh --connect qemu:///system list --all
virsh --connect qemu:///system domstate ubuntu-lab
virsh --connect qemu:///system domifaddr ubuntu-lab

# Interface attachment, link state, and traffic counters
virsh --connect qemu:///system domiflist ubuntu-lab
virsh --connect qemu:///system domif-getlink ubuntu-lab vnet1
virsh --connect qemu:///system domifstat ubuntu-lab vnet1

# Network state, configuration, and DHCP leases
virsh --connect qemu:///system net-info default
virsh --connect qemu:///system net-dumpxml default
virsh --connect qemu:///system net-dhcp-leases default

# Storage pools and volumes (the named pool may not exist after --force)
virsh --connect qemu:///system pool-list --all
virsh --connect qemu:///system pool-info ubuntu-lab
virsh --connect qemu:///system pool-dumpxml ubuntu-lab
virsh --connect qemu:///system vol-list ubuntu-lab
```

An empty lease list does not by itself prove the guest has no address. A pool
being active does not prove QEMU can access its files.

## Console and reboot — used during troubleshooting

```bash
virsh --connect qemu:///system console ubuntu-lab
virsh --connect qemu:///system reboot ubuntu-lab
```

Exit console with Ctrl+]. Reboot requests a guest restart and interrupts service.
Our guest has SSH key access; a console password was not configured.

## Lifecycle commands — reference for future practice

These are documented for learning; graceful shutdown and restart were not
verified as a complete exercise during this session.

```bash
virsh --connect qemu:///system shutdown ubuntu-lab
virsh --connect qemu:///system domstate ubuntu-lab
virsh --connect qemu:///system start ubuntu-lab
```

Shutdown is a request: verify the state before starting again. `destroy` means
an immediate power-off; `undefine` removes the persistent VM definition. Neither
should be used casually as an alternative to graceful shutdown.

## Host network diagnostics

```bash
ip addr show dev virbr0
ip link show dev vnet1
ip neigh show dev virbr0
sudo ss -lunp 'sport = :67'
sudo ss -luntp 'sport = :53'
sudo journalctl -b --no-pager -u virtnetworkd.service
sudo ufw status verbose
sudo nft list ruleset
```

These inspect state. Review logs before sharing them. Packet capture is described
in [[VM networking troubleshooting]].

## Connect from the host

```bash
ssh ubuntu@192.168.122.175
```

Check the current DHCP lease if that address no longer works.

## Inside the guest

```bash
sudo cloud-init status --wait
ip route
resolvectl --no-pager status
getent ahostsv4 archive.ubuntu.com
curl -4 -I --connect-timeout 5 --max-time 15 https://archive.ubuntu.com
```

These check provisioning, routing, DNS configuration, name resolution, and IPv4
HTTPS in that order. Curl requests headers only and limits connection/total time.
