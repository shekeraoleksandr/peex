# 11 — DevOps · Network

Один Terraform-стек в AWS, що покриває **пʼять** мережевих компетенцій: VPC з
публічною і приватною підмережами, security groups + **Network ACLs**, NAT-інстанс,
**VPC peering з IPsec-тунелем** між двома приватними мережами, **VPC Flow Logs**
і матриця звʼязності, яка доводить і дозволений, і заблокований трафік.

| Competency item | Covered by |
|---|---|
| Create a basic network segment **(KEY)** | `terraform/vpc.tf` — VPC + 3 підмережі; інстанси реально підключені |
| Apply a pre-defined firewall rule | `terraform/security-groups.tf` + негативні тести в матриці |
| Apply pre-defined network security rule | SG прив'язані до ENI, NACL — до підмереж; scope і напрям у `02_connectivity_matrix.txt` |
| Configure and manage network traffic controls | SG + **NACL** + route tables + egress-allowlist + Flow Logs |
| Manage and maintain virtual network infrastructure **(KEY)** | public/private підмережі, IGW, NAT, route tables, теги, тести між підмережами |
| Configure secure connectivity across private/external networks | `terraform/peering.tf` — peering + **IPsec (IKEv2, AES-256)** |

## Що зробили
- **Мережевий сегмент**: VPC `10.42.0.0/16`, три підмережі (`public-a`,
  `public-b` про запас, `private-a`), IGW, окремі таблиці маршрутизації.
  План адресації з навмисними проміжками — нові тіри додаються без
  переадресації (деталі в `docs/network-architecture.md`).
- **Приватна підмережа — справді приватна**: у її таблиці маршрутизації **немає**
  маршруту на IGW, тому жодні правила SG не зроблять хост доступним ззовні.
  Вихід назовні — через **NAT-інстанс** (`source_dest_check = false`,
  `ip_forward`, `iptables MASQUERADE`) замість NAT Gateway за $32/міс.
- **Два рівні фільтрації**: security groups (stateful, на інстанс) + **Network
  ACLs** (stateless, на підмережу). У кожному NACL є явне правило на
  ephemeral-порти 1024–65535 для зворотного трафіку — без нього будь-який
  вихідний запит просто зависає; це найтиповіша помилка з NACL.
- **Egress більше не `0.0.0.0/0`**: назовні дозволені тільки 443, 80 і DNS 53
  (репозиторії пакетів, реєстри, резолвінг), решта — заборонена. Усередині VPC
  і в бік peer-мережі трафік вільний.
- **Кожне правило має обґрунтування** прямо в `description` — воно видно у
  `describe-security-groups`, тобто подорожує разом із правилом, а не лежить
  окремо в документі.
