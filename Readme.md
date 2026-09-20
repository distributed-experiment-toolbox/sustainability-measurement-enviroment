# Sustainable Deploy — Baremetal Kubernetes for Energy Experiments

Automated baremetal Kubernetes with an observability stack aimed at
sustainability / energy-efficiency experiments. The baseline is
**runtime-agnostic**: it gives you a cluster with RAPL access on the SUT
nodes and Kepler / Scaphandre / process-exporter metrics, ready to be
extended with whatever you want to measure.

Packaged as the Ansible collection `sustian.deploy`, so several experiment
repositories can share one baseline instead of each carrying a copy.

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

`tools/hetzner_rapl_check.py` cross-references live Hetzner auction
listings against a RAPL compatibility table if you are shopping for nodes.

## Cluster Base
- Debian based OS (Debian 13+ recommended)
- containerd 2.2+, Kubernetes 1.32+, Flannel CNI

Exact pins and the values files that configure them:
[`configurations/Readme.md`](configurations/Readme.md).

## Observability Stack

kube-prometheus-stack, Kepler, Scaphandre and process-exporter, with
node-exporter running on every SUT with the `hwmon`, `cpufreq`,
`thermal_zone`, `rapl` and `perf` collectors enabled. The `rapl` role sets
`kernel.perf_event_paranoid=0` and `kernel.kptr_restrict=0` so the perf
collector can read counters from inside the container.

# Usage

## Install

```bash
ansible-galaxy collection install \
  git+https://github.com/distributed-experiment-toolbox/sustainability-measurement-enviroment.git
```

## Inventory contract

Two groups, `control_plane` and `sut`. Each host may set:

| Variable | Meaning |
|---|---|
| `ansible_host` | address the Ansible controller connects to |
| `internal_ip` | private address the nodes use to reach each other; defaults to `ansible_host` |
| `kubernetes_node_name` | node name as `kubectl get nodes` reports it |

See [`examples/minimal/`](examples/minimal/).

## Run

```bash
ansible-playbook -i hosts.yml sustian.deploy.pre_cluster
```

Then SSH to the control-plane and run Kubespray — the playbook prints the
exact commands, including the kubeconfig copy. Back on the controller:

```bash
ansible-playbook -i hosts.yml sustian.deploy.post_cluster
```

Kubespray is run by hand on purpose: it is long, it is noisy, and wrapping
it only hides the output you need when it fails.

## Extending

`pre_cluster` and `post_cluster` are reference assemblies, not the contract.
A project keeps its own inventory, group_vars and roles, and either wraps
them:

```yaml
- import_playbook: sustian.deploy.pre_cluster
- name: "My additions"
  hosts: sut
  roles: [my_role]
```

or ignores them and calls the roles directly by FQCN. To push settings into
Kubespray without forking the templates, use the extension hooks:

```yaml
kubespray_extra_cluster_vars:
  containerd_registries_mirrors: [...]
kubespray_extra_addons_vars:
  local_path_provisioner_enabled: true
```

[`examples/runwasi-experiment/`](examples/runwasi-experiment/) is a worked
example that adds a second container runtime.

## Roles

| Role | Runs on | Does |
|---|---|---|
| `ssh_access` | control-plane | generates a key, distributes it to the SUT nodes |
| `base_packages` | all | common packages, Helm, Skaffold |
| `docker` | control-plane | Docker for building images — run again post-cluster, Kubespray removes it |
| `containerd` | all | containerd v2, runc, CNI plugins, `config.d` imports |
| `rapl` | sut | msr module, perf sysctls, RAPL availability check |
| `cpu_perf` | sut | pins the governor, disables turbo, optional C-state / isolation cmdline |
| `kubespray` | control-plane | clones Kubespray and generates its inventory and overrides |
| `node_labels` | control-plane | applies `control_plane_labels` / `sut_labels` |
| `observability` | control-plane | kube-prometheus-stack, Kepler, Scaphandre |
| `process_exporter` | sut | process-exporter plus its Prometheus ScrapeConfig |
| `generate_ssh_config` | all | inventory names in `/etc/hosts`, ssh config on the control-plane |

Opinions are off by default and enabled in group_vars: `cpu_perf_enabled`,
`install_docker`, `coredns_patch_enabled`.

## Checking a change

```bash
ansible-playbook -i tests/inventory.yml tests/check.yml
```

No cluster needed — it renders the Kubespray templates and asserts the
values files, node labels and `internal_ip` handling still line up.
