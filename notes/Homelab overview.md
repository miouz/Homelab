# Homelab learning notes

The repository README is the roadmap: [project roadmap](../README.md).
These notes explain what I learned and how I verified it. The project is moving
from virtualisation foundations toward network isolation and remote administration.
The current Ubuntu VM still uses the default libvirt NAT network; OPNsense and
an isolated lab LAN are future work.

## Start here

- [[Virtualisation/Ubuntu lab|Ubuntu lab]] — configuration and verified state.
- [[Virtualisation/VM networking troubleshooting|VM networking troubleshooting]] — evidence, causes, fixes.
- [[Virtualisation/Libvirt commands|Libvirt commands]] — reusable commands and their effects.

## Documentation habit

After each session, record what changed, why, verification evidence, and what
remains untested. Label commands as host or guest. Never paste private keys,
passwords, tokens, or unreviewed sensitive logs.

Keep the project procedure in [the virtualisation README](../virtualisation/README.md).
Use these notes for learning and troubleshooting; avoid maintaining a second
complete copy of that procedure.

## Next steps

- Verify connectivity after a host reboot.
- Review storage socket and VM autostart separately.
- Practise graceful shutdown and startup.
- Review firewall scope before building the isolated network.
- Plan backups before keeping valuable guest data.
