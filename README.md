# 🏠 Homelab — Infrastructure, Kubernetes, DevSecOps & SRE

> 🚀 **Turning a €150 second-hand PC into a production-inspired infrastructure learning lab.**

Welcome to my Homelab! 👋

I'm building this project to develop hands-on skills in **Linux, networking, virtualization, Kubernetes, DevSecOps, cloud infrastructure and Site Reliability Engineering (SRE)**.

This is more than a self-hosting project. My goal is to learn how to **design, build, operate, secure, troubleshoot and recover infrastructure**—and to understand *why* each architectural decision makes sense.

The main workload is **Briefly**, a microservices web application developed during a team project at 42. Briefly is already containerized with Docker Compose; in this Homelab, I will **deploy it directly to Kubernetes**, using the existing Compose files to understand service dependencies and configuration rather than repeating a Compose deployment.

### 🧠 My learning philosophy

**🔨 Build → 🧠 Understand → 🤖 Automate → 📊 Observe → 💥 Break → 🔍 Troubleshoot → 🔐 Secure → 🛟 Recover → 📝 Document**

The goal isn't the biggest Homelab or the longest technology list. It's to become an engineer who can operate infrastructure independently.

---

## 🖥️ Hardware & Environment

| Component | Specification |
|---|---|
| 🖥️ Host | HP EliteDesk 800 G4 SFF |
| ⚙️ CPU | Intel Core i7-8700 — 6 cores / 12 threads |
| 🧠 RAM | 16 GB DDR4 |
| 💾 Storage | 512 GB SSD |
| 🐧 Host OS | Omarchy (Arch Linux) |
| 📦 Virtualization | KVM / QEMU / libvirt |
| 🌐 Internet | Ethernet via Freebox |
| 💰 Initial cost | €150 (used hardware) |

The host is **both my desktop/media machine and my virtualization host**. Lab workloads must leave enough resources for normal desktop use.

**Hardware strategy:** Start with 16 GB, measure CPU/RAM/storage pressure, and upgrade to 32 GB only when justified. A second physical machine is optional later; two VMs on one host do **not** provide physical high availability.

## 🏗️ Target architecture

```text
                         INTERNET
                            |
                          FREEBOX
                            |
                          ETHERNET
                            |
                 HP EliteDesk 800 G4 SFF
                    Omarchy (Arch Linux)
                    Desktop + KVM/libvirt
                            |
                     libvirt NAT (WAN)
                            |
                        OPNsense VM
                      Firewall / Router
                            |
                     Isolated Lab LAN
                            |
           +----------------+----------------+
           |                                 |
     Ubuntu Server VM 1                Ubuntu Server VM 2
       K3s server                         K3s agent
     (control plane)                    (worker node)
           |                                 |
           +---------- K3s cluster ----------+
                            |
                  Briefly microservices
             Deployments / Services / Ingress
                 Config / Secrets / Storage
                            |
                 Observability & Security
            Prometheus / Grafana / Alerts
               RBAC / NetworkPolicies
```

**Note:** K3s server nodes can also schedule application Pods by default; workloads are not automatically restricted to the worker. I will inspect and control placement as part of learning scheduling.

**Availability limitation:** One K3s server means a single control-plane failure domain. Both Kubernetes nodes and OPNsense depend on the same physical host. This architecture is designed for learning, not production HA.

### 🔐 Remote administration and public access

```text
Personal laptop -- Tailscale --> Omarchy host (SSH jump host)
                                      |
                              Isolated lab network
                                      |
                           Ubuntu / Kubernetes nodes

External users -- HTTPS --> Secured Briefly entry point
                              (no public admin access)
```

Administrative interfaces (SSH, OPNsense, Kubernetes API, Grafana administration and databases) stay private. Public access to Briefly is a separate, deliberate security decision; a tunnel or controlled HTTPS ingress can be evaluated when the app is ready.

---

# 🗺️ Roadmap

## Progress tracker

