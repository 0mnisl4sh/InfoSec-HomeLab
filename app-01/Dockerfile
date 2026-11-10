FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Базовый набор боевого сервера + инструменты, которые нужны по вакансии:
# openssl (сертификаты), jq (JSON), mysql-client, redis-tools, git, python3.
RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server sudo rsyslog nginx openssl ca-certificates \
        curl wget vim less iproute2 iputils-ping net-tools procps psmisc \
        jq git python3 python3-pip python3-venv \
        mysql-client redis-tools \
        acl lsof tcpdump dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Каталоги и файлы журналов, без которых не будут работать last/lastb.
# rsyslog на Ubuntu сбрасывает права до пользователя syslog — ему нужен auth.log
# (владелец как на обычной Ubuntu: syslog:adm). imklog в контейнере не работает — выключаем.
RUN mkdir -p /run/sshd /etc/nginx/ssl /var/log/nginx && \
    touch /var/log/auth.log /var/log/btmp /var/log/wtmp && \
    chmod 600 /var/log/btmp && chmod 664 /var/log/wtmp && \
    chown syslog:adm /var/log/auth.log && chmod 640 /var/log/auth.log && \
    sed -i '/imklog/s/^/#/' /etc/rsyslog.conf

COPY nginx/lab.conf /etc/nginx/sites-available/default
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY install-lab-cert.sh /usr/local/bin/install-lab-cert
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/install-lab-cert

# Стенд намеренно стартует в «непричёсанном» состоянии:
# парольный вход разрешён, root-логин разрешён — это первое задание на харденинг.
RUN sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*LogLevel.*/LogLevel INFO/' /etc/ssh/sshd_config && \
    sed -i 's/^#*SyslogFacility.*/SyslogFacility AUTH/' /etc/ssh/sshd_config

EXPOSE 22 80 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
