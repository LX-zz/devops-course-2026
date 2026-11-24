# Практическая работа №11. Ansible

## Цель
Автоматизировать настройку Ubuntu Server 24.04 ARM64,
развёртывание Docker-приложения и проверку конфигурации.

## Окружение
- Управляющий узел: macOS, Ansible Core 2.22
- Сервер: Ubuntu Server 24.04 ARM64
- VM: devops-ansible
- Host-only IP: 192.168.56.6
- SSH: пользователь devops, ключ ansible_devops
- Приложение: Flask, Docker, Nginx
- Реестр: GitHub Container Registry

## Роли
- base: системные пакеты и Docker Engine
- ssh: пользователь devops, SSH и UFW
- nginx: обратный прокси
- app: загрузка образа по SHA и запуск контейнера

## Установка коллекций
cd ansible
ansible-galaxy collection install -r requirements.yml

## Первоначальная настройка
ansible-playbook -i inventory/bootstrap.ini site.yml --ask-become-pass

## Повторный деплой
ansible-playbook site.yml

## Проверка
ansible-playbook verify.yml
curl -i http://192.168.56.6/health

Ожидается HTTP 200 и {"status":"ok"}.

## Идемпотентность
Повторный запуск site.yml:
changed=0, failed=0.

## Инцидент 1: Configuration drift
Удалён контейнер, изменён upstream Nginx.
Получена ошибка HTTP 502.
Восстановление выполнено командой:
ansible-playbook site.yml

Итог: HTTP 200, контейнер работает.

## Инцидент 2: Несуществующий Docker-тег
ansible-playbook site.yml -e 'app_tag=nonexistent-test-20261124'

Получена ошибка 404 Not Found.
Работающий контейнер не был заменён.
После штатного запуска приложение доступно.

## Контрольная проверка
ansible-playbook verify.yml

Результат: ok=7, changed=0, failed=0.
