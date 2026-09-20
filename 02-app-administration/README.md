# 02 — DevOps · Application Administration

Nginx-сервіс, розгорнутий на **реальній VM (Ubuntu Server 24.04) через SSH**:
окремий користувач, systemd з hardening, автозапуск після ребуту та
автоматизований maintenance. Керується скриптом `remote.sh` з твого Mac; живий
proof автоматично тягнеться у `proof/`.

## Що зробили
- **`remote.sh`** — SSH-оркестратор: копіює kit на VM, ставить, збирає proof,
  тягне його назад на Mac.
- **`install.sh`** (виконується на VM): nginx з apt, окремий non-login юзер
  `peexweb`, кастомний конфіг (порт 8080, свої логи/temp/pid), systemd-unit
  `peex-web` під цим юзером, `enable` + `start`. Ідемпотентно, без ручних кроків.
- **Hardening** юніта: `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`,
  `PrivateTmp`, порожній `CapabilityBoundingSet`, високий порт (без root-біндингу).
- **Автозапуск після ребуту** (`systemctl enable`) — доводиться `reboot-proof`.
- **Maintenance (Middle)**: `upgrade` з бекапом і **авто-rollback** при провалі
  smoke-тесту; `rollback`; `healthcheck` (systemd/HTTP/порт + Prometheus-метрика);
  `smoke_test`.
- **`collect-proof.sh`** збирає всі артефакти (status, ps, ss, curl, journalctl) у `proof/`.

Покриває: **Deploy and configure a service on OS level** (Junior KEY),
**Automate maintenance procedures** (Middle).

## Команди для демо

**Задати ціль (один раз у сесії терміналу)**
```bash
export VM=ubuntu@<твоя-адреса>      # напр. ubuntu@203.0.113.10
export SSH_KEY=~/.ssh/<ключ>        # можна пропустити, якщо ключ дефолтний / в агенті
```

> Якщо ключ під пасфразою — завантаж його в агент один раз (щоб не вводити щоразу):
> ```bash
> eval "$(ssh-agent -s)" && ssh-add --apple-use-keychain ~/.ssh/id_ed25519   # macOS
> ```
> `install.sh` виконується через `sudo` по SSH з TTY (`ssh -t`), тож на VM sudo
> спитає твій пароль у терміналі — це нормально.

**Основний потік (з Mac)**
```bash
./remote.sh deploy        # копіює kit + sudo ./install.sh на VM
./remote.sh proof         # collect-proof на VM + тягне proof/ сюди
./remote.sh maintenance   # healthcheck + upgrade + rollback
./remote.sh reboot-proof  # ребут VM + доказ автозапуску
./remote.sh all           # усе разом (deploy -> proof -> reboot-proof)
./remote.sh teardown      # прибрати сервіс з VM
./remote.sh ssh           # інтерактивний шелл на VM
```

**Перевірити сервіс (з будь-де)**
```bash
curl http://<vm>:8080/          # статус-сторінка
curl http://<vm>:8080/healthz   # ok
```

**На VM (через `./remote.sh ssh`) — що показати рецензенту**
```bash
systemctl status peex-web --no-pager             # active, під користувачем peexweb
systemctl is-enabled peex-web                    # enabled (автозапуск)
ps -C nginx -o user,pid,cmd                      # процеси від peexweb, не root
ss -ltnp | grep :8080                            # слухає порт 8080
journalctl -u peex-web -e --no-pager             # логи (healthy)
sudo nginx -t -c /etc/peex-web/nginx-peex.conf   # валідність конфіга
```

**Друга чиста VM** (reproducibility): `export VM=ubuntu@<інший-хост>` і повторити
`./remote.sh deploy` + `./remote.sh proof`.

Докази (тягнуться в `proof/` після `./remote.sh proof` / `reboot-proof`):
`00_deploy_proof.txt`, `01_after_reboot.txt`.
