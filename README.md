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
make logs              # открыть общие логи
make config            # вывести итоговую Compose-конфигурацию
make clean-cache       # очистить кэш отдельного Docker daemon Jenkins
make clean-host-cache  # очистить dangling-образы и build cache хоста
```

Jenkins запускает эфемерные агенты `slave`, `java`, `node` и `flutter` в
отдельном Docker daemon. Docker socket хоста в Jenkins не передаётся. Android
агент в первую версию не входит; APK хранятся в raw-репозитории Nexus.

Резервное копирование в первую версию не входит. Данные приложений сохраняются
в Docker volumes при обычном `make down`.
