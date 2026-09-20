# How to fill this folder

All offline (needs bash + python3; shellcheck optional):
```bash
{ ./scripts/sysreport.sh; echo; ./scripts/sysreport.sh --json; } | tee proof/01_sysreport.txt
{ ./scripts/backup.sh ./scripts /tmp/peexbk --retention 3 --dry-run; \
  ./scripts/backup.sh ./scripts /tmp/peexbk --retention 3; echo; \
  ./scripts/healthcheck.sh; } | tee proof/02_routine_tasks.txt
./fix/test-cleanup.sh            | tee proof/03_fix_test.txt
./ide/setup-dev-env.sh           | tee proof/04_ide_setup.txt
```

| Item | Proof |
|------|-------|
| Write basic automation script | 01_sysreport.txt |
| Modify existing automation script | 01_sysreport.txt (--json) + modify/MODIFICATION.md |
| Write scripts to automate routine DevOps tasks | 02_routine_tasks.txt |
| Maintain and fix automation scripts | 03_fix_test.txt + fix/BUGFIX.md |
| Prepare IDE for basic development | 04_ide_setup.txt + ide/ files |
