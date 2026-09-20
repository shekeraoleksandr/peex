# Modifying an existing automation script

`scripts/sysreport.sh` started as a **text-only v1** that just printed a fixed
report to stdout. It was then **modified** to make it more useful and scriptable.

> Оригінал лежить окремим файлом — `modify/sysreport.v1.sh`, щоб можна було
> зробити справжній `diff` проти поточної версії, а не порівнювати з блоком у
> документі.

## Original v1 (before)
```bash
#!/usr/bin/env bash
set -euo pipefail
echo "Host   : $(hostname)"
echo "Kernel : $(uname -sr)"
echo "Uptime : $(uptime -p)"
echo "Memory : $(free -m | awk '/Mem:/{print $3"/"$2" MB"}')"
echo "Disk   : $(df -h / | awk 'NR==2{print $5}')"
```

## Changes made (v2)
1. Added a `--json` flag to emit machine-readable output (for pipelines/monitoring).
2. Added a `--out FILE` flag to write the report to a file.
3. Added `--help` usage and strict argument parsing (`die` on unknown args).
4. Added more signals: load average, CPU count, top-3 processes by CPU.
5. Extracted shared logging/`die` into `lib/common.sh` (reuse, consistency).

## Changes made (v3 — cross-platform round)
6. **Платформний шар.** v2 був Linux-only так, що про це ніхто не дізнавався:
   на macOS немає `free`, `nproc`, `/proc/loadavg` і `ps --sort`, кожен з цих
   збоїв ковтався власним `2>/dev/null`, і звіт виходив з трьома **порожніми**
   полями. Скрипт моніторингу, який тихо нічого не повідомляє, гірший за той,
   що падає: нижче по конвеєру не відрізнити "0 процесів" від "я не зміг
   подивитись". Тепер кожен збирач має реалізацію під Linux і під Darwin
   (`sysctl`, `vm_stat`, `ps -Aco`), а на будь-якій іншій ОС поле чесно пише
   `n/a (unsupported on <os>)`.
7. **Валідація аргументів до початку роботи** — `--out` перевіряє, що каталог
   існує і доступний на запис, ще до збору даних.
8. **Контракт кодів виходу**: `0` — звіт зроблено, `2` — некоректний виклик,
   `3` — не вдалось записати `--out`. Раніше все було `1` через `die`.
9. **Екранування JSON** — ім'я процесу з лапкою більше не ламає документ.
10. `FORCE_OS=<Linux|Darwin>` — щоб перевірити другу гілку не міняючи машину.

## Why
The original could only be read by a human. The modification lets the same
script feed dashboards/tickets (`--json`), persist artifacts (`--out`), and fail
loudly on bad input — without changing how a human runs it.

## Verify the modification
```bash
# оригінал vs поточна версія — той самий diff, що йде в артефакти
diff -u modify/sysreport.v1.sh scripts/sysreport.sh | head -40

# обидві платформні гілки з однієї машини
./scripts/sysreport.sh
FORCE_OS=Darwin ./scripts/sysreport.sh

# коди виходу
./scripts/sysreport.sh --bogus;        echo "exit=$?"   # 2
./scripts/sysreport.sh --out /nope/x;  echo "exit=$?"   # 3
./scripts/sysreport.sh --json | python3 -m json.tool >/dev/null; echo "valid JSON exit=$?"
```

```bash
../scripts/sysreport.sh                 # human-readable (as before)
../scripts/sysreport.sh --json          # NEW machine-readable output
../scripts/sysreport.sh --json --out /tmp/report.json && cat /tmp/report.json
```
