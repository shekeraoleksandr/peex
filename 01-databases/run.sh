#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p proof
PSQL="docker compose exec -T postgres psql -U peex_admin -d company"
# mongod now requires TLS for every connection (requireTLS); self-signed cert
# is not host-verified, so client-side we allow invalid certs for this lab.
MONGO="docker compose exec -T mongo mongosh -u peex_admin -p peex_pass --authenticationDatabase admin --tls --tlsAllowInvalidCertificates --quiet"

# Print the command that produced the output below it, into $LOG and console.
LOG=/dev/null
note() { echo "\$ $1" | tee -a "$LOG"; }

echo "==> Provisioning database instances (docker compose up)"
docker compose up -d --wait

LOG=proof/03_provision.log
echo "==> [Trainee] Provision & configure a database instance" | tee "$LOG"
note 'docker compose ps'
docker compose ps                                              | tee -a "$LOG"
echo "-- Instance configuration applied at startup:"           | tee -a "$LOG"
note '$PSQL -c "SHOW shared_buffers; SHOW max_connections;"'
$PSQL -c "SHOW shared_buffers; SHOW max_connections;"          | tee -a "$LOG"
echo "-- Configured roles:"                                    | tee -a "$LOG"
note '$PSQL -c "\du"'
$PSQL -c "\du"                                                 | tee -a "$LOG"

LOG=proof/02_engine_version.log
echo "==> [Trainee] Identify database engine version"          | tee "$LOG"
note '$PSQL -f - < sql/02_engine_version.sql'
$PSQL -f - < sql/02_engine_version.sql                         | tee -a "$LOG"
echo "-- MongoDB engine version:"                              | tee -a "$LOG"
note '$MONGO --eval "print(db.version())"'
$MONGO --eval "print(db.version())"                            | tee -a "$LOG"

LOG=proof/01_execute_query.log
echo "==> [Trainee] Execute SQL query to retrieve data"        | tee "$LOG"
note '$PSQL -f - < sql/01_execute_query.sql'
$PSQL -f - < sql/01_execute_query.sql                          | tee -a "$LOG"

LOG=proof/04_sql_solution.log
echo "==> [Middle] Configure & maintain SQL-based solution"    | tee "$LOG"
echo "-- Table structure with constraints:"                    | tee -a "$LOG"
note '$PSQL -c "\d employees"'
$PSQL -c "\d employees"                                        | tee -a "$LOG"
echo "-- Configured indexes:"                                  | tee -a "$LOG"
note "\$PSQL -c \"SELECT indexname, indexdef FROM pg_indexes WHERE tablename='employees';\""
$PSQL -c "SELECT indexname, indexdef FROM pg_indexes WHERE tablename='employees';" | tee -a "$LOG"
echo "-- Schema backup via pg_dump (maintenance task):"        | tee -a "$LOG"
note 'docker compose exec -T postgres pg_dump -U peex_admin -d company --schema-only | head -35'
docker compose exec -T postgres pg_dump -U peex_admin -d company --schema-only | head -35 | tee -a "$LOG"

LOG=proof/05_nosql.log
echo "==> [Middle] Configure & maintain NoSQL database"        | tee "$LOG"
note '$MONGO < nosql/query.js'
$MONGO < nosql/query.js                                        | tee -a "$LOG"

LOG=proof/06_security.log
echo "==> [Middle] Security: network restriction + TLS enforcement" | tee "$LOG"
echo "-- Host ports are bound to 127.0.0.1 only (not reachable from LAN):" | tee -a "$LOG"
note 'docker compose port postgres 5432'
docker compose port postgres 5432                              | tee -a "$LOG"
note 'docker compose port mongo 27017'
docker compose port mongo 27017                                | tee -a "$LOG"

echo "-- Postgres: TLS-required connection from a sibling container (simulated remote client) succeeds:" | tee -a "$LOG"
note "psql 'host=postgres port=5432 dbname=company user=peex_admin sslmode=require' -c 'select 1 as tls_ok;'   [from client container]"
docker compose exec -T client bash -c \
  "PGPASSWORD=peex_pass psql 'host=postgres port=5432 dbname=company user=peex_admin sslmode=require' -c 'select 1 as tls_ok;'" \
  | tee -a "$LOG"

