# Minimal Jenkins in Docker

Минимальный проект для запуска Jenkins в Docker с:

- controller в контейнере
- конфигурацией через JCasC
- автосозданием demo pipeline job со stage-ами
- `backend-agent` с Maven и JDK 17
- `flutter-agent` с Flutter SDK и JDK 17
- постоянным volume для `jenkins_home`
- healthcheck для контейнера
- базовыми pipeline-оптимизациями

## Что внутри

- `compose.yaml` - запуск Jenkins
- `controller/Dockerfile` - сборка собственного Jenkins image
- `controller/plugins.txt` - минимальный набор плагинов
- `jcasc/jenkins.yaml` - конфигурация Jenkins как код
- `agents/backend-maven/Dockerfile` - образ backend-агента
- `agents/flutter/Dockerfile` - образ flutter-агента
- `.dockerignore` - уменьшение build context

## Быстрый старт

1. Подготовьте переменные окружения:

   ```bash
   cp .env.example .env
   ```

2. Поднимите Jenkins:

   ```bash
   docker compose up -d --build
   ```

3. Откройте UI:

   `http://localhost:8080`

4. Войдите с логином и паролем из `.env`.

## Что создается автоматически

После старта Jenkins появятся jobs:

- `backend-smoke`
- `flutter-smoke`

И будут зарегистрированы агенты:

- `backend-agent`
- `flutter-agent`

## Остановка

```bash
docker compose down
```

Если нужно удалить данные Jenkins:

```bash
docker compose down -v
```
