# 06 — DevOps · Containers

Повний життєвий цикл образу на **реальному застосунку** — Angular SSR лендінг
`movielinks.ai` з мого пет-проєкту MovieLinks: авторинг Dockerfile → білд →
локальний запуск з port forwarding → образ у реальному registry (GCP Artifact
Registry) → pull звідти й запуск. Жодного placeholder-застосунку: NEBO-вимога
прямо забороняє "hello world" без реальної установки залежностей, тут же
`npm ci` тягне 23 prod- і 15 dev-залежностей і `ng build` збирає SSR-бандл.

| Level | Competency item | Covered by |
|---|---|---|
| Trainee (KEY) | Build and run a basic container image | `scripts/build.sh`, `scripts/run.sh` |
| Trainee (KEY) | Update configuration for a containerized application | `config/app.env` + `scripts/update-config.sh` |
| Junior (KEY) | Create and publish a custom container image | `scripts/registry.sh`, `scripts/pull-and-run.sh` |
| Middle | Apply observability practices to containerized infra | **`observability/`** — Prometheus/cAdvisor/Loki/Alertmanager на AWS EC2 + Cloud Run (див. `observability/README.md`) |

> **MovieLinks — read-only.** Жоден скрипт нічого не пише у репозиторій проєкту.

## Що зробили
- Взяли **справжній Dockerfile** з `movieLinks-landing` (у git, з історією
  комітів — `fcfa1d1 Updated Dockerfile, cloud build. Tested deploy`), а не
  написаний під завдання.
- **Білдимо образ локально** з контексту `git archive HEAD` — тобто рівно з
  того, що закомічено. Це водночас обходить проблему великого контексту
  (див. нижче), тримає репо read-only і прив'язує образ до конкретного
  коміту (образ тегається `movielinks-landing:<short-sha>`).
- **Запускаємо з port forwarding** (`-p 8080:4000`), чекаємо готовності SSR і
  доводимо curl'ом, що сторінка віддається (HTTP 200 + `<title>`).
- **Перевіряємо non-functional вимоги** (`inspect.sh`): образ працює від
  **non-root** (`USER node`, `id` → uid 1000), `EXPOSE 4000`, `CMD`,
  multi-stage (у фінальний образ їдуть лише `dist` + prod-`node_modules` після
  `npm prune --omit=dev`), і окремо перевіряємо, що `.git`, `src`, `public`,
  `.angular` **не потрапили** в образ.
- **Registry**: образи вже лежать у реальному **Artifact Registry**
  (`europe-west1-docker.pkg.dev/movielinks-475222/...`), куди їх пушать власні
  Cloud Build / GitHub Actions пайплайни проєкту. `registry.sh` показує
  репозиторії, список образів з тегами і історію білдів — тобто push
  задокументований реальним пайплайном, а не разовою ручною командою.
- **Pull & run**: `pull-and-run.sh` витягує найсвіжіший образ з registry,
  запускає його локально на сусідньому порту — можна поруч відкрити
  `localhost:8080` (локальний білд) і `localhost:8081` (образ з registry) і
  показати ревьюеру, що функціональність однакова.
- Старий синтетичний `peex-app` переїхав у `legacy/` — він не проходив вимогу
  "no placeholder applications" (stdlib-only, нульова установка залежностей).

### Знахідка: у `movieLinks-landing` немає `.dockerignore`
Робоче дерево важить **~947MB** (`node_modules` 606M, `dist` 128M, `.git` 92M),
і без `.dockerignore` усе це їде в build context, а `COPY . .` запікає його в
builder-шар. Плюс два SVG по **42MB і 40MB** (`public/img/*-landing-img.svg`)
сидять у самому репозиторії. Готовий файл лежить у
`recommendations/dockerignore.suggested` — **не застосований**, бо MovieLinks
чіпати не домовлялись; застосувати можна однією командою (вона ж у шапці файлу).

## Команди для демо
```bash
# усе одним заходом (білд → run → inspect → registry → pull&run)
./scripts/collect-proof.sh

# або покроково:
./scripts/build.sh          # -> proof/01_build.txt
./scripts/run.sh            # -> proof/02_run.txt   (localhost:8080)
./scripts/inspect.sh        # -> proof/03_inspect.txt
./scripts/registry.sh       # -> proof/04_registry.txt
./scripts/pull-and-run.sh   # -> proof/05_pull_and_run.txt (localhost:8081)
./scripts/update-config.sh  # -> proof/06_update_config.txt (зміна PORT у config/app.env)
```

Показати ревьюеру наживо:
```bash
# Dockerfile у git з історією
git -C ../MovieLinks/movieLinks-landing log --oneline -- Dockerfile
cat ../MovieLinks/movieLinks-landing/Dockerfile

# образ запущений і віддає сторінку
docker ps
curl -i http://localhost:8080/
open http://localhost:8080/            # для скріншота

# non-root + що всередині образу
docker inspect -f '{{.Config.User}}' movielinks-landing:peex-local
docker run --rm --entrypoint sh movielinks-landing:peex-local -c 'id; ls /usr/src/app'

# образ у реальному registry
gcloud artifacts docker images list \
  europe-west1-docker.pkg.dev/movielinks-475222/movie-links-lending/lending-prod \
  --include-tags --limit 10

# порівняти локальний білд і образ з registry поруч
open http://localhost:8080/   # локальний
open http://localhost:8081/   # з Artifact Registry
```

Прибрати за собою:
```bash
docker rm -f peex_movielinks_landing peex_movielinks_landing_registry
docker image prune -f
```

## Структура
```
06-containers/
  lib.sh                    спільна конфігурація (шляхи, координати registry)
  scripts/
    build.sh                git archive -> docker build (локальний білд)
    run.sh                  docker run -p 8080:4000 + curl + logs
    inspect.sh              non-root, шари, розмір, що реально в образі
    registry.sh             що вже лежить в Artifact Registry + історія білдів
    pull-and-run.sh         docker pull з GAR + запуск на 8081
    collect-proof.sh        усе підряд -> proof/
    update-config.sh        зміна PORT у config/app.env -> recreate -> перевірка
  config/app.env            конфіг застосунку (--env-file, не вшитий в образ)
  observability/            окремий під-кіт: Prometheus/cAdvisor/Loki/Alertmanager
  recommendations/
    dockerignore.suggested  пропозиція для MovieLinks (НЕ застосована)
  proof/                    01_build .. 06_update_config (+ HOWTO.md)
  legacy/                   попередній синтетичний peex-app
```

## Нотатки
- Перший білд довгий (кілька хвилин): `npm ci` + `ng build` SSR. Далі кешується.
- Потрібні: Docker Desktop (запущений) і залогінений `gcloud` для кроків з
  registry. Без gcloud перші три кроки (build/run/inspect) все одно працюють.
- Шлях до MovieLinks можна перевизначити: `MOVIELINKS=/path/to/MovieLinks ./scripts/build.sh`.
- Порти можна змінити: `HOST_PORT=9000 ./scripts/run.sh`.