- [x] 🧱 Phase 1 — Virtualization & Linux Foundation
- [ ] 🛡️ Phase 2 — Network Isolation & Remote Administration
- [ ] 🐧 Phase 3 — Linux Administration & Host Hardening
- [ ] ☸️ Phase 4 — Two-Node Kubernetes Foundation
- [ ] 🚀 Phase 5 — Deploy Briefly on Kubernetes
- [ ] 🔐 Phase 6 — Kubernetes & Application Security
- [ ] 📊 Phase 7 — Observability & SRE Operations
- [ ] 🌍 Phase 8 — Secure Public Access & HTTPS
- [ ] 💾 Phase 9 — Backup, Restore & Reliability
- [ ] 🔄 Phase 10 — CI/CD & Software Supply-Chain Security
- [ ] 🤖 Phase 11 — Infrastructure Automation & IaC
- [ ] 🔁 Phase 12 — GitOps & Kubernetes Operations
- [ ] 🕵️ Phase 13 — Advanced Security & Incident Response
- [ ] ☁️ Phase 14 — AWS & Cloud Infrastructure

> A phase is complete only after **implementation, verification and documentation**. The checked Phase 1 items reflect the status recorded in my previous README; future milestones must be validated as I progress.

---

## 🧱 Phase 1 — Virtualization & Linux Foundation

**🎯 Goal:** Understand and operate Linux virtualization before building a cluster.

### Tasks

- [x] Configure and validate KVM/QEMU/libvirt (initially on Fedora, now Omarchy).
- [x] Create and configure an Ubuntu Server VM.
- [x] Understand vCPU, memory, virtual disks and qcow2 images.
- [x] Explore libvirt bridges, DHCP and NAT.
- [x] Configure SSH key-based administration.
- [x] Manage VM lifecycle with `virsh`.
- [x] Troubleshoot VM startup, networking and storage issues.
- [x] Document the virtualization architecture.

**📦 Deliverables:** Virtualization diagram, VM setup notes and administration/troubleshooting runbook.

**✅ Success criteria:** I can create, connect to, restart, inspect and recover an Ubuntu VM using SSH and its virtual console.

---

## 🛡️ Phase 2 — Network Isolation & Remote Administration

**🎯 Goal:** Build a safe, inspectable virtual network without disrupting my home network.

### Tasks

- [ ] Deploy OPNsense with WAN and LAN virtual interfaces.
- [ ] Connect WAN to libvirt NAT and LAN to an isolated virtual network.
- [ ] Configure DHCP, DNS, routing, NAT and firewall policies.
- [ ] Place Ubuntu lab VMs behind OPNsense.
- [ ] Inspect traffic using `ip`, `ss`, `dig`, `tcpdump` and firewall logs.
- [ ] Configure Tailscale on Omarchy and my personal laptop.
- [ ] Access lab VMs through an SSH jump host.
- [ ] Test allowed and denied traffic and document recovery from a firewall mistake.

**📦 Deliverables:** Network diagram, firewall policy table, OPNsense configuration notes and remote-access runbook.

**✅ Success criteria:** Lab traffic follows intended paths, blocked traffic is demonstrably blocked, and private remote administration works.

---

## 🐧 Phase 3 — Linux Administration & Host Hardening

**🎯 Goal:** Establish secure, maintainable Ubuntu VM baselines.

### Tasks

- [ ] Configure users, groups, sudo and SSH key policies.
- [ ] Understand systemd, journald, service failures and boot diagnostics.
- [ ] Configure patching, time synchronization and host firewall rules.
- [ ] Inspect processes, sockets, disk space, memory and resource pressure.
- [ ] Apply least privilege and document access paths.
- [ ] Practice recovering from a broken service, DNS configuration or full filesystem.

**📦 Deliverables:** Ubuntu baseline checklist and troubleshooting runbooks.

**✅ Success criteria:** I can explain, secure, maintain and troubleshoot the operating systems supporting my cluster.

---

## ☸️ Phase 4 — Two-Node Kubernetes Foundation

**🎯 Goal:** Learn Kubernetes fundamentals using **two Ubuntu VMs**: one K3s server and one K3s worker.

### Tasks

