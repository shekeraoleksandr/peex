# Maintain & fix an automation script

## Symptom
`broken-cleanup.sh DIR DAYS` was meant to delete log files **older** than
`DAYS` days, but it was deleting the **most recent** logs and leaving old ones.

## Root cause
`find`'s `-mtime` sign was wrong:
- `-mtime -N` → modified **within** the last N days (recent files)
- `-mtime +N` → modified **more than** N days ago (old files)

The script used `-mtime -"$DAYS"`, so it matched the wrong set.

## Fix
Change `-mtime -"$DAYS"` to `-mtime +"$DAYS"` (see `cleanup.sh`).

## Regression test
`test-cleanup.sh` creates an old (10-day) and a new log, runs both scripts with
`DAYS=7`, and asserts the fixed script deletes only the old file while the
broken one deletes the new file. Run:
```bash
./test-cleanup.sh
```
