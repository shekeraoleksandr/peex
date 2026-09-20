# How to fill this folder

Ansible (offline, needs ansible-core):
```bash
cd ansible
{ ansible-playbook playbook.yml; echo "=== re-run (idempotent) ==="; ansible-playbook playbook.yml; \
  echo "=== config change ==="; ansible-playbook playbook.yml -e app_port=9090; } | tee ../proof/01_ansible_run.txt
cat /tmp/peex-iac/app/app.conf | tee ../proof/02_rendered_config.txt
```

Terraform (on the machine where aws is logged in):
```bash
cd terraform && cp terraform.tfvars.example terraform.tfvars   # set unique bucket_prefix
terraform init
terraform plan  | tee ../proof/tf_plan.txt
terraform apply -auto-approve | tee ../proof/tf_apply.txt
terraform apply -auto-approve -var enable_versioning=false | tee ../proof/tf_change.txt   # config change
terraform destroy -auto-approve
```

| Item | Proof |
|------|-------|
| Execute automated configuration change | 01_ansible_run.txt / tf_change.txt |
| Provision resource from a template | tf_plan.txt + tf_apply.txt / 02_rendered_config.txt |
| Review and record IaC execution results | tf_plan.txt, tf_apply.txt, ansible recap |
| Maintain automated infra configuration | 01_ansible_run.txt (idempotent re-run) |
| Store config files in VCS | 03_vcs.txt |