- **Secure connectivity**: другий VPC `10.43.0.0/16` + **VPC peering** (трафік
  не виходить в інтернет) і поверх нього **IPsec transport mode** (strongSwan,
  IKEv2, AES-256/SHA-256, PSK генерується Terraform'ом на apply). Peering дає
  ізоляцію, IPsec — власне шифрування; разом вони закривають вимогу
  "encrypted in transit" чесно, а не на словах.
- **Traffic monitoring**: VPC Flow Logs (`ACCEPT` + `REJECT`) у CloudWatch з
  retention 1 день. Саме `REJECT`-записи роблять заблоковане з'єднання
  доказовим постфактум.
- **S3 gateway endpoint** — трафік до S3 не виходить в інтернет і не тягнеться
  через NAT (gateway-ендпоїнти безкоштовні, на відміну від interface).
- **Матриця звʼязності** (`test-connectivity.sh`): кожна перевірка заявляє
  очікуваний результат, тож провалений негативний тест видно як `[LEAK!]`, а не
  тихо зараховується як успіх. Раніше в цій секції був баг саме такого типу —
  перевірка firewall обгорталась у `timeout`, якого на macOS немає, і
  "command not found" зараховувався як "заблоковано".
- **Зміна правил з валідацією** (`change-and-validate.sh`): before → зміна →
  after → відкат → `terraform plan -detailed-exitcode` як доказ, що дрейфу не
  лишилось.

## Відповідність вимогам NEBO

**Configure and manage network traffic controls**

| Вимога | Де доведено |
|---|---|
| SG контролюють трафік на рівні інстансу | `terraform/security-groups.tf`; `02_connectivity_matrix.txt` §1, §7 |
| **NACL фільтрують на рівні підмережі** | `terraform/nacl.tf`; матриця §6 |
| Inbound тільки потрібні порти/протоколи | §1 — оголошені порти працюють, `:8080` і `:9100` ззовні — ні |
| Outbound обмежує зайвий egress | §7 — egress-allowlist 443/80/53, плюс живий тест забороненого порту |
| Обмеження за IP/CIDR | усе внутрішнє з інтернету — лише з `allowed_cidr` (твій /32) |
| Дозволений трафік проходить | §1, §2, §3, §4 — `[OK]` |
| Заборонений трафік блокується | §1, §2 — `[BLOCKED]` |
| Моніторинг/логування трафіку | §8 — VPC Flow Logs + вибірка `REJECT` |
| Зміни правил протестовані й валідовані | `03_rule_change_validation.txt` |
| Least privilege, без надто широких правил | немає жодного inbound `0.0.0.0/0` на всі протоколи; egress — allowlist |
| Кожне правило задокументоване | `description` у кожному правилі + таблиця в `docs/network-architecture.md` |
| Зміни відстежувані | усе в Terraform; drift-перевірка в `03_...txt` |

**Manage and maintain virtual network infrastructure**

| Вимога | Де доведено |
|---|---|
| VPC з чітким CIDR | `10.42.0.0/16` — матриця, шапка |
| ≥2 підмережі, публічна і приватна | `public-a`, `public-b`, `private-a` |
| Internet Gateway | `vpc.tf`; маршрут `0.0.0.0/0 → IGW` у public-rt |
| Route tables: інтернет + внутрішня маршрутизація | §3 — таблиці; §2 — трафік між підмережами |
| NAT для приватної підмережі | §3 — egress-IP приватного хоста збігається з IP NAT-інстансу |
| Теги на всіх ресурсах | `Name`/`Tier`/`Project` на VPC, підмережах, RT, NACL, SG, інстансах |
| Тести звʼязності між підмережами і ресурсами | §2, §4 |
| План адресації задокументований, без перетинів | `docs/network-architecture.md` |
| Діаграма топології | `docs/network-architecture.md` |
| Відтворюваність через IaC | увесь стек — Terraform |

**Configure secure connectivity across private and external networks**

| Вимога | Де доведено |
|---|---|
| Приватне зʼєднання між двома мережами | VPC peering, §4 |
| Маршрутизація в обидва боки | §4 — маршрути з обох сторін, ping в обидва напрямки |
| Трафік зашифрований in transit | §5 — `ipsec statusall` (AES-256/SHA-256) + `tcpdump` показує ESP |
| Тести звʼязності (ping/SSH) | §4, §2 |
| Моніторинг стану зʼєднання | §8 Flow Logs; `dpdaction=restart` у IPsec |
| Symmetric routing перевірено | §4 — обидва напрямки окремо |
| SG оновлені під приватне зʼєднання | `peering.tf` — UDP 500/4500 + ESP лише з peer CIDR |
| Без перетину адресних просторів | `10.42.0.0/16` vs `10.43.0.0/16` |

## Команди для демо
```bash
# 0) підняти все (VPC, підмережі, NAT, NACL, peering, IPsec, flow logs)
cd scripts
./apply.sh

# 1) матриця звʼязності: що проходить і що блокується
./test-connectivity.sh        # -> proof/02_connectivity_matrix.txt

# 2) зміна правила з before/after і відкатом
./change-and-validate.sh      # -> proof/03_rule_change_validation.txt
```

Показати ревьюеру наживо:
```bash
cd terraform && terraform output

# приватний хост не має публічної адреси
aws ec2 describe-instances --filters "Name=tag:Tier,Values=private" \
  --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,PublicIpAddress]' --output text

# NAT: 0.0.0.0/0 приватної підмережі дивиться в ENI, а не в IGW
aws ec2 describe-route-tables --filters "Name=tag:Tier,Values=private" \
  --query 'RouteTables[].Routes[]' --output table

# firewall працює: той самий порт, різне джерело — різний результат
curl -m 5 http://$(terraform output -raw web_public_ip):9100/metrics     # таймаут
ssh ... ubuntu@<monitoring> "curl -s http://10.42.1.10:9100/metrics | head -3"   # працює

# шифрування наживо
ssh -J ubuntu@<web> ubuntu@10.42.10.10 'sudo ipsec statusall | head -20'

# заблокований трафік у Flow Logs
aws logs filter-log-events --log-group-name /aws/vpc/peex-netcompute-flow-logs \
  --filter-pattern REJECT --max-items 10
```

Прибрати за собою (5 інстансів t3.micro — за годину демо це копійки, за місяць ні):
```bash
cd scripts && ./destroy.sh
```

## Структура
```
11-network/
  terraform/
    vpc.tf              VPC, 3 підмережі, RT, S3 endpoint, план адресації
    nacl.tf             stateless фільтрація на рівні підмереж
    nat.tf              NAT-інстанс (source_dest_check=false)
    security-groups.tf  stateful правила з обґрунтуванням у description
    peering.tf          другий VPC, peering, IPsec-ендпоїнт
    flow-logs.tf        VPC Flow Logs -> CloudWatch (+ IAM роль)
    ec2.tf              web, monitoring, private хости
    user-data/          nat.sh, ipsec.sh.tpl, web.sh, monitoring.sh.tpl
  scripts/
    apply.sh · test-connectivity.sh · change-and-validate.sh · destroy.sh
  docs/network-architecture.md   діаграма, план IP, маршрути, обґрунтування
  proof/
```

## Чесно про межі
- **Peering, а не VPN gateway.** Site-to-Site VPN коштував би ~$36/міс за ту
  саму демонстрацію. Peering тримає трафік на бекбоні AWS, а IPsec зверху дає
  шифрування, яке дав би VPN.
- **PSK, а не сертифікати.** Ключ генерується на `apply` і лежить у стейті та
  в user-data. Для демо прийнятно; для проду — сертифікати або Secrets Manager.
- **NAT-інстанс — single point of failure**, без автофейловера. Продакшн-дизайн
  мав би керований NAT Gateway у кожній AZ.
- **`public-b` порожня.** Вона є, щоб показати, що дизайн масштабується без
  переадресації, але справжній HA потребував би другого NAT і інстансів у двох AZ.
- **Скріншоти** (їх просять і в "traffic controls", і в "virtual network
  infrastructure"): VPC → Your VPCs (CIDR), Subnets (три підмережі з Tier-тегами),
  Route Tables (приватна — на NAT ENI), Network ACLs, Security Groups з описами,
  Peering Connections, CloudWatch → log group з `REJECT`.
