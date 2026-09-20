# 05 — DevOps · Compute

Reproducible proof for the competency items marked **Yes** in PeEx
(**DevOps · Compute**). Real AWS EC2, provisioned by **Terraform** — now
shared with Network and Observability as one infrastructure stack
(`../11-network/`), instead of a standalone bash+aws-cli script.

| Level  | Competency item                                    | Covered by |
|--------|----------------------------------------------------|------------|
| Junior (KEY) | Provision virtual machine with predefined types and images | `../11-network/terraform/ec2.tf` (`aws_instance.web`) |
| Trainee (KEY) | Verify virtual machine access                    | `collect-proof.sh` (SSH session) |
| Trainee (KEY) | Perform basic operating system configuration     | `../11-network/terraform/user-data/web.sh` (cloud-init) |
| Trainee (KEY) | Monitor virtual machine resource usage           | `collect-proof.sh` (uptime/memory/disk + node_exporter) |

## Що зробили
- Перевели provisioning EC2 з окремого bash+aws-cli скрипту на **Terraform**
  (`../11-network/terraform`) — той самий `apply` одночасно піднімає VPC,
  firewall і обидві інстанси; тут лишився тільки **свій** зріз доказу.
- **Instance**: `t3.micro` (predefined type), **Ubuntu 24.04** (predefined
  image, резолвиться динамічно через `data.aws_ami`), IMDSv2 обов'язковий.
- **SSH-ключ** генерується самим Terraform (`tls_private_key`) — приватна
  частина ніколи нікуди не йде, тільки публічний ключ реєструється в AWS.
- **Basic OS config** через cloud-init: nginx встановлено, увімкнено,
  активне; демо-сторінка з hostname; окремий systemd-юніт `node_exporter`
  (least-privilege: `NoNewPrivileges`, `ProtectSystem=strict`).
- **Monitor resource usage**: `collect-proof.sh` знімає uptime/load,
  memory, disk і живі метрики `node_exporter` прямо з інстансу по SSH — ті
  самі цифри одночасно видно в Grafana (`../11-network/`).
- Старий standalone-варіант (окремі `provision.sh` / `lib.sh` / `monitor.sh` /
  `os-config.sh` / `verify-access.sh` / `teardown.sh` під власний SG/key-pair)
  переїхав у `legacy/` — робочий, але дублює те, що тепер робить Terraform;
  лишив для довідки.

## Команди для демо
```bash
# 1) підняти інфраструктуру (VPC+SG+2xEC2) — один раз для 05+04+11 разом
cd ../11-network/scripts && ./apply.sh

# 2) зняти саме Compute-доказ
cd ../../05-compute
./collect-proof.sh          # -> proof/00_compute_proof.txt
```

Показати ревьюеру наживо:
```bash
cd ../11-network/terraform
terraform output ssh_web                 # готова команда SSH
$(terraform output -raw ssh_web)         # зайти напряму

# на інстансі:
systemctl status nginx
hostnamectl
curl -s localhost:9100/metrics | head -20   # node_exporter
uptime; free -h; df -h /
```

Прибрати за собою (спільно з Network/Observability):
```bash
cd ../11-network/scripts && ./destroy.sh
```

## Структура
```
05-compute/
  README.md
  collect-proof.sh     тягне Compute-зріз доказів з ../11-network/terraform
  proof/                00_compute_proof.txt (+ HOWTO.md)
  legacy/               попередній standalone aws-cli варіант (для довідки)
```

## Нотатки
- Інфраструктура спільна з `04-observability` і `11-network` — піднімається й
  знищується одним `apply.sh` / `destroy.sh` у `11-network/scripts/`.
- `t3.micro` — free-tier-eligible у більшості акаунтів; все одно прибирай за
  собою через `destroy.sh`.