- [ ] Measure available host RAM, CPU and storage before allocating VM resources.
- [ ] Provision a K3s server VM and a K3s agent VM on the isolated lab LAN.
- [ ] Install K3s and join the worker to the cluster.
- [ ] Inspect nodes, Pods, Deployments, ReplicaSets, Services and controllers.
- [ ] Understand container networking, CoreDNS, service discovery and the CNI.
- [ ] Explore scheduling, requests/limits, labels, taints and tolerations.
- [ ] Test node drain, worker shutdown and Pod rescheduling.
- [ ] Test control-plane unavailability and document what continues to run.
- [ ] Record actual RAM/CPU usage and decide whether 32 GB is needed.

**📦 Deliverables:** Cluster architecture diagram, bootstrap notes, node troubleshooting runbook and capacity measurements.

**✅ Success criteria:** Both nodes join successfully; I can explain where Pods run, how networking works and what happens when a node fails.

---

## 🚀 Phase 5 — Deploy Briefly on Kubernetes

**🎯 Goal:** Run an existing microservices application as a Kubernetes workload—not just a tutorial application.

### Tasks

- [ ] Inspect Briefly's Docker Compose services, images, ports, dependencies and volumes.
- [ ] Design Kubernetes Deployments, Services and namespaces for the real application.
- [ ] Configure environment values using ConfigMaps and appropriate secret handling.
- [ ] Set up persistent storage for PostgreSQL and other stateful components as needed.
- [ ] Configure readiness, liveness and startup probes.
- [ ] Define resource requests and limits based on measurements.
- [ ] Configure internal routing and an application Ingress.
- [ ] Test startup ordering assumptions, database connectivity and service discovery.
- [ ] Simulate Pod crashes and dependency failures; inspect events and logs.
- [ ] Document the differences between Compose and Kubernetes.

**📦 Deliverables:** Version-controlled Kubernetes manifests, Briefly architecture diagram, deployment runbook and Compose-to-Kubernetes comparison.

**✅ Success criteria:** Briefly runs inside K3s, retains its data, recovers from expected Pod failures and can be redeployed from documented configuration.

---

## 🔐 Phase 6 — Kubernetes & Application Security

**🎯 Goal:** Apply security controls to a real workload and **verify that they work**.

### Tasks

- [ ] Define a basic threat model for Briefly and the cluster.
- [ ] Configure least-privilege Kubernetes RBAC and service accounts.
- [ ] Apply Pod Security Admission and appropriate security contexts.
- [ ] Run containers as non-root where compatible; restrict privileges and capabilities.
- [ ] Implement NetworkPolicies between application components.
- [ ] Confirm that the installed K3s networking stack enforces those policies.
- [ ] Test allowed and denied connections with temporary diagnostic Pods.
- [ ] Review image provenance, dependencies, exposed ports and secret storage.
- [ ] Separate public application access from private cluster administration.

**📦 Deliverables:** Threat model, RBAC and NetworkPolicy manifests, security test evidence and security decisions.

**✅ Success criteria:** Intended application flows still work, unauthorized network/API actions fail, and security controls are validated—not merely declared.

---

## 📊 Phase 7 — Observability & SRE Operations

**🎯 Goal:** Understand the behavior and health of both Briefly and Kubernetes.

**Initial tools:** Prometheus, Grafana, Alertmanager and appropriate exporters; consider `kube-prometheus-stack` when resources allow.

### Tasks

- [ ] Measure observability-stack resource costs before deployment.
- [ ] Collect node, cluster, Pod and application metrics.
- [ ] Expose meaningful Briefly metrics such as requests, errors and latency.
- [ ] Learn PromQL and create focused Grafana dashboards.
- [ ] Define SLIs and an initial, realistic SLO for Briefly.
- [ ] Configure alerts for actionable failures and resource exhaustion.
- [ ] Investigate simulated Pod, node, database and application failures.
- [ ] Correlate Kubernetes events, logs, metrics and network evidence.
- [ ] Write an incident report and a blameless postmortem.

**📦 Deliverables:** Monitoring manifests/Helm values, dashboards, alert rules, SLI/SLO document and incident report.

**✅ Success criteria:** I can detect, diagnose and explain an outage using observable evidence.

---

## 🌍 Phase 8 — Secure Public Access & HTTPS

**🎯 Goal:** Allow other people to use Briefly while keeping lab management private.

### Tasks

