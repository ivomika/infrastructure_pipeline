# DevOps infrastructure

Локальная инфраструктура для CI/CD, управления задачами, документации,
артефактов и мониторинга. Корневой `compose.yaml` подключает Compose-файлы
приложений через `include`.

## Запуск

```sh
make up
```

При первом запуске `.env` создаётся из `.env.example`. Перед использованием
замените значения `change-me-*`. Первый запуск скачивает образы, собирает
Jenkins controller и агентов, поэтому занимает больше времени следующих.

Сервисы доступны через Nginx:

- Jenkins: `http://jenkins.localhost`;
- Plane: `http://plane.localhost`;
- Docmost: `http://docs.localhost`;
- Nexus: `http://nexus.localhost`;
- Nexus Docker registry: `http://registry.localhost`;
- Grafana: `http://grafana.localhost`.

## Команды

```sh
make up                # собрать и запустить инфраструктуру
make down              # остановить контейнеры, сохранив volumes
make restart           # перезапустить все запущенные сервисы
make restart SERVICE=grafana  # перезапустить отдельный Compose-сервис
make logs              # открыть общие логи
make config            # вывести итоговую Compose-конфигурацию
make clean-cache       # очистить кэш отдельного Docker daemon Jenkins
make clean-host-cache  # очистить dangling-образы и build cache хоста
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

Резервное копирование в первую версию не входит. Данные приложений сохраняются
в Docker volumes при обычном `make down`.
