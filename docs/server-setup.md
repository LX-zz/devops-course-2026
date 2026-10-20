# Конфигурация виртуальной машины devops-vm

Практическая работа № 5 — «Удалённый сервер и безопасный доступ. SSH, sudo, UFW, DNS».

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Гипервизор | Oracle VirtualBox 7.2.16 |
| Хостовая система | macOS, ARM64 (Apple Silicon) |
| Гостевая система | Ubuntu Server 24.04 LTS, ARM64 (aarch64) |
| Имя виртуальной машины | `devops-vm` |
| ОЗУ | 2048 МБ |
| Процессор | 2 виртуальных ядра |
| Виртуальный диск | 25 ГБ, VDI |
| Графический контроллер | VMSVGA, 64 МБ видеопамяти |
| Прошивка | EFI |

## 2. Сетевые интерфейсы

| Адаптер | Интерфейс Ubuntu | Адрес | Назначение |
|---|---|---|---|
| NAT | `enp0s8` | `10.0.2.15/24` | Интернет и загрузка пакетов |
| Host-only (`devops-hostonly`) | `enp0s9` | `192.168.56.3/24` | Прямое соединение с Mac |

Для NAT шлюз — `10.0.2.2`. Host-only сеть: `192.168.56.0/24`.

Команды проверки:

```bash
ip -brief address
ip route
```

При первоначальной настройке наблюдались ошибки разрешения имени `ports.ubuntu.com`. Создан файл `/etc/systemd/resolved.conf.d/99-devops-dns.conf`:

```ini
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9
```

После изменения настроек выполнялись `sudo systemctl restart systemd-resolved` и `resolvectl query ports.ubuntu.com`.

## 3. Правило проброса портов

| Поле | Значение |
|---|---|
| Имя правила | `ssh` |
| Протокол | TCP |
| Адрес хоста | `127.0.0.1` |
| Порт хоста | `2222` |
| Порт гостя | `2222` |

Первоначально порт гостя был 22, после усиления защиты SSH изменён на 2222.

Команда настройки на Mac для **выключенной** ВМ (если правило отсутствует):

```bash
VBoxManage modifyvm "devops-vm" --nat-pf1 "ssh,tcp,127.0.0.1,2222,,2222"
```

Если правило уже существует, не добавляйте дубликат; проверьте `VBoxManage showvminfo "devops-vm" --details`.

## 4. Учётные записи

| Имя | UID | Роль |
|---|---|---|
| `student` | 1000 | Первоначальный пользователь при установке системы |
| `devops` | 1001 | Администратор сервера, включён в группу `sudo` |

Создание административного пользователя:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

С Mac создан отдельный ключ `~/.ssh/devops_vm` (ED25519), открытая часть перенесена в `/home/devops/.ssh/authorized_keys`. Закрытый ключ хранится на Mac и в репозиторий не загружается.

Права доступа на сервере:

```text
700 /home/devops/.ssh
600 /home/devops/.ssh/authorized_keys
```

Конфигурация клиента на Mac (`~/.ssh/config`):

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Подключение: `ssh devops`. Для использования ключа может запрашиваться его парольная фраза; пароль учётной записи для SSH не используется.

## 5. Служба SSH

Сервер OpenSSH установлен пакетом `openssh-server`. Главный конфигурационный файл сохранён в `/etc/ssh/sshd_config.backup`; усиление защиты оформлено отдельным файлом `/etc/ssh/sshd_config.d/99-hardening.conf`:

```sshconfig
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Сокет-активация отключена, служба активирована:

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo sshd -t
sudo systemctl restart ssh
sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'
sudo ss -tlnp | grep sshd
```

Проверено, что сервер слушает `0.0.0.0:2222` и `[::]:2222`. Попытки войти под `root` и без открытого ключа отклоняются с `Permission denied (publickey)`; журнал содержит сообщение о том, что root отсутствует в `AllowUsers`.

**Безопасность при восстановлении:** до изменения SSH держать существующий сеанс открытым; новое соединение проверять в другом терминале. Не отключать парольную аутентификацию до проверки доступа по ключу.