- [ ] Choose an external-access design (for example, Cloudflare Tunnel or carefully controlled port forwarding).
- [ ] Configure domain DNS, HTTPS and certificate renewal.
- [ ] Understand Ingress, reverse-proxy headers, routing and timeouts.
- [ ] Publish only the intended Briefly HTTP(S) endpoint.
- [ ] Review application authentication, authorization and rate limiting.
- [ ] Verify SSH, OPNsense, Kubernetes API and databases are not publicly reachable.
- [ ] Test access from outside the home network and investigate failure scenarios.
- [ ] Document the security and availability limitations of a home-hosted service.

**📦 Deliverables:** Public-access diagram, DNS/TLS configuration, exposure checklist and troubleshooting runbook.

**✅ Success criteria:** Briefly is reachable over HTTPS by intended users, while infrastructure administration remains private.

---

## 💾 Phase 9 — Backup, Restore & Reliability

**🎯 Goal:** Recover Briefly and critical configuration after controlled failures.

### Tasks

- [ ] Identify important data, configuration and recovery dependencies.
- [ ] Implement and schedule PostgreSQL backups.
- [ ] Back up relevant manifests, configuration and cluster/bootstrap information.
- [ ] Distinguish VM snapshots from application-consistent backups.
- [ ] Define realistic RPO and RTO targets.
- [ ] Simulate data loss and restore into a test environment.
- [ ] Validate application behavior and data integrity after recovery.
- [ ] Document what cannot be recovered if the single physical host fails.

**📦 Deliverables:** Backup procedure, restore scripts, recovery runbook and restore-test report.

**✅ Success criteria:** I have performed a verified restoration—not merely produced backup files.

---

## 🔄 Phase 10 — CI/CD & Software Supply-Chain Security

**🎯 Goal:** Build, test, scan and deliver Briefly through a controlled pipeline.

**Target tools:** GitHub Actions, container registry, Trivy and SBOM tooling.

### Tasks

- [ ] Run application tests and linting in CI.
- [ ] Build reproducible, versioned container images.
- [ ] Scan dependencies, images and infrastructure configuration.
- [ ] Detect accidentally committed secrets and protect CI credentials.
- [ ] Generate SBOMs and review vulnerability findings.
- [ ] Apply sensible policies for failing builds on serious findings.
- [ ] Publish images with traceable tags or digests.
- [ ] Automate a controlled Kubernetes deployment and health verification.
- [ ] Test rollback after a deliberately bad release.

**📦 Deliverables:** GitHub Actions workflows, image build pipeline, security reports and release/rollback runbook.

**✅ Success criteria:** A change can be tested, scanned, built, deployed, verified and rolled back with documented controls.

---

## 🤖 Phase 11 — Infrastructure Automation & IaC

**🎯 Goal:** Rebuild the lab reproducibly without hiding how it works.

**Target tools:** Bash, Ansible, cloud-init, libvirt; Terraform where it adds value.

### Tasks

- [ ] Document manual setup before automating it.
- [ ] Automate Ubuntu baseline configuration with Ansible.
- [ ] Use cloud-init for initial VM configuration.
- [ ] Automate K3s VM provisioning and cluster bootstrap.
- [ ] Test Ansible idempotency and safe reruns.
- [ ] Evaluate declarative provisioning with Terraform where appropriate.
- [ ] Rebuild a disposable node from version-controlled configuration.

**📦 Deliverables:** Ansible roles/playbooks, VM provisioning definitions and rebuild runbook.

**✅ Success criteria:** I can recreate a known-good lab component with minimal undocumented manual steps.

---

## 🔁 Phase 12 — GitOps & Kubernetes Operations

**🎯 Goal:** Manage Kubernetes desired state through Git and observe reconciliation.

**Potential tools:** Kustomize or Helm, then Flux or Argo CD—choose based on a concrete need.

### Tasks

- [ ] Organize Briefly manifests into maintainable environments/overlays.
- [ ] Introduce Helm or Kustomize and explain the trade-offs.
- [ ] Install a GitOps controller if host capacity permits.
- [ ] Reconcile application configuration from Git.
- [ ] Test drift detection, failed rollouts and recovery.
- [ ] Separate deployment permissions from broad cluster-admin privileges.
- [ ] Document cluster maintenance and upgrade procedures.

