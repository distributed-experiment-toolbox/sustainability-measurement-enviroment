# Minimal baseline

The smallest thing that deploys the baseline cluster: an inventory, an
`ansible.cfg`, and group_vars turning on the opinions a measurement setup
usually wants.

```bash
ansible-galaxy collection install -r requirements.yml
cp hosts.yml.example hosts.yml   # edit node addresses

ansible-playbook -i hosts.yml sustian.deploy.pre_cluster
# run Kubespray on the control-plane (the playbook prints how)
ansible-playbook -i hosts.yml sustian.deploy.post_cluster
```
