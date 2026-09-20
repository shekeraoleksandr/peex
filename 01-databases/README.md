# 01 — DevOps · Databases

PostgreSQL 16 + MongoDB 7 у Docker: обидва з обов'язковим TLS, обмеженим
мережевим доступом, least-privilege ролями та backup/restore. Усе піднімається
однією командою `./run.sh`; вивід кожного кроку — у `proof/` (перед кожним
виводом додається рядок `$ <команда>`).

## Що зробили
- Підняли **PostgreSQL 16** і **MongoDB 7** через `docker compose` (кастомні
  образи `postgres/Dockerfile`, `mongo/Dockerfile`).
- **TLS обов'язковий** на обох двигунах (self-signed cert генерується в образі);
  не-TLS з'єднання відхиляються.
- **Обмеження мережі**: порти лише на `127.0.0.1`; `pg_hba.conf` пускає TLS тільки
  з localhost і docker-мережі, решту — `reject`.
- **Least privilege**: `app_reader` — SELECT-only (Postgres), `catalog_app` —
  readWrite лише на `catalog` (Mongo).
- **SQL-рішення**: схема з PK/FK/UNIQUE/CHECK, індекси, view, seed-дані.
- **NoSQL**: колекція з JSON-Schema валідацією, унікальний + вторинний індекси,
  окремий користувач.
- **Backup/restore**: повний `pg_dump` → відновлення у свіжу БД → звірка кількості рядків.
- Докази кроків: `proof/01..07_*.log`.

Покриває всі «Yes»: Execute SQL query · Identify engine version · Provision &
configure instance · Configure & maintain SQL solution · Configure & maintain
NoSQL — плюс security (TLS / мережа / least-privilege) і backup/restore як
Middle non-functional вимоги.

## Команди для демо

**Запуск / зупинка**
```bash
./run.sh                 # підняти все, виконати демо, зібрати proof/
docker compose ps        # статуси контейнерів
docker compose down -v   # прибрати (разом із volumes)
```

**Підключення до БД** (креденшли з compose: admin `peex_admin`/`peex_pass`,
read-only `app_reader`/`reader_pass`, база `company`)
```bash
# Postgres, адмін (через контейнер — TLS/сертифікати вже налаштовані)
docker compose exec postgres psql -U peex_admin -d company
# Postgres, read-only роль
docker compose exec postgres psql -U app_reader -d company        # пароль: reader_pass
# MongoDB (TLS обов'язковий)
docker compose exec mongo mongosh -u peex_admin -p peex_pass \
  --authenticationDatabase admin --tls --tlsAllowInvalidCertificates

# З самого Mac (потрібні локальні psql / mongosh), TLS required:
PGPASSWORD=peex_pass psql "host=127.0.0.1 port=5432 dbname=company user=peex_admin sslmode=require"
mongosh "mongodb://peex_admin:peex_pass@127.0.0.1:27017/admin?tls=true&tlsAllowInvalidCertificates=true"
```
GUI (DBeaver / TablePlus): host `127.0.0.1`, port `5432`, db `company`,
user `peex_admin`, **SSL mode = require**.

**Показати TLS-enforcement**
```bash
# OK — з TLS:
docker compose exec -T client bash -c "PGPASSWORD=peex_pass psql 'host=postgres port=5432 dbname=company user=peex_admin sslmode=require' -c 'select 1 as tls_ok;'"
# Відхилено — без TLS (очікувано):
docker compose exec -T client bash -c "PGPASSWORD=peex_pass psql 'host=postgres port=5432 dbname=company user=peex_admin sslmode=disable' -c 'select 1;'"
```

**Least privilege** (app_reader читає, але не пише)
```bash
docker compose exec postgres psql -U app_reader -d company -c "SELECT COUNT(*) FROM employees;"
docker compose exec postgres psql -U app_reader -d company -c "INSERT INTO employees(full_name,email,dept_id,salary) VALUES ('X','x@x.com',1,1000);"   # -> permission denied
```

**Де сертифікат** (self-signed, лежить у контейнері, у git не комітиться)
```bash
docker compose exec postgres cat /etc/postgresql/certs/server.crt | openssl x509 -noout -subject -dates
docker compose exec mongo    cat /etc/mongo/certs/mongo.crt       | openssl x509 -noout -subject -dates
```

**Backup / restore вручну**
```bash
docker compose exec -T postgres pg_dump -U peex_admin -d company > backup/company_backup.sql
docker compose exec -T postgres psql -U peex_admin -d postgres -c "CREATE DATABASE company_restore_test OWNER peex_admin;"
docker compose exec -T postgres psql -U peex_admin -d company_restore_test < backup/company_backup.sql
docker compose exec -T postgres psql -U peex_admin -d company_restore_test -c "SELECT COUNT(*) FROM employees;"
```

## Примітка про TLS
Сертифікати self-signed, тож для демо клієнту cert не потрібен (`sslmode=require`
шифрує без перевірки). Для повної перевірки — витягнути cert і `sslmode=verify-ca`
(Postgres) / `tlsCAFile` (Mongo). У проді — cert від довіреного CA + `verify-full`.