**📦 Deliverables:** GitOps repository structure, deployment definitions and operational runbooks.

**✅ Success criteria:** Git is the documented source of desired application state, and I can explain and troubleshoot reconciliation.

---

## 🕵️ Phase 13 — Advanced Security & Incident Response

**🎯 Goal:** Explore detection and response after core security and observability are reliable.

### Tasks

- [ ] Assess whether runtime detection (such as Falco) is useful and affordable on this host.
- [ ] Investigate suspicious container behavior in a controlled test.
- [ ] Correlate security events with Kubernetes audit/logging data where available.
- [ ] Evaluate centralized secrets management only if it solves a demonstrated problem.
- [ ] Practice credential rotation and access revocation.
- [ ] Conduct a small incident-response exercise and document lessons learned.

**📦 Deliverables:** Security experiment notes, incident timeline, response runbook and improvement actions.

**✅ Success criteria:** I can explain a realistic threat, detect or investigate it, contain it and document the response.

---

## ☁️ Phase 14 — AWS & Cloud Infrastructure

**🎯 Goal:** Transfer Homelab skills to cloud infrastructure without unnecessary spending.

### Tasks

- [ ] Learn AWS IAM, VPCs, subnets, routing and security groups.
- [ ] Provision a small environment using Terraform.
- [ ] Deploy a selected Briefly component or another tightly scoped workload.
- [ ] Apply least privilege, logging, cost limits and secure networking.
- [ ] Compare AWS networking, compute, security and operations with the Homelab.
- [ ] Destroy cloud resources reproducibly and verify cleanup.

**📦 Deliverables:** Terraform configuration, architecture diagram, cost report and local-versus-cloud comparison.

**✅ Success criteria:** I can provision, secure, inspect and remove a small cloud environment safely.

---

## 🧪 Engineering habits

For each meaningful milestone, I aim to answer:

1. **Why?** What problem does this component solve?
2. **How?** What is happening under the hood?
3. **Verify:** What evidence proves it works?
4. **Break:** What fails, and how can I observe it?
5. **Secure:** What is exposed, and who has access?
6. **Recover:** How do I restore service and data?
7. **Document:** Could I explain or rebuild this later?

Security and reliability are **cross-cutting practices**, not features added only at the end.

## 🔧 Resource and scope decisions

- **16 GB first:** Keep VM sizing conservative; measure host and guest memory before adding monitoring or GitOps controllers.
- **32 GB if needed:** Upgrade RAM when actual Kubernetes/application/observability requirements justify it.
- **Two Kubernetes VMs:** One K3s server and one worker provide useful networking, scheduling and failure exercises—not high availability.
- **One main workload:** Use Briefly to make architecture, CI/CD, observability and security exercises realistic.
- **No tool collection:** Add components only when they solve a problem or teach a clear, transferable skill.

## 📚 Documentation & Portfolio

The repository will progressively contain:

- [ ] Architecture and network diagrams.
- [ ] Version-controlled VM and Kubernetes configuration.
- [ ] Briefly deployment manifests and security policies.
- [ ] CI/CD workflows and security scan results.
- [ ] Grafana dashboards, alerts and SLI/SLO definitions.
- [ ] Backup and **verified restore** reports.
- [ ] Runbooks, incident postmortems and architecture decision records (ADRs).
- [ ] Measured resource usage and architectural trade-offs.

**Never commit** credentials, private keys, access tokens, production secrets or sensitive backups.

## 🚧 Current status

**Completed (per previous project checklist):** Phase 1 — virtualization and Linux foundation.

**Next:** Build the isolated OPNsense network, harden Ubuntu VMs, provision the two-node K3s cluster, and deploy Briefly directly on Kubernetes.

**Long-term objective:** A reproducible, observable, secure and recoverable microservices platform—and the skills to explain, operate and troubleshoot it independently.

---

## 🙏 Inspiration

Inspired in part by [Stéphane Robert's Homelab](https://www.stephane-robert.info/docs/homelab/), adapted to my own hardware, application and learning goals.

**💻 Small hardware. 🧠 Deep learning. 🔧 Real infrastructure problems. 🚀**
