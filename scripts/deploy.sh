#!/usr/bin/env bash

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=false

# Проверка аргументов
if [[ $# -eq 1 && "$1" == "--dry-run" ]]; then
    DRY_RUN=true
elif [[ $# -ne 0 ]]; then
    echo "Ошибка: допустим только аргумент --dry-run" >&2
    exit 1
fi

# Проверка наличия главной страницы
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: отсутствует site/index.html" >&2
    exit 1
fi

# Проверка чистоты Git
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории имеются незакоммиченные изменения" >&2
    exit 1
fi

COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

echo "Деплой коммита: $COMMIT"

RSYNC_ARGS=(-avz --delete --chmod=D755,F644)

if [[ "$DRY_RUN" == true ]]; then
    RSYNC_ARGS+=(--dry-run)
    echo "Режим проверки — изменения не применяются"
fi

# Одно SSH-соединение для доставки
/opt/homebrew/bin/rsync "${RSYNC_ARGS[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"

if [[ "$DRY_RUN" == true ]]; then
    echo "Пробный запуск завершён успешно"
    exit 0
fi

# Проверка HTTPS
if ! curl --silent --show-error --fail \
    --cacert "$CA_CERT" \
    --max-time 10 \
    "$SITE_URL" > /dev/null; then
    echo "Ошибка: сайт недоступен по HTTPS" >&2
    exit 1
fi

echo "Деплой успешно завершён: $COMMIT"
exit 0
