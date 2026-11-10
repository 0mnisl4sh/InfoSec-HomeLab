# Установка и работа со стендом

## 1. Требования

- Docker Engine 24+ и Docker Compose v2 — проверь: `docker compose version`
- Linux, macOS или Windows с WSL2
- Базовый стенд: ~3 ГБ RAM, ~6 ГБ диска. С Zabbix +1.5 ГБ, с Wazuh ещё +4–6 ГБ
- Свободные порты на хосте: 2222, 2223, 3000, 3306, 5672, 6379, 8080, 8443, 15672

Скрипты в `ca/bin/` и `app-01/` делать исполняемыми не нужно: `chmod +x` прописан
внутри Dockerfile.

**Windows + WSL2: держи стенд внутри файловой системы WSL, а не на диске `C:`.**
Если запускать Docker из `/mnt/c/...`, всё работает заметно медленнее, а `chmod`
на файлах NTFS молча не действует — у приватных ключей УЦ в `ca/pki/` будут неправильные
права. Скопируй стенд в домашний каталог WSL и работай там:

```bash
mkdir -p ~/lab
cp -r "/mnt/c/Users/Pyotr/Desktop/appsec/infosec-homelab" ~/lab/
cd ~/lab/infosec-homelab
```

Копия на рабочем столе остаётся «эталоном»: если что-то сломал до неузнаваемости,
удали `~/lab/infosec-homelab` (`docker compose down -v` перед этим) и скопируй заново.

## 2. Установка

```bash
cd infosec-homelab

# Пароли, FQDN и твой публичный ключ
cp .env.example .env
echo "LAB_ADMIN_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)" >> .env   # по желанию

docker compose build
docker compose up -d
docker compose ps
```

Первый запуск MySQL занимает 30–60 секунд: он прогоняет скрипты из `mysql/init/`.
Дождись статуса `healthy`.

## 3. Проверка, что всё работает

```bash
# SSH на app-01 (пароль labadmin, если не подложил ключ)
ssh -p 2222 labadmin@localhost

# HTTP и HTTPS (сертификат пока самоподписанный — предупреждение ожидаемо)
curl -s  http://localhost:8080/health
curl -sk https://localhost:8443/health

# MySQL
docker compose exec mysql mysql -uroot -prootpass -e "SHOW DATABASES;"

# Redis
docker compose exec redis redis-cli -a redispass PING

# RabbitMQ
docker compose exec rabbitmq rabbitmqctl list_users
```

Админ Gitea создаётся один раз командой:

```bash
docker compose exec -u git gitea gitea admin user create \
  --username labadmin --password 'LabAdmin123!' \
  --email labadmin@example.com --admin
```

Веб-интерфейсы: Gitea `http://localhost:3000`, RabbitMQ `http://localhost:15672`.

## 4. Удостоверяющий центр

В контейнере `ca` три команды: `ca-init`, `ca-issue`, `ca-revoke`.
Материал УЦ хранится на хосте в `ca/pki/`, выпущенные сертификаты — в `ca/pki/issued/`.
Этот каталог примонтирован в `app-01` как `/etc/nginx/certs` в режиме только чтения.

```bash
# Создать корневой и промежуточный УЦ (один раз)
docker compose exec ca ca-init

# Выпустить сертификат
docker compose exec ca ca-issue app-01.lab localhost 127.0.0.1

# Поставить в nginx и перечитать конфиг
docker compose exec app-01 install-lab-cert app-01.lab

# Посмотреть, что реально отдаёт сервер
docker compose exec app-01 bash -c \
  "openssl s_client -connect localhost:443 -servername app-01.lab </dev/null 2>/dev/null \
   | openssl x509 -noout -subject -issuer -dates"

# Цепочка с точки зрения хоста
openssl s_client -connect localhost:8443 -servername app-01.lab -showcerts </dev/null
```

Отзыв и CRL:

```bash
docker compose exec ca ca-revoke app-01.lab keyCompromise
docker compose exec ca cat /pki/intermediate/index.txt      # V = действует, R = отозван
docker compose exec ca openssl crl \
  -in /pki/intermediate/crl/intermediate.crl.pem -noout -text
```

База УЦ — это `index.txt` и файл `serial`, из которого берутся последовательные
номера `1000`, `1001` и дальше. Публичные УЦ обязаны выдавать случайные серийники;
в конфиге за это отвечает опция `rand_serial`.

Какой файл куда кладётся:

