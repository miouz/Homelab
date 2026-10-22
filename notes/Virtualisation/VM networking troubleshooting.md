# VM networking troubleshooting

Related: [[Ubuntu lab]], [[Libvirt commands]]

Session: 2026-10-22. Commands below are historical fixes, not a checklist to
rerun blindly. Host commands run on Omarchy; guest commands run inside Ubuntu.

## Missing storage socket

**Symptom:** virt-install could not connect to virtstoraged-sock.
**Evidence:** virtstoraged.socket was installed but inactive.
**Host fix:**

```bash
sudo systemctl start virtstoraged.socket
systemctl is-active virtstoraged.socket
```

**Result:** active. Starting a socket does not enable it for later boots.

## Disk access denied

**Symptom:** QEMU could not access the disk under the home directory.
**Evidence:** `/home/mi` had mode 0700; the error identified traversal permissions.
**Fix:** copied disk and seed ISO to `/var/lib/libvirt/images/ubuntu-lab/`, verified
copies with cmp, and updated the pool target before starting it.
**Result:** VM creation completed. Full migration commands are in the project README.

## DHCP requests received no replies

**Evidence:** guest running, link up, network active, DHCP range configured,
dnsmasq listening on UDP 67. Traffic counters alone did not identify DHCP.
A packet capture showed guest requests with no replies:

```bash
# Host; tcpdump was installed using sudo pacman -S --needed tcpdump
sudo tcpdump -ni virbr0 -e 'udp port 67 or udp port 68'
sudo nft list ruleset
```

UFW counters showed port 67 packets reaching a drop rule.

**Host fix:**

```bash
sudo ufw allow in on virbr0 proto udp from any port 68 to any port 67
virsh --connect qemu:///system net-dhcp-leases default
```

**Result:** lease assigned. Initial DHCP requests use 0.0.0.0, so the rule cannot
require the guest's future subnet address as the source.

## DNS failed despite an address and route

**Evidence:** guest used 192.168.122.1 as DNS and gateway, but getent returned no
addresses. UFW status showed DNS allowances were missing.

**Host fix:**

```bash
sudo ufw allow in on virbr0 proto udp from 192.168.122.0/24 to 192.168.122.1 port 53
sudo ufw allow in on virbr0 proto tcp from 192.168.122.0/24 to 192.168.122.1 port 53
```

**Guest verification:**

```bash
getent ahostsv4 archive.ubuntu.com
```

**Result:** IPv4 addresses returned.

## HTTPS timed out after DNS worked

**Evidence:** curl timed out; UFW denied routed traffic with no guest forwarding
allowance. Libvirt NAT rules were present.

**Host fix:**

```bash
sudo ufw route allow in on virbr0 from 192.168.122.0/24 to any
```

**Guest verification:**

```bash
curl -4 -I --connect-timeout 5 --max-time 15 https://archive.ubuntu.com
```

**Result:** HTTP 200 OK. This forwarding rule includes reachable LAN destinations;
review its scope when designing isolation. UFW rules are persistent, but behavior
after a host reboot has not been tested.

## Reusable reasoning

1. Check VM state and interface attachment.
2. Check link, bridge, DHCP configuration and listening sockets.
3. Capture traffic to distinguish requests from replies.
4. Inspect firewall rules and counters.
5. Verify address, route, DNS, then outbound connectivity separately.

DHCP and DNS requests go **to the host**: input rules apply. Guest internet
traffic goes **through the host**: forwarding rules apply. Use UFW to manage its
rules rather than editing generated nftables tables directly.
