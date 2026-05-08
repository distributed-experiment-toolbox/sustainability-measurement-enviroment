# Sustainable Deploy — Baremetal Kubernetes for Energy Experiments

Automated baremetal Kubernetes deployment with an opinionated
observability stack aimed at sustainability / energy-efficiency
experiments. The baseline is **runtime-agnostic**: it gives you a cluster
with RAPL access on SUT nodes and Kepler/Scaphandre/process-exporter
metrics, ready to be extended with whatever you want to measure.

# Basic Setup

## Nodes

| Role | # | Resources | Label | Requirements |
|--- |--- | --- | --- | --- |
| Control-plane | 1 | 8 vCPUs, 16 GB RAM | `role=system`, `workload-generator=true` | same network as SUT |
| SUT node(s) | n+ | Intel (Skylake+) or AMD Zen2+ CPU, 32 GB RAM | `role=sut` (baremetal) | RAPL access, Linux kernel 5.11+ (AMD) / 5.10+ (Intel), containerd v2 |

Make sure firewalls allow access between all nodes.

### SUT Node Recommendations

- **Intel:** Skylake or newer (e.g. Xeon E3-1275v5/v6). For i-series,
  12700K and above so efficiency cores are reported correctly.
- **AMD:** Zen 2 or newer (Ryzen 3000+/4000+, EPYC 7002+/7003+). Zen 1
  / Zen+ only expose package-level energy via RAPL — avoid for fine-
  grained measurements. With kernel ≥6.1 the `amd-pstate` driver is
  preferred; in active mode only `performance`/`powersave` governors
  are available (the `cpu_perf` role handles this).

## Cluster Base
- Debian based OS (Debian 13+ recommended)
- containerd 2.2+
- Kubernetes 1.32+
- Flannel CNI
- SUT CPUs pinned to `performance` governor with turbo disabled
  (see `cpu_perf` role; tweak via `cpu_governor`, `cpu_disable_turbo`,
  optional `cpu_max_cstate`, `cpu_isolate_cores` in group_vars)

## Observability Stack
| Component | Version |
|--- |--- |
| Helm [kube-prometheus-stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack) | v82+ |
| Helm [kepler](https://github.com/sustainable-computing-io/kepler) | v0.11+ |
| Helm [scaphandre](https://github.com/hubblo-org/scaphandre) | v1.0.2 |
| GIT [process-exporter](https://github.com/ncabatoff/process-exporter) | v0.8+ |

node-exporter (shipped with kube-prometheus-stack) runs on every SUT
with these extra collectors enabled:
`hwmon` (PMBus VRM, temps), `cpufreq` (live core frequency),
`thermal_zone`, `rapl` (powercap), `perf` (hardware PMU counters via
`CAP_PERFMON`). The `rapl` Ansible role sets
`kernel.perf_event_paranoid=0` and `kernel.kptr_restrict=0` so the
perf collector can read counters from inside the container.

# Workflow

1. Obtain 1+ baremetal instances (e.g. Hetzner dedicated server auctions),
   install Debian 13.
2. Obtain 1 VM / cheap dedicated server for the control-plane, install
   Debian 13.
3. Set up the cluster base on the nodes; the playbooks label them.
4. Install the observability stack on the cluster.
5. Drop in your workloads and run experiments, e.g. with SMA https://github.com/ISE-TU-Berlin/sustainability-measurement-agent.git / https://pypi.org/project/sustainability-measurement-agent/ 
# Installation

## Prerequisites

- Ansible installed on the machine running the playbooks (can be the
  control-plane itself or an external host)
- Passwordless SSH access from the Ansible controller to all nodes
- Debian 13+ on all nodes

## Quick Start

All `ansible-playbook` commands below run from the **Ansible
controller** (wherever you cloned this repository). The pre-cluster
playbook installs Kubespray on the **control-plane node** at
`/opt/kubespray`, so you SSH into the control-plane to run Step 4.

```bash
# -- On the Ansible controller --
cd ansible

# 1. Create your inventory from the example
cp inventory/hosts.yml.example inventory/hosts.yml
# Edit inventory/hosts.yml with your node IPs and SSH users

# 2. Review and adjust versions in inventory/group_vars/all.yml

# 3. Run pre-cluster setup
#    Installs base packages, containerd, configures RAPL on SUT,
#    and clones Kubespray on the control-plane.
ansible-playbook -i inventory/hosts.yml pre-cluster.yml
```

SSH into the control-plane:
```bash
ssh <user>@<control-plane-ip>

# 4. Run Kubespray on the control-plane
cd /opt/kubespray
source venv/bin/activate
ansible-playbook -i inventory/mycluster/hosts.yml cluster.yml \
  --become --become-user=root

# 5. Copy kubeconfig (still on the control-plane)
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
# Replace 127.0.0.1 in the config with the public IP of the
# control-plane so external tools can reach the API server.
sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl get nodes
```

Back on the Ansible controller:
```bash
cd ansible

# 6. Run post-cluster setup: CoreDNS fix, re-install Docker, label
#    nodes, install observability stack, ssh config on control-plane.
ansible-playbook -i inventory/hosts.yml post-cluster.yml
```