| Файл | Что внутри | Куда идёт |
|---|---|---|
| `privkey.pem` | приватный ключ | `ssl_certificate_key` в nginx |
| `cert.pem` | только сертификат сервера | сам по себе почти нигде не используется |
| `fullchain.pem` | сертификат + промежуточный | `ssl_certificate` в nginx |
| `chain.pem` | промежуточный + корневой | для `openssl verify` и раздачи клиентам |

## 5. Zabbix

```bash
docker compose -f compose.zabbix.yml up -d
docker compose -f compose.zabbix.yml logs -f zabbix-server
```

Веб-интерфейс: `http://localhost:8081`, вход `Admin / zabbix` — пароль поменяй сразу.

В интерфейсе: *Data collection → Hosts → Zabbix server* — в интерфейсе агента поставь
DNS-имя `zabbix-agent` вместо `127.0.0.1`, иначе сервер не достучится до агента
в соседнем контейнере.

Хороший первый триггер — истечение сертификата:
элемент данных `web.certificate.get[app-01.lab,443]`.

## 6. Wazuh

Ставится отдельно, официальным compose из репозитория проекта.

```bash
sudo sysctl -w vm.max_map_count=262144

git clone https://github.com/wazuh/wazuh-docker.git
cd wazuh-docker
git tag | tail -5            # выбери последний стабильный тег
git checkout v4.14.8          # актуальный стабильный на 24.09.2026 — сверь с выводом git tag
cd single-node

docker compose -f generate-indexer-certs.yml run --rm generator
docker compose up -d
```

Дашборд: `https://localhost`, вход `admin / SecretPassword` (смени по инструкции в репозитории).

Подключить `app-01` как агента:

```bash
# 1. Подсадить менеджера Wazuh в сеть стенда
docker ps --format '{{.Names}}' | grep wazuh.manager
docker network connect infosec-lab <имя-контейнера-менеджера>

# 2. Установить агент внутри app-01
docker compose exec app-01 bash
apt-get update && apt-get install -y curl gnupg apt-transport-https
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | \
  gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
  > /etc/apt/sources.list.d/wazuh.list
apt-get update
WAZUH_MANAGER="<имя-контейнера-менеджера>" apt-get install -y wazuh-agent
/var/ossec/bin/wazuh-control start
```

В `app-01` работает rsyslog, поэтому `/var/log/auth.log` наполняется и агенту есть что читать.
Дальше бери сценарии из Proof of Concept guide в документации Wazuh: детект брутфорса,
контроль целостности файлов, активное реагирование с блокировкой IP.

## 7. GitLab CE вместо Gitea

Для заданий про роли и защищённые ветки в GitLab подними его:

```bash
docker compose -f compose.gitlab.yml up -d
docker compose -f compose.gitlab.yml logs -f gitlab     # стартует 5–10 минут
```

`http://localhost:8929`, логин `root`, пароль из `.env` (`GITLAB_ROOT_PASSWORD`).
Нужно минимум 4 ГБ свободной памяти; Gitea на это время можно остановить:
`docker compose stop gitea`.

## 8. Управление стендом

```bash
docker compose ps                     # статус
docker compose logs -f app-01         # логи сервиса
docker compose exec app-01 bash       # шелл внутрь
docker compose restart app-01         # перезапуск без потери состояния
docker compose stop                   # остановить, сохранив контейнеры
docker compose start                  # поднять обратно
docker compose down                   # удалить контейнеры (тома остаются)
docker compose down -v                # снести всё вместе с данными
```

**Про состояние.** Пользователи, которых ты создаёшь внутри `app-01`, живут в файловой
системе контейнера. `restart` и `stop/start` их сохраняют, а `down` и пересборка образа — нет.
Зафиксировать настроенный сервер: `docker commit app-01 my-app-01:configured`.
Данные MySQL, Gitea, RabbitMQ и материал УЦ лежат в томах и на хосте — они переживают `down`.

## 9. Если что-то не поднялось

| Симптом | Причина и что делать |
|---|---|
| `port is already allocated` | порт занят другим процессом — поменяй левую часть в `ports:` |
| `app-01` уходит в цикл рестарта | `docker compose logs app-01`; чаще всего сломан `nginx -t` после правки конфига |
| MySQL не применил init-скрипты | том создан раньше: `docker compose down -v && docker compose up -d` |
| `ca-issue` пишет, что УЦ не инициализирован | сначала `docker compose exec ca ca-init` |
| Zabbix-веб отдаёт ошибку БД | сервер ещё накатывает схему, подожди пару минут |
| Wazuh-индексер падает | не выставлен `vm.max_map_count=262144` на хосте |
| Не заходит по SSH после LAB-02 | проверяй `sshd -t` **до** перезапуска; починить можно через `docker compose exec app-01 bash` |