## 6. Межсетевой экран UFW

Политики: `deny incoming`, `allow outgoing`, маршрутизация по умолчанию отключена.

| Порт | Действие | Назначение |
|---|---|---|
| `2222/tcp` | `LIMIT IN` | SSH с ограничением частоты подключения |
| `80/tcp` | `ALLOW IN` | HTTP для практической № 6 |
| `443/tcp` | `ALLOW IN` | HTTPS |

Правила установлены для IPv4 и IPv6. Уровень журналирования — `medium`.

Команды первичной настройки:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
# Удалить старое ALLOW-правило, если оно осталось:
sudo ufw status numbered
sudo ufw logging medium
sudo ufw status verbose
```

**Важно:** перед `ufw enable` сначала разрешить SSH-порт. Не закрывать действующую SSH-сессию до проверки нового подключения.

Проверка блокировки с Mac:

```bash
curl -m 3 http://192.168.56.3:8080
```

Проверка журнала на Ubuntu:

```bash
sudo grep 'UFW BLOCK' /var/log/ufw.log | tail -5
```

Зафиксированы реальные поля: `SRC=192.168.56.1`, `DST=192.168.56.3`, `PROTO=TCP`, `DPT=8080`, `IN=enp0s9`. Это входящая попытка TCP-соединения на закрытый порт 8080, которую UFW заблокировал.

## 7. Локальное доменное имя

На Mac в `/etc/hosts` добавлено:

```text
192.168.56.3 devops.local
```

Проверены `ping -c 4 devops.local` (4 ответа, потерь 0%) и вход `ssh -p 2222 -i ~/.ssh/devops_vm devops@devops.local`.

На Ubuntu выполнено:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127\.0\.1\.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f
```

Ожидаемый и полученный FQDN: `devops-vm.devops.local`.

## 8. Снимки состояния

1. `01-clean-install` — Ubuntu, базовая сеть и установленный SSH; создан и проверен.
2. `02-keys-configured` — пользователь `devops` и ключевая аутентификация; создан и проверен.
3. `03-ssh-hardened` — состояние после защиты SSH; **проверить наличие в VirtualBox перед сдачей**.

На Mac:

```bash
VBoxManage snapshot "devops-vm" list
```

ВМ должна сохраняться для следующих практических работ (Nginx, Docker, Ansible, Prometheus/Grafana).

## 9. Аудит конфигурации

Скрипт: `scripts/audit.sh`.

Проверки: запрет root, запрет пароля, нестандартный порт, `MaxAuthTries 3`, активный UFW, политика `deny incoming`.

Результаты:

- Корректная конфигурация: **6 успешно, 0 ошибок, код возврата 0**.
- Временно изменено `MaxAuthTries` на 10: **5 успешно, 1 ошибка, код возврата 1**.
- Затем `MaxAuthTries` возвращён к 3: **6 успешно, код возврата 0**.

Команды:

```bash
cd ~/devops-course-2026
./scripts/audit.sh
echo "Код возврата: $?"
```

## 10. Краткий порядок восстановления

1. Запустить Ubuntu Server и проверить оба адаптера через `ip -brief address`.
2. Проверить и при необходимости восстановить DNS (`resolved.conf.d`).
3. Установить `openssh-server`, если отсутствует.
4. Создать `devops`, добавить в `sudo`, проверить вход по открытому ключу.
5. Скопировать `99-hardening.conf` и проверить `sudo sshd -t` и `sudo sshd -T`.
6. Перевести SSH на порт 2222, согласовать проброс NAT 2222→2222, проверить новое соединение до закрытия старого.
7. Разрешить 2222/tcp, 80/tcp и 443/tcp, установить политики UFW и включить его, затем заменить SSH ALLOW на LIMIT.
8. Настроить локальное имя на Mac и FQDN внутри Ubuntu.
9. Запустить `scripts/audit.sh` и проверить шесть успешных тестов, код 0.
10. Сверить снимки и документировать фактические значения IP/параметров (они могут измениться после пересоздания ВМ).
