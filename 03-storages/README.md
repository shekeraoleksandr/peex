# 03 — DevOps · Storages

Реальний AWS S3 + IAM: захищений bucket (без публічного доступу, шифрування,
версіонування, логування) і дві ролі з різними правами (read-only / read-write),
підняті і перевірені скриптами. Все виконується на машині, де залогінений
`aws` CLI — докази лежать у `proof/`.

| Level | Competency item | Covered by |
|---|---|---|
| Trainee | Create a basic storage resource | `provision.sh` |
| Junior | Provision and configure storage services | `provision.sh` + `iam-setup.sh` + `test-access.sh` |

## Що зробили
- Підняли захищений **S3 bucket** `peex-storage-demo-<accountId>` (регіон
  **us-east-1**): блокування публічного доступу (усі 4 прапорці), **шифрування
  at rest** (SSE-S3/AES256 + bucket key), **версіонування**, теги для обліку витрат.
- Додали окремий **log bucket** і увімкнули **server access logging** основного
  bucket'а на нього.
- Створили дві **least-privilege IAM ролі** через STS (без довготривалих ключів):
  `peex-s3-readonly-role` (`ListBucket`/`GetObject`/`GetObjectVersion`) і
  `peex-s3-readwrite-role` (додатково `PutObject`/`DeleteObject`), обидві
  скоуплені тільки на ARN цього bucket'а.
- Довели модель доступу **наживо** і **детерміновано**: RW → upload+download OK;
  RO → download OK, upload **AccessDenied**, delete **AccessDenied**; плюс
  `simulate-custom-policy` дає `s3:GetObject allowed` / `s3:PutObject implicitDeny`
  для RO і обидва `allowed` для RW.
- **Версіонування доводимо як слід**: той самий ключ завантажується двічі, тож
  `list-object-versions` показує ≥2 версії, і стара версія **реально
  відновлюється** по `VersionId` (`get-object --version-id`). Раніше скрипт
  вантажив ключ один раз — це доводило, що версіонування увімкнене, але не що
  воно зберігає попередні копії.
- Пофіксили два баги в скриптах (обидва варто вміти пояснити):
  `simulate-custom-policy --policy-input-list file://...` падав з
  `Policy input list item 1 has invalid content` (aws-cli ненадійно резолвить
  `file://` для list-параметрів → передаємо `"$(cat policy.json)"`), а в
  `teardown.sh` `--query` зліплював два масиви через `+`, чого в JMESPath немає —
  виклик падав, `set -e` тихо вбивав скрипт, і бакети лишались жити.

## Відповідність вимогам NEBO

**Functional**

| Вимога | Де доведено |
|---|---|
| Storage service provisioned | `proof/01_provision.txt` — `PROVISION DONE: s3://peex-storage-demo-…` |
| Public access blocked by default | `01_provision.txt` → `get-public-access-block` (усі 4 = true) |
| Encryption at rest enabled | `01_provision.txt` → `get-bucket-encryption` (AES256 + bucket key) |
| ≥2 access roles/policies, різні рівні | `proof/02_iam.txt` + `policies/readonly-policy.json`, `readwrite-policy.json` |
| RO може завантажувати, але не змінювати | `proof/03_access_tests.txt` — download rc=0, upload `AccessDenied`, delete `AccessDenied` |
| RW може upload + download | `03_access_tests.txt` — обидва rc=0 |
| Object versioning enabled | `01_provision.txt` → `get-bucket-versioning`; `03_access_tests.txt` → ≥2 версії + відновлення старої по `VersionId` |
| Тестовий файл вивантажено і завантажено відповідною роллю | `03_access_tests.txt` (обидві ролі) |

**Non-functional**

| Вимога | Де доведено |
|---|---|
| Least privilege, без надто широких прав | `policies/*.json` — actions і resources скоуплені на один ARN; підтверджено `simulate-custom-policy` |
| Жодних креденшелів у відкритому вигляді | Доступ лише через `sts assume-role`; у репозиторії немає ключів — `grep -rn "AKIA" .` порожній |
| Теги для обліку витрат | `01_provision.txt` → `get-bucket-tagging` (Project/Environment/Competency) |
| Access logs увімкнені | `01_provision.txt` → `get-bucket-logging` → `s3://…-logs/access-logs/` |
| Відтворювана документація | цей README + `provision.sh`/`iam-setup.sh`/`test-access.sh` (ідемпотентні) |

**Скріншоти, яких ще бракує** — чотири артефакти NEBO вимагають саме скріншотів,
термінального виводу для них недостатньо. Зроби і поклади в `proof/`:
1. S3 → bucket → **Properties** (видно Versioning = Enabled, Default encryption).
2. S3 → bucket → **Permissions** → Block public access (усі чотири = On).
3. S3 → bucket → **Objects** → `test.txt` → вкладка **Versions** (видно кілька версій).
4. IAM → Roles → `peex-s3-readonly-role` → Permissions (видно, що немає PutObject).

## Команди для демо
```bash
# 0) перевірити, що aws CLI залогінений
aws sts get-caller-identity

# 1) підняти bucket (ідемпотентно)
./provision.sh          # -> proof/01_provision.txt

# 2) створити IAM-політики та ролі
./iam-setup.sh          # -> proof/02_iam.txt

# 3) довести модель доступу + версіонування
./test-access.sh        # -> proof/03_access_tests.txt
```

Показати ревьюеру наживо:
```bash
B=peex-storage-demo-$(aws sts get-caller-identity --query Account --output text)

aws s3api get-public-access-block --bucket $B     # публічний доступ заблоковано
aws s3api get-bucket-encryption   --bucket $B     # шифрування at rest
aws s3api get-bucket-versioning   --bucket $B     # версіонування
aws s3api get-bucket-logging      --bucket $B     # access logs
aws s3api get-bucket-tagging      --bucket $B     # теги

# усі версії обʼєкта і відновлення попередньої
aws s3api list-object-versions --bucket $B --prefix test.txt \
  --query 'Versions[].[VersionId,IsLatest,LastModified]' --output table

# права ролей
aws iam list-attached-role-policies --role-name peex-s3-readonly-role
aws iam list-attached-role-policies --role-name peex-s3-readwrite-role

# жодних ключів у репо
grep -rn "AKIA" . || echo "no access keys in the kit"
```

Прибрати за собою (щоб не капали гроші):
```bash
./teardown.sh   # питає підтвердження; чистить усі версії й видаляє ресурси
```

## Структура
```
03-storages/
  lib.sh            спільна конфігурація (імена, ARN; ключів немає)
  provision.sh      bucket + public-access-block + encryption + versioning + tags + logging
  iam-setup.sh      дві політики + дві ролі (STS, без довготривалих ключів)
  test-access.sh    RW/RO наживо + policy simulation + доказ версіонування
  teardown.sh       повне прибирання (версії, delete markers, ролі, політики)
  policies/         згенеровані JSON-документи політик
  proof/            01_provision, 02_iam, 03_access_tests
```

## Чесно про межі
- Назва bucket'а похідна від account id — тому глобально унікальна.
- Якщо принципал не має `sts:AssumeRole`, live-тести це покажуть, але
  `simulate-custom-policy` все одно доводить модель прав незалежно від цього.
- Access logs доставляються з затримкою (години), тож у `proof/` видно
  **конфігурацію** логування, а не самі лог-файли. Це очікувано для S3.
