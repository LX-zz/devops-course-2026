#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo "[OK]   $desc"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo

SSH_CONFIG=$(sudo sshd -T)

echo "[1] Служба SSH"

ROOT_LOGIN=$(awk '/^permitrootlogin / {print $2}' <<< "$SSH_CONFIG")
check "Вход от имени root запрещён" "no" "$ROOT_LOGIN"

PASSWORD_AUTH=$(awk '/^passwordauthentication / {print $2}' <<< "$SSH_CONFIG")
check "Парольная аутентификация отключена" "no" "$PASSWORD_AUTH"

SSH_PORT=$(awk '/^port / {print $2}' <<< "$SSH_CONFIG")

if [[ "$SSH_PORT" != "22" && -n "$SSH_PORT" ]]; then
    check "SSH использует нестандартный порт" "yes" "yes"
else
    check "SSH использует нестандартный порт" "yes" "no"
fi

MAX_AUTH=$(awk '/^maxauthtries / {print $2}' <<< "$SSH_CONFIG")
check "Максимум попыток входа — 3" "3" "$MAX_AUTH"

echo
echo "[2] Межсетевой экран"

UFW_STATUS=$(sudo ufw status | awk '/^Status:/ {print $2}')
check "Межсетевой экран активен" "active" "$UFW_STATUS"

UFW_INCOMING=$(sudo ufw status verbose | sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p')
check "Входящие соединения запрещены по умолчанию" "deny" "$UFW_INCOMING"

echo
echo "[3] Учётные записи"

awk -F: '$3 >= 1000 && $3 < 65534 {
    printf "  %s (uid=%s)\n", $1, $3
}' /etc/passwd

echo

echo
echo "[4] Проверки Nginx и HTTPS"

if systemctl is-active --quiet nginx; then
    echo "[OK]   Nginx работает"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Nginx не работает"
    FAIL=$((FAIL + 1))
fi

if curl --silent --show-error --fail     --cacert /etc/ssl/certs/devops.crt --resolve devops.local:443:127.0.0.1     --max-time 10     https://devops.local > /dev/null; then
    echo "[OK]   HTTPS работает"
    PASS=$((PASS + 1))
else
    echo "[FAIL] HTTPS недоступен"
    FAIL=$((FAIL + 1))
fi

echo
echo "[5] Docker и PostgreSQL"

if systemctl is-active --quiet docker; then
    echo "[OK]   Docker Engine работает"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Docker Engine не работает"
    FAIL=$((FAIL + 1))
fi

if docker compose version >/dev/null 2>&1; then
    echo "[OK]   Docker Compose доступен"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Docker Compose недоступен"
    FAIL=$((FAIL + 1))
fi

if (cd /home/devops/app && docker compose exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"') >/dev/null 2>&1; then
    echo "[OK]   PostgreSQL работает"
    PASS=$((PASS + 1))
else
    echo "[FAIL] PostgreSQL недоступен"
    FAIL=$((FAIL + 1))
fi

if curl --silent --show-error --fail \
    --cacert /etc/ssl/certs/devops.crt \
    --resolve devops.local:443:127.0.0.1 \
    --max-time 10 \
    https://devops.local/app/health | grep -qx ok; then
    echo "[OK]   Flask доступен через HTTPS"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Flask недоступен через HTTPS"
    FAIL=$((FAIL + 1))
fi

echo "Пройдено: $PASS, не пройдено: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
