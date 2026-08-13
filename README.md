# DevOps infrastructure

Локальная инфраструктура для CI/CD, управления задачами, документации,
артефактов и мониторинга. Корневой `compose.yaml` подключает Compose-файлы
приложений через `include`.

## Production-запуск

```sh
cp .env.example .env
# Укажите production-домены, email Certbot и секреты в .env.
make cert
```

`make cert` запускает временную HTTP-конфигурацию Nginx для ACME challenge,
получает один SAN-сертификат для всех сервисов и переключает Nginx на HTTPS.
Контейнер `certbot-renew` автоматически проверяет необходимость продления
сертификата каждые 12 часов.

Последующие запуски выполняются обычной командой:

```sh
make up
```

Перед выпуском сертификата DNS-записи всех указанных доменов должны вести на
сервер, а порты 80 и 443 должны быть доступны извне. Первый запуск скачивает
образы, собирает Jenkins controller и агентов, поэтому занимает больше времени
следующих.

## Локальный запуск

```sh
make local-up
```

При первом локальном запуске `.env.local` создаётся из `.env.local.example`.
Локальные сервисы работают только по HTTP:

Сервисы доступны через Nginx:

- Jenkins: `http://jenkins.localhost`;
- Plane: `http://plane.localhost`;
- Docmost: `http://docs.localhost`;
- Nexus: `http://nexus.localhost`;
- Nexus Docker registry: `http://registry.localhost`;
- Grafana: `http://grafana.localhost`.

## Команды

```sh
make up                         # production-запуск
make down                       # остановить production
make restart SERVICE=grafana    # перезапустить production-сервис
make logs                       # production-логи
make config                     # итоговая production-конфигурация
make cert                       # первичный выпуск/расширение сертификата
make cert-renew                 # ручной запуск renewal
make clean-cache                # очистить production Jenkins Docker cache

make local-up                   # локальный HTTP-запуск
make local-down                 # остановить локальную инфраструктуру
make local-restart SERVICE=grafana
make local-logs
make local-config
make local-clean-cache

make clean-host-cache           # очистить Docker cache хоста
```

В `SERVICE` указывается имя из Compose, например `jenkins-controller`,
`plane-proxy`, `docmost`, `nexus`, `grafana` или `prometheus`. Команда restart
не пересобирает образ и не пересоздаёт контейнер.

Jenkins запускает эфемерные агенты `slave`, `java`, `node` и `flutter` в
отдельном Docker daemon. Docker socket хоста в Jenkins не передаётся. Android
агент в первую версию не входит; APK хранятся в raw-репозитории Nexus.

Версии toolchain агентов зафиксированы в Dockerfile:

- Jenkins agent `3384.v60d89463d9e0-1`, JDK 21;
- Docker CLI `28.5.2`;
- Maven `3.9.11`;
- Node.js `22.23.2`, npm `10.9.8`;
- Flutter `3.44.9`, Dart `3.12.2`.

## Мониторинг проектов

Grafana автоматически формирует дашборд `Project Overview` из Blackbox-метрик.
Чтобы подключить проект, добавьте backend и frontend endpoints в
`grafana/prometheus/targets/projects.yml`. Используйте одинаковый `project` и
`environment`, а в `component` укажите соответственно `backend` и `frontend`.
Prometheus применяет изменения target-файла без перезапуска.
Для HTTPS endpoints дашборд также показывает использование TLS, оставшийся срок
сертификата и текущее время ответа. Для локальных HTTP endpoints TLS-панель срока
действия остаётся без данных.

Дашборд `Infrastructure Overview` показывает результат последнего запуска
Certbot, время с последней успешной проверки и оставшийся срок действия общего
SAN-сертификата. Метрики формирует `certbot-renew` и передаёт в Prometheus через
textfile collector Node Exporter.

Резервное копирование в первую версию не входит. Production и local используют
разные Compose project names и отдельные Docker volumes. Данные production-
приложений сохраняются в volumes при обычном `make down`.
