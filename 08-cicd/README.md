# 08 — DevOps · CI/CD Engineering

Два шари доказів: **локальний пайплайн**, який можна прогнати будь-де за 30
секунд (lint → test → build → deploy → verify), і **реальні продакшн-пайплайни
MovieLinks** — 13 Cloud Build конфігів, що збирають образи, пушать їх у Artifact
Registry з тегом по SHA і деплоять у Cloud Run, плюс GitHub Actions з OIDC і
canary/promote/rollback.

| Level | Competency item | Covered by |
|---|---|---|
| Trainee (KEY) | Update configuration files | `config/app.config.json` + `pipeline/update-config.sh`; реально — substitutions у `cloudbuild.yaml` |
| Trainee (KEY) | Deploy a pre-configured application | `app/server.py` + стадія `deploy`; реально — `gcloud run deploy` у Cloud Build |
| Trainee (KEY) | Verify CI/CD pipeline execution results | `pipeline/verify-results.sh`; реально — `gcloud builds list/describe` |

## Що зробили
- **Локальний пайплайн** (`pipeline/run-local.sh`) проганяє ті самі стадії, що
  й CI: lint → test → build → deploy → verify. Кладе у `build/`: звіт тестів,
  артефакт `peex-cicd-demo-<version>.tar.gz`, задеплоєний застосунок з
  health-check на :8091 і підсумковий `pipeline-result.txt`.
- **Дві справжні CI-конфігурації** на ті самі стадії: `.github/workflows/ci.yml`
  (GitHub Actions) і `.gitlab-ci.yml` (GitLab CI) — сторінка запуску в будь-якій
  з них і є доказом "verify pipeline execution results".
- **Оновлення конфігурації** окремою дією: `update-config.sh 1.1.0 production`
  змінює версію/оточення/фіче-флаг, після чого пайплайн передеплоює застосунок
  уже з новим конфігом — before/after видно в `proof/02_update_config.txt`.
- Усе прогнано наживо — три файли в `proof/` це реальні виводи, не приклади.

### Реальні пайплайни (MovieLinks) — той самий скіл, але в проді
У `../MovieLinks/movielinksParser/infra/cloudbuild/` лежать **13** конфігів
(tastefilter, quickpickwizard, trailers, admin, importhub, …). Кожен:
збирає образ → пушить у Artifact Registry **двома тегами** (`:latest` і
`:$SHORT_SHA`) → деплоїть ревізію в Cloud Run саме по SHA-тегу, а не по
`latest`. Тег по коміту — це те, що робить деплой відтворюваним і дозволяє
відкотитись на конкретну ревізію.

`../MovieLinks/movieLinks-landing/.github/workflows/cloud-run-seo-deploy.yml` —
окремий рівень: **OIDC** (`id-token: write`, без збережених ключів сервісного
акаунта), і три режими роботи — `deploy_canary` з відсотком трафіку, `promote`
і `rollback` з обчисленням попередньої стабільної ревізії.

## Команди для демо
```bash
# локальний пайплайн цілком
./pipeline/run-local.sh              # -> proof/01_pipeline_run.txt

# оновити конфіг і передеплоїти
./pipeline/update-config.sh 1.1.0 production
./pipeline/run-local.sh              # -> proof/02_update_config.txt

# перевірити результати окремо
./pipeline/verify-results.sh         # -> proof/03_verify_results.txt
```

Показати ревьюеру наживо (реальні пайплайни):
```bash
# історія справжніх білдів
gcloud builds list --project movielinks-475222 --limit 10

# що саме робить один пайплайн: build -> push (2 теги) -> deploy
cat ../MovieLinks/movielinksParser/infra/cloudbuild/tastefilter/cloudbuild.yaml

# образи з тегами по комітах у registry
gcloud artifacts docker images list \
  europe-west1-docker.pkg.dev/movielinks-475222/movielinks-functions \
  --include-tags --limit 20

# ревізії Cloud Run і розподіл трафіку (canary/promote/rollback)
gcloud run services describe tastefilter --region europe-west1 \
  --project movielinks-475222 --format='value(status.traffic)'

# workflow з OIDC і трьома режимами
cat ../MovieLinks/movieLinks-landing/.github/workflows/cloud-run-seo-deploy.yml
```

## Структура
```
08-cicd/
  app/            calc.py (логіка під тестами), server.py (що деплоїться)
  tests/          test_calc.py
  config/         app.config.json — конфіг, який оновлює пайплайн
  pipeline/       run-local.sh, update-config.sh, verify-results.sh
  .github/workflows/ci.yml     GitHub Actions
  .gitlab-ci.yml               GitLab CI
  proof/          01_pipeline_run, 02_update_config, 03_verify_results
```

## Чесно про межі
- Локальний застосунок навмисно крихітний — він тут як **предмет** пайплайну, а
  не як досягнення. Вага доказу в стадіях і в тому, що вони реально проходять.
- Три пункти компетенції — усі Trainee-рівня. Пайплайни MovieLinks тягнуть на
  вищий рівень (SHA-теги, canary, rollback, OIDC), але вони писались під проєкт,
  а не під цю задачу, тож тут вони як **підтвердження в продакшні**, а не як
  окремо оформлений кейс. Якщо треба саме оформлений — варто зробити окремий
  прохід по них.
