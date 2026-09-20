# What gets installed, and where to tune it

Everything the measurement stack depends on is pinned. This table is the
whole surface: a version variable in a role's `defaults/main.yml`, and a
values file in this directory.

| Tool | Version variable | Default | Values file | Role |
|---|---|---|---|---|
| kube-prometheus-stack | `kube_prometheus_stack_chart_version` | `82.0.0` | `kube-prometheus-stack.yaml` | `observability` |
| kepler | `kepler_chart_version` | `0.11.4` | `kepler.yaml` | `observability` |
| scaphandre | `scaphandre_chart_version` | `1.0.2` | `scaphandre.yaml` | `observability` |
| process-exporter | `process_exporter_version` | `0.8.4` | `process-exporter.yml` | `process_exporter` |
| containerd | `containerd_version` | `2.2.1` | — | `containerd` |
| runc | `runc_version` | `1.4.0` | — | `containerd` |
| CNI plugins | `cni_plugins_version` | `1.9.0` | — | `containerd` |
| Kubespray | `kubespray_version` | `v2.30.0` | — | `kubespray` |
| Helm | `helm_version` | `v3.21.4` | — | `base_packages` |

Kubernetes, flannel and the runtime containerd come from Kubespray's own
pins: v2.30.0 means K8s 1.34.3, containerd 2.2.1, flannel 0.27.3.

## Replacing a values file

The roles read these files from the collection by default. Point the
variable at your own copy to replace one wholesale:

```yaml
kepler_values_file: "{{ playbook_dir }}/values/kepler.yaml"
kube_prometheus_stack_values_file: "{{ playbook_dir }}/values/kps.yaml"
scaphandre_values_file: "{{ playbook_dir }}/values/scaphandre.yaml"
process_exporter_config_file: "{{ playbook_dir }}/values/process-exporter.yml"
```

## What each file is responsible for

- **kube-prometheus-stack.yaml** — Prometheus itself (10s scrape, 8h
  retention, NodePort 30090) and node-exporter's collector set. The energy
  relevant collectors are `hwmon` (VRM power via PMBus, temps), `cpufreq`
  (live core frequency), `thermal_zone`, `rapl` (powercap) and `perf`
  (hardware PMU counters). `perf` needs `CAP_PERFMON` plus
  `kernel.perf_event_paranoid <= 0` on the host, which the `rapl` role sets.
  Grafana and Alertmanager are off — this cluster produces data, it does not
  display it.
- **kepler.yaml** — per-container energy attribution. Pins the image tag
  independently of the chart version.
- **scaphandre.yaml** — host and process level RAPL readings, as a
  cross-check on kepler. Installed from a git checkout, not a chart repo:
  the published chart is stale and does not deploy. See the comment in
  `roles/observability/tasks/main.yml` before changing that.
- **process-exporter.yml** — which processes get their own CPU/memory series
  on the SUT. Add your workload's process name here, otherwise it is
  invisible in the per-process breakdown.

## nodeSelectors

These files hardcode `role: sut` (kepler, node-exporter, scaphandre) and
`role: system` (Prometheus, the operator, kube-state-metrics). Those must
match `sut_labels` and `control_plane_labels`. The `observability` role
asserts they still agree and fails before installing anything if they do not.

## The perf CPU range

`--collector.perf.cpus=0-127` in `kube-prometheus-stack.yaml` clamps the perf
collector to 128 logical CPUs. node-exporter ignores entries above the real
count, so it is safe to leave — raise it for larger machines.
