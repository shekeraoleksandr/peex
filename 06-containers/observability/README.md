# 06 · Observability for containerized infrastructure (Middle)

Повноцінна observability для **контейнеризованої** інфраструктури у **двох
середовищах**: контейнери на VM-інстансі в AWS (стек з `11-network`) і ~10
сервісів на **Cloud Run** у GCP. Метрики, логи, дашборди, алерти з порогами,
доставка сповіщень і навмисно спровокований інцидент — усе на реальних
ресурсах, які вже існують.

| Вимога NEBO | Чим закрито |
|---|---|
| ≥2 monitoring components | AWS: Prometheus + cAdvisor + node-exporter + blackbox + Loki/Promtail + Alertmanager + Grafana; окремо CloudWatch+SNS. GCP: Cloud Monitoring + Cloud Logging |
| Метрики з усіх контейнерів (CPU/mem/net/disk) | cAdvisor → `prometheus/prometheus.yml` |
| Application-level метрики | blackbox probes: `probe_success`, `probe_duration_seconds` |
| Централізовані логи | Promtail (docker service discovery) → Loki |
| Дашборди | `grafana/provisioning/dashboards/containers.json` + існуючий four-golden-signals у GCP |
| Алерти (CPU, memory, restarts, readiness) | `prometheus/alert.rules.yml` — 10 правил |
| Доставка сповіщень | webhook-sink (автоматизована дія) + CloudWatch→SNS→email |

## Що зробили
- Розгорнули на моніторинг-інстансі з `11-network` **повний стек**: Prometheus,
  **cAdvisor** (метрики по кожному контейнеру), node-exporter, **blackbox**
  (HTTP-проби = readiness/liveness), **Loki + Promtail** (централізовані логи
  всіх контейнерів через docker service discovery), **Alertmanager**,
  webhook-sink і Grafana з провіженим дашбордом.
- Написали **10 alert-правил** з обґрунтованими порогами: CPU >0.8 ядра (2хв),
  память >85% ліміту (3хв), рестарт контейнера, зникнення контейнера, `up==0`,
  память/диск хоста, `probe_success==0`, латентність >2с, плюс демо-правило.
