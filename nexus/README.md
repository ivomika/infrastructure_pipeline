# Nexus

После первого запуска пароль пользователя `admin` находится в
`/nexus-data/admin.password` внутри контейнера.

Минимальный набор репозиториев для ручного создания:

- Maven hosted и Maven Central proxy;
- raw hosted для Android APK;
- Docker hosted с HTTP connector на порту `5000`;
- Docker proxy для Docker Hub.
