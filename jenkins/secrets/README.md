# Jenkins SSH Secrets

Эта директория используется для SSH-ключа Jenkins Shared Library.

## Что должно лежать в директории

- `shared-library.key` - приватный SSH-ключ
- `shared-library.key.pub` - публичный SSH-ключ
- `known_hosts` - файл с SSH host keys для GitHub

## Как создать ключ

Выполните из корня проекта:

```bash
mkdir -p jenkins/secrets
ssh-keygen -t ed25519 -C "jenkins-shared-library" -f jenkins/secrets/shared-library.key -N ""
chmod 600 jenkins/secrets/shared-library.key
chmod 644 jenkins/secrets/shared-library.key.pub
```

## Как создать known_hosts

```bash
ssh-keyscan -H github.com > jenkins/secrets/known_hosts
chmod 644 jenkins/secrets/known_hosts
```

## Что добавить в GitHub

1. Откройте репозиторий shared library.
2. Перейдите в `Settings -> Deploy keys`.
3. Нажмите `Add deploy key`.
4. Вставьте содержимое файла `jenkins/secrets/shared-library.key.pub`.
5. Не включайте `Allow write access`, если Jenkins должен только читать библиотеку.

## Что указать в `.env`

Пример:

```dotenv
SHARED_LIBRARY_NAME=jenkins_libs
SHARED_LIBRARY_REPOSITORY_URL=git@github.com:your-org/jenkins_libs.git
SHARED_LIBRARY_DEFAULT_BRANCH=main
SHARED_LIBRARY_CREDENTIALS_ID=jenkins-libs-git
SHARED_LIBRARY_SSH_USERNAME=git
SHARED_LIBRARY_SSH_PRIVATE_KEY_PATH=/var/jenkins_home/.ssh/shared-library.key
```