- **Проти false positives**: у правилі памʼяті стоїть guard `> 0` на ліміт
  (без нього контейнери без ліміту дають `+Inf` і алерт горить завжди);
  в Alertmanager — `repeat_interval` 4h і два inhibition-правила (зниклий
  контейнер глушить свої ж CPU/memory алерти, впалий таргет — похідні warning'и).
- **Секрети в логах**: Promtail редактить `password|token|secret|api_key`,
  `Bearer ...` і email-адреси **на етапі ingest**, до запису в Loki.
- **Retention під контроль вартості**: Prometheus 7д/2GB, Loki 7д — це t3.micro
  з одним root-волюмом; алерт `HostDiskFilling` стоїть як підстраховка.
- **Другий, незалежний механізм** — `terraform/`: CloudWatch alarms (CPU +
  `StatusCheckFailed` на обох інстансах) → SNS → **email**. Це закриває дірку,
  яку стек всередині інстансу закрити не може: він не здатен повідомити про
  власну смерть. І без жодного SMTP-пароля на диску.
- **Експозиція мінімальна**: назовні лише Prometheus (9090) і Grafana (3000),
  і лише на твій IP. Alertmanager/cAdvisor/Loki слухають `127.0.0.1` — доступ
  через SSH-тунель, без змін у security group.
- **GCP — тільки читання**: `gcp-export.sh` витягує список Cloud Run сервісів,
  експортує дашборди у версіоновний JSON, показує log-based метрики і живі
  запити до Cloud Logging. Нічого в проєкті не створюється.
- **Спровокували справжній інцидент**: `trigger-alert.sh` запускає CPU-хог або
  вбиває контейнер → правило спрацьовує → Alertmanager → webhook фіксує дію.
  Є що скріншотити, і це не зелений дашборд.

## Команди для демо
```bash
# 1) розгорнути стек на моніторинг-інстанс (IP/ключ беруться з 11-network)
./scripts/deploy.sh

# 2) зібрати доказову базу (компоненти, метрики, логи, правила, overhead)
./scripts/collect-proof.sh        # -> proof/01_observability_proof.txt

# 3) GCP Cloud Run (read-only)
./scripts/gcp-export.sh           # -> proof/02_gcp_cloudrun_observability.txt + gcp-export/*.json

# 4) email-канал через CloudWatch -> SNS
cd terraform
terraform init
terraform apply -var="alert_email=oleksandrshekera@gmail.com"
#    -> підтвердь підписку в листі від AWS, інакше сповіщення не прийдуть

# 5) навмисно запалити алерт
cd ..
./scripts/trigger-alert.sh stress   # CPU-хог   -> proof/03_triggered_alert_stress.txt
./scripts/trigger-alert.sh kill     # вбити контейнер -> ContainerDisappeared/TargetDown
```

Показати ревьюеру наживо:
```bash
MON=$(terraform -chdir=../../11-network/terraform output -raw monitoring_public_ip)

open http://$MON:3000      # Grafana -> дашборд "PeEx — Container Observability"
open http://$MON:9090/alerts   # Prometheus: правила і їх стан

# внутрішні UI — через тунель (портів назовні навмисно не відкривали)
ssh -i ../../11-network/terraform/peex-netcompute-key.pem \
    -L 9093:localhost:9093 -L 8081:localhost:8080 ubuntu@$MON
open http://localhost:9093   # Alertmanager: інциденти, silences, inhibition
open http://localhost:8081   # cAdvisor

# приклади запитів (є і в proof)
# PromQL: CPU по контейнерах
sum by (name) (rate(container_cpu_usage_seconds_total{name!=""}[2m]))
# PromQL: память відносно ліміту
container_memory_usage_bytes{name!=""} / (container_spec_memory_limit_bytes{name!=""} > 0)
# LogQL: помилки в логах усіх контейнерів
{environment="aws-ec2"} |= "error"
# GCP: помилки Cloud Run
gcloud logging read 'resource.type=cloud_run_revision AND severity>=ERROR' --limit 5
```

Прибрати за собою:
```bash
cd terraform && terraform destroy     # алярми + SNS
# сам стек зникне разом з інстансами: ../../11-network/scripts/destroy.sh
```

## Структура
```
observability/
  docker-compose.yml         увесь стек (8 сервісів)
  prometheus/                prometheus.yml + alert.rules.yml (10 правил)
  alertmanager/              маршрутизація, inhibition, receivers
  blackbox/                  HTTP-проби
  loki/ promtail/            централізовані логи + редакція секретів
  grafana/provisioning/      datasources + дашборд containers.json
  webhook/sink.py            автоматизована дія на алерт
  terraform/                 CloudWatch alarms -> SNS -> email
  scripts/                   deploy / collect-proof / gcp-export / trigger-alert
  docs/architecture.md       схема, покриття сигналів, обґрунтування рішень
  docs/runbook.md            по одному розділу на кожен алерт
  proof/                     заповнюється скриптами
  gcp-export/                експортовані дашборди GCP (JSON)
```

## Чесно про межі
- **Kubernetes не покрито.** Контейнери тут живуть на Cloud Run (Container
  Apps) і безпосередньо на VM-інстансі; GKE/EKS/AKS кластера в жодному з
  проєктів немає, тож цей пункт свідомо поза скоупом, а не зімітований
  одноразовим кластером.
- `monitoring overhead < 5%` — перевіряється в `collect-proof.sh` через
  `docker stats`; на t3.micro стек сам по собі помітний, тому цифру треба
  дивитись у звіті, а не приймати на віру.
- Підписку SNS треба підтвердити вручну з листа — доти email не приходить.
