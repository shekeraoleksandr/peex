# 10 — DevOps · Infrastructure as Code

Два інструменти і три рівні "справжності": **Ansible** (конфіг-менеджмент, який
доводиться офлайн), локальний **Terraform**-приклад, і — найвагоміше — реальні
Terraform-стеки, які вже керують живою інфраструктурою: `../11-network/`
(VPC + SG + 2×EC2 в AWS) і MovieLinks (~10 Cloud Run сервісів у GCP з віддаленим
стейтом і Secret Manager).

| Level | Competency item | Covered by |
|---|---|---|
| Trainee (KEY) | Execute automated configuration change | `ansible/playbook.yml -e app_port=...`; реально — `terraform apply` у `../11-network/` |
| Trainee (KEY) | Provision resource from a template | `terraform/` (S3 з параметрів) + Jinja2-шаблон Ansible; реально — модуль `cloudrun` у MovieLinks |
| Trainee (KEY) | Review and record IaC execution results | збережені recap Ansible і `plan`/`apply` Terraform |
| Junior | Maintain and support automated infra configuration | ідемпотентний плейбук; живі стеки, які ми справді супроводжували |
| Junior | Store and manage config files in VCS | `.gitignore` + `VCS.md` (state і секрети поза Git) |

## Що зробили
- **Ansible**: плейбук рендерить `app.conf` з Jinja2-шаблону (provision from
  template) і декларативно тримає hosts-запис. Другий запуск — `ok`, а не
  `changed`: ідемпотентність доведена, а не задекларована. Зміна конфігурації
  виконується як `-e app_port=9090`, є `--check --diff` для сухого прогону.
- **Terraform (локальний приклад)**: приватний зашифрований S3-бакет з
  версіонуванням, зібраний з змінних. Перемикання `enable_versioning` і
  повторний `apply` — це і є "automated configuration change", а вивід
  `plan`/`apply` — записаний результат виконання.
- **VCS-гігієна**: `.gitignore` тримає **стейт** і справжні `*.tfvars` поза
  Git (трекається лише `*.tfvars.example`); `proof/03_vcs.txt` — реальна
  git-історія з підтвердженням, що ігнорується саме те, що треба.

### Реальні IaC-стеки, якими ми справді керували
Локальний приклад вище — навчальний. Ось що стоїть за цією компетенцією
насправді:

**`../11-network/terraform/` (AWS, наш власний)** — VPC, підмережа, IGW,
маршрутизація, дві security groups, два EC2 з cloud-init, SSH-ключ через
`tls_private_key`. Саме тут ми на практиці зловили пастку, яку варто вміти
пояснити: зміна `user_data` за замовчуванням оновлює атрибут **in-place**, і
cloud-init не перезапускається — виправлений boot-скрипт лежить у стейті й
нічого не робить. Лікується `user_data_replace_on_change = true`.

**`../06-containers/observability/terraform/`** — CloudWatch alarms + SNS, які
читають стейт `11-network` через `terraform_remote_state` (backend `local`) і
**не володіють** його ресурсами. Розділення стейтів замість одного великого —
свідоме рішення.

**MovieLinks (GCP, продакшн)** — `movielinksParser/infra/terraform/`:
- **віддалений стейт** у GCS (`backend "gcs"`, bucket
  `movielinks-terraform-state-backend`, prefix `cloudrun/state`) — не локальний
  файл, тобто придатний для роботи не з одного ноутбука;
- **власний модуль** `modules/cloudrun/` замість копіпасти на кожен сервіс;
- `for_each` по мапах `public_services` / `private_services` — ~10 сервісів
  описані даними, а не десятьма блоками ресурсів;
- **Secret Manager** для секретів і `team_member_emails` для приватних сервісів
  — доступ як код;
- `terraform.tfvars` у `.gitignore` (у самому файлі є про це коментар).

## Команди для демо
```bash
# --- Ansible: зміна конфігурації + ідемпотентність ---
cd ansible
ansible-playbook playbook.yml                      # перший раз: changed
ansible-playbook playbook.yml                      # другий раз: ok (ідемпотентно)
ansible-playbook playbook.yml -e app_port=9090     # автоматизована зміна конфігу
ansible-playbook playbook.yml --check --diff       # сухий прогін з діффом
cat /tmp/peex-iac/app/app.conf                     # результат з шаблону

# --- Terraform (локальний приклад) ---
cd ../terraform
cp terraform.tfvars.example terraform.tfvars       # унікальний bucket_prefix
terraform init
terraform plan | tee ../proof/tf_plan.txt          # записати результат
terraform apply -auto-approve
terraform apply -auto-approve -var enable_versioning=false   # зміна конфігу
terraform destroy -auto-approve                    # прибрати
```

Показати ревьюеру наживо (реальні стеки):
```bash
# наш AWS-стек: що ним описано і що зараз у стейті
terraform -chdir=../11-network/terraform show | head -40
terraform -chdir=../11-network/terraform state list
grep -n "user_data_replace_on_change" ../11-network/terraform/ec2.tf

# розділені стейти: alarms читають мережевий стейт, але не володіють ним
grep -n -A6 "terraform_remote_state" ../06-containers/observability/terraform/main.tf

# MovieLinks: віддалений бекенд, модуль, for_each по сервісах
cat ../MovieLinks/movielinksParser/infra/terraform/backend.tf
sed -n '1,40p' ../MovieLinks/movielinksParser/infra/terraform/modules/cloudrun/main.tf
grep -n "for_each\|public_services\|private_services" \
  ../MovieLinks/movielinksParser/infra/terraform/cloudrun-services.tf

# секрети і стейт не в Git
cat VCS.md
git -C ../MovieLinks/movielinksParser check-ignore -v infra/terraform/terraform.tfvars
```

## Структура
```
10-iac/
  ansible/     playbook.yml, templates/app.conf.j2, inventory.ini, ansible.cfg
  terraform/   main.tf, variables.tf, outputs.tf, terraform.tfvars.example
  VCS.md       що трекаємо, що ігноруємо і чому
  proof/       01_ansible_run, 02_rendered_config, 03_vcs (+ tf_plan/tf_apply)
```

## Чесно про межі
- Ansible і VCS-докази згенеровані наживо; Terraform-приклад потребує AWS-креденшелів,
  тож його запускаєш ти — саме тому `tf_plan.txt` / `tf_apply.txt` у `proof/`
  зʼявляються після твого прогону.
- Локальний `terraform/` тут дублює те, що краще показано в `../11-network/`.
  Якщо скорочувати портфоліо — сильніший доказ саме там, а цей лишається як
  мінімальний приклад "provision from template".
- MovieLinks-стек **не чіпаємо** — він читається для демонстрації, жодна
  команда вище нічого там не змінює.
