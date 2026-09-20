# 09 — DevOps · Automation & Scripting

Чисте скриптування, яке доводиться офлайн: базовий скрипт і його свідома
модифікація, два скрипти під рутинні DevOps-задачі, зламаний скрипт з
регресійним тестом на фікс, і підготовлене IDE-оточення. Усі докази в `proof/`
згенеровані реальним запуском.

| Level | Competency item | Covered by |
|---|---|---|
| Trainee (KEY) | Write basic automation script | `scripts/sysreport.sh` |
| Trainee (KEY) | Modify existing automation script | `modify/MODIFICATION.md` (v1→v2) |
| Trainee (KEY) | Prepare IDE for basic development | `ide/` + `setup-dev-env.sh` |
| Junior | Write scripts to automate routine DevOps tasks | `scripts/backup.sh`, `scripts/healthcheck.sh` |
| Junior | Maintain and fix automation scripts | `fix/` (баг → фікс → регресійний тест) |

### Покриття критеріїв (Write + Maintain)

| Критерій | Де |
|---|---|
| Скрипт автоматизує визначену рутинну задачу | `sysreport.sh` (health), `backup.sh` (файли+ретенція), `healthcheck.sh` (ендпоінти), `fix/cleanup.sh` (логи) |
| Змінні входи / параметри | прапорці у всіх чотирьох; `endpoints.sample.txt` як вхідні дані |
| Два різні сценарії входу | `proof/02_routine_tasks.txt` — dry-run vs реальний прогін, живий ендпоінт vs неіснуючий домен |
| Передбачувані коди виходу | `sysreport`: 0/2/3 (задокументовано у `--help`); `healthcheck`: 1 якщо хоч один хост впав |
| `--help` | всі чотири скрипти |
| Обробка помилок | `die`/`warn` з `lib/common.sh`, перевірка каталогу `--out` **до** збору даних |
| Оригінал для порівняння + diff | `modify/sysreport.v1.sh` → `diff -u modify/sysreport.v1.sh scripts/sysreport.sh` |
| Cross-platform (Linux + macOS) | платформний шар у `sysreport.sh`; `FORCE_OS=Darwin` прогонить другу гілку |
| Документація змін | `modify/MODIFICATION.md` (v1 → v2 → v3), `fix/BUGFIX.md` |
| **Committed to version control** | розділ «Version control» нижче |

## Що зробили
- **Базовий скрипт** `sysreport.sh` — системний звіт у людському вигляді, і його
  **модифікація** до `--json` / `--out` для машинного споживання. Що саме
  змінилось і навіщо — у `modify/MODIFICATION.md`, тобто модифікація
  задокументована, а не просто присутня.
- **Рутинні задачі**: `backup.sh` з `--dry-run` і **retention** (старі бекапи
  підчищаються, і спершу можна подивитись, що саме видалиться) та
  `healthcheck.sh` по списку ендпоінтів.
- **Фікс зламаного скрипта**: `fix/broken-cleanup.sh` має реальний баг,
  `fix/cleanup.sh` — виправлену версію, а `fix/test-cleanup.sh` спершу
  **відтворює баг**, потім доводить, що фікс працює. Опис у `fix/BUGFIX.md`.
- **Єдиний стиль**: усі скрипти на `set -euo pipefail`, з `--help`, валідацією
  аргументів і спільним `lib/common.sh` для логів і помилок.
- **IDE**: `.editorconfig`, VS Code `settings.json` + рекомендовані розширення
  (shellcheck, shell-format, python, yaml), `.pre-commit-config.yaml`
  (whitespace/json/yaml + shellcheck), і `setup-dev-env.sh`, який перевіряє
  тулчейн і піднімає venv.

### Найсильніший доказ "maintain and fix" — цей же репозиторій
Поки збирали портфоліо, у власних скриптах знайшлись і полагодились **реальні**
баги — не навчальні. Кожен варто вміти пояснити, бо це типові пастки bash:

| Де | Баг | Чому ламалось |
|---|---|---|
| `03-storages/teardown.sh` | `--query` зліплював два масиви через `+` | JMESPath не має конкатенації масивів; виклик падав, а `set -e` тихо вбивав увесь скрипт — бакети лишались живими |
| `03-storages/test-access.sh` | `--policy-input-list file://...` | aws-cli ненадійно резолвить `file://` для list-параметрів → `Policy input list item 1 has invalid content` |
| `02-app-administration/collect-proof.sh` | скрипт завершувався кодом 1 | останній рядок — ланцюг `[ ... ] && [ ... ] && cp`; коли умова хибна, весь ланцюг дає 1, і викликаючий `remote.sh` під `set -e` обривався до кроку pull |
| `11-network/scripts/collect-proof.sh` | `timeout` у перевірці firewall | на macOS немає GNU `timeout` → "command not found" → ненульовий код → гілка `\|\| echo "blocked"` друкувала успіх, **нічого не перевіривши** |
| `11-network/terraform/ec2.tf` | зміна `user_data` не переставляла інстанс | провайдер оновлює атрибут in-place, cloud-init не перезапускається; треба `user_data_replace_on_change = true` |
| `06-containers/scripts/*.sh` | `curl ... \| head -25` | `head` закриває пайп → curl отримує SIGPIPE і виходить з кодом 23 (`Failure writing output to destination, passed 16312 returned 0`); під `pipefail` це читалось як "запит не пройшов" — **хибний негатив** на успішній відповіді, а без `\|\| true` ще й обривало скрипт під `set -e`. Фікс: `http_show()` у `lib.sh` — спершу зберігаємо відповідь у змінну, потім показуємо через here-string, вердикт по HTTP-статусу, а не по коду виходу |
| `07-security/access-review/access-review.sh` | читав `/etc/passwd` і `/etc/shadow` напряму | на macOS справжні акаунти живуть в Open Directory, а не в `/etc/passwd`; `getent` і `/etc/shadow` там відсутні — ревʼю доступів **пропустило всіх людей на машині** і виглядало чистим, ще й друкувало коментарі з шапки `/etc/passwd` як акаунти (у них немає `:`, тому awk бачив порожній shell). Фікс: платформний шар з реалізацією під Linux і Darwin + явне повідомлення там, де перевірка неможлива |

