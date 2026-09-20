# 07 — DevOps · Security

Три речі, які доводяться на реальній системі: **ревʼю доступів** (хто що може),
**перевірка firewall проти baseline** і **захищений SSH**. Все self-contained,
без хмарного акаунта; AWS IAM-ревʼю є окремим бонусним скриптом. Живі докази —
у `proof/`.

| Level | Competency item | Covered by |
|---|---|---|
| Trainee | Prepare user access data for least-privilege review | `access-review/access-review.sh` (+ `aws-iam-review.sh`) |
| Trainee | Verify firewall rules against provided baseline | `firewall/verify-firewall.sh` + `firewall-baseline.txt` |
| Junior (KEY) | Configure and use secure shell access | `ssh/setup-ssh.sh` (генерація + hardening) та `ssh/ssh-access-demo.sh` (використання: config, agent, forwarding, SCM) |

## Що зробили
- **Ревʼю доступів**: скрипт збирає інвентар акаунтів, здатних логінитись, усі
  UID 0, членів привілейованих груп, `authorized_keys`, статус паролів/локів і
  `NOPASSWD`-права в sudoers — і **позначає** підозріле для власника безпеки.
  Це рівно той артефакт, який віддають на least-privilege review.
- **Працює і на Linux, і на macOS.** Перша версія читала `/etc/passwd`,
  `/etc/group`, `/etc/shadow` напряму — на Ubuntu правильно, на macOS **тихо
  неправильно**: у `/etc/passwd` там лише системні акаунти (справжні живуть в
  Open Directory), `getent` не існує, `/etc/shadow` теж, а коментарі з шапки
  `/etc/passwd` awk приймав за акаунти. Ревʼю доступів, яке **недорахувало**
  людей і виглядало чистим, гірше за те, що впало з помилкою — тому
  платформозалежні запити винесені у чотири функції з реалізацією під кожну ОС
  (`dscl` на macOS), а все, що неможливо перевірити, тепер прямо про це пише.
- **Перевірка firewall проти baseline**: `verify-firewall.sh` порівнює живий
  ruleset (`iptables -L -n` / `ufw status verbose` / `nft list ruleset`) з
  `firewall-baseline.txt` і друкує таблицю PRESENT/MISSING. Працює і офлайн —
  проти захопленого `sample-rules.txt`, щоб демо не залежало від хоста.
- **Захищений SSH**: drop-in `99-peex-hardening.conf` вимикає root-логін і
  парольну автентифікацію, лишає тільки ключі, обмежує кількість спроб і
  прибирає форвардинг. `setup-ssh.sh` генерує ключ, валідує конфіг через
  `sshd -t` і показує **ефективні** налаштування (`sshd -T`), а не бажані.
- Усе прогнано наживо: реальний `access-review`, реальне порівняння з baseline
  і реальний `sshd -t` — докази в `proof/01..03`.

### Де ця компетенція підкріплена рештою портфоліо
Ці три пункти доводяться і на справжній інфраструктурі, яку ми підняли:
- **Firewall наживо** — security groups у `../11-network/`: доступ ззовні лише
  з твого IP, а порт `node_exporter` (9100) відкритий **тільки** для SG
  моніторинг-інстансу. У пруфі `11-network` є і негативний тест: спроба
  достукатись на 9100 з інтернету падає по таймауту.
- **SSH наживо** — `../02-app-administration/` керує реальною VM виключно по
  SSH (`remote.sh`), а `../11-network/` генерує ключ через Terraform
  (`tls_private_key`), і приватна частина ніколи не їде в хмару.
- **Least privilege наживо** — IAM-ролі read-only/read-write у `../03-storages/`
  з доведеною відмовою на запис під RO-роллю.

## Команди для демо
```bash
# 1) ревʼю доступів (sudo — щоб дістати shadow/sudoers)
sudo ./access-review/access-review.sh | tee proof/01_access_review.txt
sudo ./access-review/access-review.sh review.json    # + JSON-звіт
FORCE_OS=Linux sudo -E ./access-review/access-review.sh   # перевірити другу гілку
./access-review/aws-iam-review.sh                    # бонус: те саме для AWS IAM

# 2) firewall проти baseline
./firewall/verify-firewall.sh firewall/firewall-baseline.txt firewall/sample-rules.txt  # офлайн
sudo ./firewall/verify-firewall.sh                   # проти живого ruleset

# 3) захищений SSH
./ssh/setup-ssh.sh
```

