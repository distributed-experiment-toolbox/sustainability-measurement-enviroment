# Runwasi / wasmtime experiment

How to extend the baseline cluster with a second container runtime. Builds
the [runwasi](https://github.com/containerd/runwasi) wasmtime shim, installs
it on the SUT nodes, and registers a Kubernetes `RuntimeClass` for it.

This is the pattern every consuming project follows: install the collection,
keep your own inventory, group_vars and roles, and wrap the baseline
playbooks with `import_playbook`.

## Layout

```
ansible.cfg           roles_path = roles (your roles), inventory = hosts.yml
requirements.yml      the collection
group_vars/all.yml    overrides on top of the collection's role defaults
pre-cluster.yml       import sustian.deploy.pre_cluster, then build + install the shim
post-cluster.yml      import sustian.deploy.post_cluster, then re-apply + RuntimeClass
roles/runwasi_build/  builds the shim on the control-plane
roles/runwasi_shim/   installs it on the SUT nodes, writes containerd config.d
```

## Running

```bash
ansible-galaxy collection install -r requirements.yml
cp hosts.yml.example hosts.yml   # edit node addresses

ansible-playbook -i hosts.yml pre-cluster.yml
# run Kubespray on the control-plane (the pre-cluster playbook prints how)
ansible-playbook -i hosts.yml post-cluster.yml
```

`post-cluster.yml` re-applies the shim on purpose: Kubespray rewrites
`/etc/containerd/config.toml` and drops the `config.d` import.