echo "-- Postgres: the same connection WITHOUT TLS is rejected by pg_hba.conf (expected failure):" | tee -a "$LOG"
note "psql 'host=postgres port=5432 dbname=company user=peex_admin sslmode=disable' -c 'select 1;'   [from client container]"
docker compose exec -T client bash -c \
  "PGPASSWORD=peex_pass psql 'host=postgres port=5432 dbname=company user=peex_admin sslmode=disable' -c 'select 1;'" \
  2>&1 | tee -a "$LOG" || true

echo "-- MongoDB: TLS-required connection succeeds:"          | tee -a "$LOG"
note "mongosh 'mongodb://peex_admin:***@localhost:27017/admin?tls=true&tlsAllowInvalidCertificates=true' --eval 'db.runCommand({ping:1}).ok'"
docker compose exec -T mongo mongosh \
  "mongodb://peex_admin:peex_pass@localhost:27017/admin?tls=true&tlsAllowInvalidCertificates=true" \
  --quiet --eval "print('tls_ok:', db.runCommand({ping:1}).ok)" | tee -a "$LOG"

echo "-- MongoDB: the same connection WITHOUT TLS is rejected (expected failure):" | tee -a "$LOG"
note "mongosh 'mongodb://peex_admin:***@localhost:27017/admin?tls=false' --eval 'db.runCommand({ping:1}).ok'"
docker compose exec -T mongo mongosh \
  "mongodb://peex_admin:peex_pass@localhost:27017/admin?tls=false" \
  --quiet --eval "print(db.runCommand({ping:1}).ok)" 2>&1 | tee -a "$LOG" || true

echo "-- Least privilege: app_reader can SELECT ..."          | tee -a "$LOG"
note "psql -U app_reader -d company -c 'SELECT COUNT(*) FROM employees;'   [app_reader]"
docker compose exec -T postgres bash -c \
  "PGPASSWORD=reader_pass psql -U app_reader -d company -c 'SELECT COUNT(*) FROM employees;'" \
  | tee -a "$LOG"

echo "-- ... but is denied INSERT (expected failure):"        | tee -a "$LOG"
note "psql -U app_reader -d company -c \"INSERT INTO employees(...) VALUES (...);\"   [app_reader]"
docker compose exec -T postgres bash -c \
  "PGPASSWORD=reader_pass psql -U app_reader -d company -c \"INSERT INTO employees(full_name,email,dept_id,salary) VALUES ('X','x@x.com',1,1000);\"" \
  2>&1 | tee -a "$LOG" || true

LOG=proof/07_backup_restore.log
echo "==> [Middle] Backup & restore (full data, not schema-only)" | tee "$LOG"
mkdir -p backup
echo "-- Full pg_dump (schema + data):"                        | tee -a "$LOG"
note 'docker compose exec -T postgres pg_dump -U peex_admin -d company > backup/company_backup.sql'
docker compose exec -T postgres pg_dump -U peex_admin -d company > backup/company_backup.sql
note 'wc -l backup/company_backup.sql'
wc -l backup/company_backup.sql                                | tee -a "$LOG"

echo "-- Restore into a fresh database to prove reproducibility:" | tee -a "$LOG"
note 'psql -d postgres -c "DROP DATABASE IF EXISTS company_restore_test;"'
docker compose exec -T postgres psql -U peex_admin -d postgres -c "DROP DATABASE IF EXISTS company_restore_test;" | tee -a "$LOG"
note 'psql -d postgres -c "CREATE DATABASE company_restore_test OWNER peex_admin;"'
docker compose exec -T postgres psql -U peex_admin -d postgres -c "CREATE DATABASE company_restore_test OWNER peex_admin;" | tee -a "$LOG"
note 'psql -d company_restore_test < backup/company_backup.sql   [restore]'
docker compose exec -T postgres psql -U peex_admin -d company_restore_test < backup/company_backup.sql > backup/restore_output.log 2>&1
note 'tail -5 backup/restore_output.log'
tail -5 backup/restore_output.log                               | tee -a "$LOG"

echo "-- Verify restored row count matches the original (5 employees):" | tee -a "$LOG"
note "psql -d company_restore_test -c 'SELECT COUNT(*) AS restored_rows FROM employees;'"
docker compose exec -T postgres psql -U peex_admin -d company_restore_test -c "SELECT COUNT(*) AS restored_rows FROM employees;" | tee -a "$LOG"
note 'psql -d postgres -c "DROP DATABASE company_restore_test;"'
docker compose exec -T postgres psql -U peex_admin -d postgres -c "DROP DATABASE company_restore_test;" | tee -a "$LOG"

echo ""
echo "==> Done. Reproducible proof saved in ./proof/ and ./backup/"
