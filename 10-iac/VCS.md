# Storing & managing IaC in version control (Junior item)

All infrastructure code here is designed to live in Git.

## What IS committed
- `terraform/*.tf`, `terraform.tfvars.example`
- `ansible/` playbooks, templates, inventory, `ansible.cfg`
- documentation (`README.md`, `VCS.md`)

## What is NOT committed (see `.gitignore`)
- Terraform **state** (`*.tfstate*`) — can contain secrets; store in a remote
  backend (e.g. S3 + DynamoDB lock) instead.
- `.terraform/` provider cache and real `*.tfvars` (only the `.example` is tracked).
- Rendered artifacts under `/tmp/peex-iac/` produced by the Ansible run.

## Workflow (conventions)
- Trunk-based with short-lived feature branches: `feat/iac-<change>`.
- Small, reviewable commits; conventional messages, e.g.
  `feat(tf): enable S3 versioning`, `fix(ansible): correct app_port`.
- Every infra change goes through a PR/MR with `terraform plan` output attached
  (the reviewer sees the diff before apply).
- Tags for releases: `iac-v1.0.0`.

## Proof
`proof/03_vcs.txt` shows a real `git init` + commit history of this kit with
state/secret files correctly ignored.