Спільний знаменник у більшості з них — **ненульовий код виходу в поєднанні з
`set -e` або `||`**: або тихо вбиває скрипт, або перетворює провалену перевірку
на "успіх". Це і є та сама компетенція "maintain and fix", тільки на живому коді.

## Команди для демо
```bash
# 0) все підряд, із записом у proof/ (нічого, крім bash/curl, не потрібно)
./scripts/sysreport.sh            | tee proof/01_sysreport.txt
{ ./scripts/backup.sh ./scripts /tmp/peexbk --retention 2 --dry-run
  ./scripts/backup.sh ./scripts /tmp/peexbk --retention 2
  ./scripts/healthcheck.sh; }     2>&1 | tee proof/02_routine_tasks.txt
./fix/test-cleanup.sh             | tee proof/03_fix_test.txt

# 1) базовий скрипт і його модифікація
./scripts/sysreport.sh
./scripts/sysreport.sh --json
./scripts/sysreport.sh --json --out /tmp/r.json && cat /tmp/r.json
./scripts/sysreport.sh --help

# 1a) v3: обидві платформні гілки з однієї машини
./scripts/sysreport.sh                       # твій справжній OS (Darwin)
FORCE_OS=Linux  ./scripts/sysreport.sh       # гілка для Linux
FORCE_OS=Plan9  ./scripts/sysreport.sh       # чесні "n/a (unsupported on Plan9)"

# 1b) v3: контракт кодів виходу (для пайплайнів)
./scripts/sysreport.sh --bogus;       echo "exit=$?"   # 2 — некоректний виклик
./scripts/sysreport.sh --out /nope/x; echo "exit=$?"   # 3 — не можу записати
./scripts/sysreport.sh --json | python3 -m json.tool >/dev/null; echo "JSON ok=$?"

# 1c) v1 -> v3: той самий diff, що йде в артефакти "Maintain and fix"
diff -u modify/sysreport.v1.sh scripts/sysreport.sh | head -40

# 2) рутинні задачі
./scripts/backup.sh ./scripts /tmp/backups --retention 3 --dry-run   # спершу подивитись
./scripts/backup.sh ./scripts /tmp/backups --retention 3
./scripts/healthcheck.sh                                            # дефолтний список
./scripts/healthcheck.sh --file scripts/endpoints.sample.txt --timeout 3
echo "exit=$?"   # 1, бо в списку навмисно є неіснуючий домен

# 3) баг → фікс → регресійний тест
./fix/test-cleanup.sh
cat fix/BUGFIX.md

# 4) IDE
./ide/setup-dev-env.sh          # --install щоб доставити pip-тули
```

Показати ревьюеру наживо:
```bash
# стиль і захист від помилок в усіх скриптах
head -20 lib/common.sh
grep -l 'set -euo pipefail' scripts/*.sh fix/*.sh

# статичний аналіз (той самий, що в pre-commit)
shellcheck scripts/*.sh fix/*.sh lib/common.sh

# реальні фікси з таблиці вище
git -C .. log --oneline -- 03-storages/teardown.sh   # якщо peex під git
grep -n "JMESPath" ../03-storages/teardown.sh
grep -n "macOS has no GNU" ../11-network/scripts/collect-proof.sh
```

## Структура
```
09-automation-scripting/
  lib/common.sh        спільні логи/помилки
  scripts/             sysreport.sh, backup.sh, healthcheck.sh,
                       endpoints.sample.txt
  modify/              sysreport.v1.sh (оригінал) + MODIFICATION.md (v1→v2→v3)
  fix/                 broken-cleanup.sh, cleanup.sh, test-cleanup.sh, BUGFIX.md
  ide/                 .editorconfig, .vscode/, .pre-commit-config.yaml, setup-dev-env.sh
  proof/               01_sysreport, 02_routine_tasks, 03_fix_test, 04_ide_setup
```

## Version control
Обидва критерії ("Write" і "Maintain") прямо вимагають **commit у систему
контролю версій з описовими повідомленнями**, а "Maintain" ще й хоче `git diff`
як артефакт. Мінімум, щоб це закрити:

```bash
cd ~/Desktop/peex
git init && git branch -M main
printf '.DS_Store\n*.pem\n*_key\n.known_hosts*\nide/.venv/\n__pycache__/\n' > .gitignore
git add . && git commit -m "PeEx: competency kits with executed proof"
# далі — окремий комміт на v2 -> v3, щоб у «Maintain» був справжній diff:
git commit -am "sysreport: add per-OS collectors so macOS stops silently reporting blanks"
```

> **Перед першим `git add` перевір `.gitignore`.** У дереві лежать приватні
> ключі: `11-network/terraform/*.pem`, `05-compute/.peexops_key`,
> `terraform.tfstate` (містить відкритим текстом ключ з `tls_private_key`).
> Нічого з цього не має потрапити в репозиторій — особливо якщо він піде на
> GitHub.

## Чесно про межі
- `sysreport.sh` підтримує Linux і macOS явно; на інших ОС платформозалежні
  поля пишуть `n/a (unsupported on <os>)` замість того, щоб мовчки бути
  порожніми. Це свідоме рішення, а не обмеження.
- Таблиця багів вище — доказ рівня Junior "maintain and fix": усі шість багів
  справжні, знайдені під час прогонів цього ж кіта.
