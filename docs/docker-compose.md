# Практическая №7. Docker и Docker Compose

## Окружение

- Ubuntu Server 24.04 ARM64
- Oracle VirtualBox
- Docker Engine
- Docker Compose v5.6.1
- Python 3.12
- Flask 3.0.3
- Gunicorn 22.0.0
- PostgreSQL 16
- Nginx 1.24.0

## Docker-образ

Образ: devops-app:1.0

Базовый образ: python:3.12-slim

Приложение запускается от непривилегированного пользователя app.

Зависимости устанавливаются отдельным слоем Dockerfile.

После изменения app.py повторная сборка использовала кэш
для установки зависимостей.

## Docker Compose

Сервисы:
- app — Flask и Gunicorn
- db — PostgreSQL 16

Сеть: backend

Постоянный том: app_db_data

Порт Flask опубликован только на 127.0.0.1:5000.

PostgreSQL не публикуется наружу.

Пароль хранится в локальном файле .env.

## Тестирование

GET /health — HTTP 200.

GET / без PostgreSQL — HTTP 500.

После запуска PostgreSQL счётчик посещений:
1, 2, 3.

После пересоздания контейнеров счётчик продолжился с 4.

После перезагрузки Ubuntu счётчик продолжился с 7.

Это подтвердило сохранность данных PostgreSQL.

## Nginx и HTTPS

Старый сайт:
https://devops.local/

Flask:
https://devops.local/app/

Проверка:
https://devops.local/app/health

Настроено проксирование запросов на 127.0.0.1:5000.

HTTPS использует TLS-сертификат из практической №6.

## Аудит безопасности

Проверены:
- SSH
- UFW
- Nginx
- HTTPS
- Docker Engine
- Docker Compose
- PostgreSQL
- Flask через HTTPS

Результат: 12 успешных проверок, 0 ошибок.

Код возврата: 0.
