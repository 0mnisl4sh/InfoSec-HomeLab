# InfoSec HomeLab

Стенд операционной ИБ в Docker Compose: Linux-сервер с SSH и nginx, MySQL, Redis, RabbitMQ, Gitea, двухуровневый удостоверяющий центр на OpenSSL, Zabbix и Wazuh.

Стенд стартует в намеренно небезопасном состоянии: парольный вход по SSH, разрешённый root, учётки MySQL с `GRANT ALL`, «забытая» учётка уволенного сотрудника. На нём отрабатываются задачи младшего инженера ИБ в формате рабочих заявок: выдать и отозвать доступы, закрыть находки аудита, выпустить и отозвать сертификат, разобрать алерт.

- Заявки с критериями приёмки: [TICKETS.md](TICKETS.md)
- Установка, проверка и разбор типичных ошибок: [INSTALL.md](INSTALL.md)
- Отчёты по выполненным заявкам: [reports/](reports/), шаблон в [reports/_TEMPLATE.md](reports/_TEMPLATE.md)

## Сценарии

| Блок | Заявки | Что отрабатывается |
|---|---|---|
| A. Доступы и Linux | LAB-01 – LAB-07 | Онбординг и офбординг сотрудника, харденинг SSH, инвентаризация учётных записей, аудит sudo и SUID, компрометация SSH-ключа, перебор паролей |
| B. Сертификаты и PKI | LAB-08 – LAB-13 | Выпуск сертификата и установка в nginx, неполная цепочка, типовые ошибки TLS, отзыв и CRL, форматы ключей, контроль сроков действия |
| C. MySQL и права | LAB-14 – LAB-16 | Аудит прав, приведение к least privilege, заявка на доступ к базе |
| D. Сервисы | LAB-17 – LAB-19 | ACL в Redis, vhost и права в RabbitMQ, роли и защита веток в git-сервисе |
| E. Данные и автоматизация | LAB-20 – LAB-22 | Разбор JSON и YAML, скрипт аудита прав MySQL, `onboard.sh` и `offboard.sh` |
| F. Мониторинг и инциденты | LAB-23 – LAB-25 | Триггеры Zabbix, детект и active response в Wazuh, триаж инцидента |

В конце идёт сквозной сценарий LAB-EXAM: три события одновременно, расстановка приоритетов и общий таймлайн.

## Состав стенда

| Сервис | Что это | Адрес с хоста |
|---|---|---|
| `app-01` | Ubuntu 24.04, sshd и nginx | SSH `localhost:2222`, HTTP `8080`, HTTPS `8443` |
| `ca` | Двухуровневый УЦ на OpenSSL | изнутри контейнера |
| `mysql` | MySQL 8.4, схемы `shop`, `billing`, `analytics` | `localhost:3306` |
| `gitea` | Git-сервис: роли, права на репозитории, deploy keys | `http://localhost:3000` |
| `redis` | Redis 7 с паролем и ACL | `localhost:6379` |
| `rabbitmq` | RabbitMQ с веб-консолью | `http://localhost:15672` |
| `zabbix-web` | Zabbix 7.0, отдельный compose-файл | `http://localhost:8081` |
| Wazuh | SIEM, ставится отдельно по [INSTALL.md](INSTALL.md) | `https://localhost` |

Контейнеры общаются в сети `infosec-lab` по именам. Zabbix и Wazuh подключаются к той же сети.

## Быстрый старт

```bash
cp .env.example .env
docker compose build
docker compose up -d
docker compose exec ca ca-init                              # создать УЦ
docker compose exec ca ca-issue app-01.lab localhost 127.0.0.1
docker compose exec app-01 install-lab-cert app-01.lab      # поставить сертификат в nginx
```

Требования: Docker Engine 24+ и Compose v2, около 3 ГБ памяти и 6 ГБ диска на базовый стенд, ещё 1,5 ГБ на Zabbix и 4–6 ГБ на Wazuh. Linux, macOS или Windows с WSL2.

## Структура репозитория

```
├── docker-compose.yml     основной стенд
├── compose.zabbix.yml     Zabbix
├── compose.gitlab.yml     GitLab CE вместо Gitea
├── .env.example           переменные стенда, копируется в .env
├── app-01/                Dockerfile, entrypoint, конфигурация nginx
├── ca/                    скрипты УЦ (ca-init, ca-issue, ca-revoke) и openssl.cnf
├── mysql/init/            схемы с данными и учётки для аудита прав
├── redis/redis.conf
├── TICKETS.md             25 заявок с критериями приёмки
├── INSTALL.md             установка и проверка
└── reports/               отчёты по выполненным заявкам
```

## Безопасность стенда

Все порты опубликованы только на `127.0.0.1`. Слабые пароли в `.env.example`, парольный SSH и избыточные права в MySQL оставлены намеренно: это материал для заявок по аудиту. Выставлять стенд в сеть нельзя.

Файл `.env` и каталог `ca/pki/` с ключами удостоверяющего центра в репозиторий не попадают, они перечислены в `.gitignore`.
