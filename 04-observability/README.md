# 04 — DevOps · Observability

Reproducible proof for the competency items marked **Yes** in PeEx
(**DevOps · Observability**). Two layers: a local `docker compose` stack
(fast, no cloud needed — covers the Trainee items) and, additionally, the
**same kind of stack hosted on real EC2** as part of the shared
`../11-network/` infrastructure (covers "infrastructure monitoring" with a
genuinely remote target, not localhost).

| Level  | Competency item                              | Covered by |
|--------|----------------------------------------------|------------|
| Trainee | Extract and summarize log entries           | `scripts/log-summary.sh` + `logs/sample.log` |
| Trainee | Identify observability data types           | `docs/observability-data-types.md` |
| Trainee | Configure a basic trigger for an automated process | `prometheus/alert.rules.yml` + `alertmanager/` + `webhook/sink.py` |
| Junior (KEY) | Configure infrastructure monitoring and logging | local `docker compose` stack below **+** the real-EC2 stack in `../11-network/` |

## Що зробили
- Локальний стек (`docker compose`): **Prometheus** (скрейпить метрики,
  оцінює alert rules), **node-exporter** (метрики хоста), **Loki + Promtail**
  (централізовані логи), **Grafana** (дашборди), **Alertmanager +
  webhook-sink** (спрацьований алерт запускає автоматизований процес —
  webhook фіксує дію). Це лишається основним доказом для трьох Trainee-пунктів
  і не змінювалось — вже відпрацьовано і задокументовано в `proof/`.
- **Додатково** підняли **той самий тип стеку (Prometheus + Grafana) на
  реальній EC2-інстансі** через `../11-network/terraform` — Prometheus там
  скрейпить `node_exporter` **іншої** реальної EC2-інстансі по приватному VPC
  IP, а не `localhost`. Це сильніший доказ для "Junior (KEY) Configure
  infrastructure monitoring" саме тому, що інфраструктура — справжня, а не
  твій ноутбук.
- Новий `scripts/collect-ec2-proof.sh` тягне цей другий доказ окремо
  (`proof/02_ec2_infrastructure_monitoring.txt`), не чіпаючи локальний стек і
  вже наявний `proof/01_log_summary.txt`.

## Команди для демо

### Локальний стек (Trainee-пункти)
```bash
docker compose up -d          # підняти стек локально
# ~30с на прогрів, далі:
./scripts/collect-proof.sh    # -> proof/ (log summary, monitoring, trigger)

# або окремо, без Docker:
./scripts/log-summary.sh                   # витяг + summary логів
less docs/observability-data-types.md      # типи observability-даних
```
Відкрити в браузері: Prometheus `http://localhost:9090`, Grafana
`http://localhost:3000` (admin / peexadmin, дашборд "PeEx Infrastructure
Overview"), Alertmanager `http://localhost:9093`.

Зупинити:
```bash
docker compose down -v
```

### Реальний EC2-стек (Junior KEY, спільно з 05-compute/11-network)
```bash
# 1) підняти інфраструктуру (VPC+SG+2xEC2) — один раз для 04+05+11 разом
cd ../11-network/scripts && ./apply.sh

# 2) зняти саме Observability-доказ з EC2
cd ../../04-observability
./scripts/collect-ec2-proof.sh   # -> proof/02_ec2_infrastructure_monitoring.txt
```

Показати ревьюеру наживо:
```bash
cd ../11-network/terraform
terraform output grafana_url
terraform output prometheus_url
# відкрити Grafana / Prometheus за цими URL, Status -> Targets в Prometheus
```

Прибрати EC2-стек (спільно з Network/Compute):
```bash
cd ../11-network/scripts && ./destroy.sh
```

## Що доводить кожен пункт
- **Логи**: `proof/01_log_summary.txt` — витяг і summary `logs/sample.log`.
- **Типи даних**: `docs/observability-data-types.md`.
- **Тригер / автоматизація**: alert rules завантажені; спрацьований алерт
  доходить до Alertmanager, webhook-sink фіксує дію (локальний стек).
- **Моніторинг інфраструктури**: локально — Prometheus targets `up`,
  `node_load1` і memory з node-exporter; додатково — той самий доказ, але з
  реальної EC2 в `proof/02_ec2_infrastructure_monitoring.txt`.

## Структура
```
04-observability/
  docker-compose.yml, prometheus/, grafana/, loki/, promtail/, alertmanager/, webhook/
  scripts/
    log-summary.sh
    collect-proof.sh          локальний стек -> proof/01_log_summary.txt (+ інше)
    collect-ec2-proof.sh      реальний EC2-стек -> proof/02_ec2_infrastructure_monitoring.txt
  docs/observability-data-types.md
  logs/sample.log
  proof/
```

## Нотатки
- Образи запінені; перший `up` тягне їх з інтернету (потрібен інтернет на
  хості, де запускаєш).
- Конфіги валідовані: `promtool check config`, `promtool check rules`,
  `amtool check-config`.
- Паролі Grafana в обох стеках — демонстраційні значення, зміни їх для
  чогось поза цим завданням.