Показати ревьюеру наживо:
```bash
# що саме зайшло в hardening і що реально діє
cat ssh/99-peex-hardening.conf
sudo sshd -t && echo "config OK"
sudo sshd -T | grep -Ei 'permitrootlogin|passwordauth|pubkeyauth|maxauthtries|allowtcpforwarding'

# 3) SSH наживо: config + agent + forwarding + GitHub  -> proof/04_ssh_access.txt
./ssh/ssh-access-demo.sh
#    опційно, з push у СВІЙ тестовий репозиторій:
#    PUSH_REPO=git@github.com:<you>/<scratch>.git ./ssh/ssh-access-demo.sh

# firewall наживо на реальній інфраструктурі (11-network)
aws ec2 describe-security-groups --filters "Name=group-name,Values=*peex*" \
  --query 'SecurityGroups[].[GroupName,IpPermissions]' --output json

# негативний тест: порт метрик недоступний з інтернету
curl -m 5 http://<web_public_ip>:9100/metrics   # має впасти по таймауту
```

## Покриття критеріїв «Configure and use secure remote access»

| Критерій | Де доводиться |
|---|---|
| SSH key pair generated | `ssh-access-demo.sh` §1 — ed25519, `-a 100`, **з passphrase**; плюс `tls_private_key` у `../11-network/terraform` |
| Public key added to target systems | `aws_key_pair` в `../11-network`; окремий ключ для нового юзера — `../05-compute/os-config.sh` |
| Key-based connection established | §4 — логін по алiасу `peex-web` |
| Login as non-root user | §4 — `ubuntu`, і `peexops` у `../05-compute/os-config.sh` |
| Privilege escalation (sudo) | §5 — `uid` до і після `sudo` |
| SSH key added to SCM + git over SSH | §9 — `ssh -T git@github.com`, `git ls-remote`, `git clone` по SSH |
| Port forwarding (optional) | §8 — `-L` тунель до Prometheus і реальна відповідь через нього |
| Private key 600 + passphrase | §2 — перевірка прав; §1 — доказ, що порожня passphrase **відхиляється** |
| Password authentication disabled | §6 — **негативний тест**: сервер відмовляє, плюс `sshd -T` |
| SSH config used for connection management | §3 — керований блок у `~/.ssh/config`, включно з `ProxyJump` до хоста без публічного IP |
| Key-based faster than password | §10 — час key-based логіну; парольний шлях недоступний в принципі |

### Суперечність, яку варто назвати вголос
`99-peex-hardening.conf` ставить `AllowTcpForwarding no` — і це свідомо ламає
саме те, що демонструє §8. Політика правильна для хоста, де форвардинг нікому
не потрібен (зайвий канал у внутрішню мережу), і неправильна для
моніторинг-інстансу, де тунель — єдиний спосіб дістатись Alertmanager/cAdvisor
без відкриття портів назовні. Тому drop-in застосований на керованій VM, а не
на EC2-хостах. Це компроміс, а не недогляд.

## Структура
```
07-security/
  access-review/   access-review.sh, aws-iam-review.sh
  firewall/        verify-firewall.sh, firewall-baseline.txt, sample-rules.txt
  ssh/             99-peex-hardening.conf, setup-ssh.sh, ssh-access-demo.sh,
                   ssh_client_config.sample
  proof/           01_access_review, 02_firewall_verify, 03_ssh_hardening,
                   04_ssh_access
```

## Чесно про межі
- `firewall-baseline.txt` треба підганяти під формат виводу твого firewall —
  патерни матчаться текстово, а `ufw`, `iptables` і `nft` друкують по-різному.
- `setup-ssh.sh` **не** встановлює drop-in у систему сам: він генерує і валідує,
  а копіювання в `/etc/ssh/sshd_config.d/` + `reload` лишається усвідомленою
  ручною дією. Вимкнути собі SSH одним скриптом — надто легкий спосіб втратити
  доступ до хоста.
