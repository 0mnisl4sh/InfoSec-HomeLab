-- ВНИМАНИЕ: часть учёток создана НАМЕРЕННО НЕПРАВИЛЬНО.
-- Это материал для задания «аудит прав и least privilege».
-- Не копируй эти GRANT'ы никуда, кроме лабораторного стенда.

-- ========== Как надо ==========

-- Приложение: только то, что реально нужно, и только своя схема
CREATE USER 'app_shop'@'%' IDENTIFIED BY 'app_shop_pw';
GRANT SELECT, INSERT, UPDATE ON shop.* TO 'app_shop'@'%';

-- Аналитик: чтение одной схемы и только из внутренней подсети
CREATE USER 'analyst'@'172.%' IDENTIFIED BY 'analyst_pw';
GRANT SELECT ON analytics.* TO 'analyst'@'172.%';

-- Бэкап: чтение + блокировки, без права менять данные
CREATE USER 'backup'@'172.%' IDENTIFIED BY 'backup_pw';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup'@'172.%';

-- ========== Как не надо (находки для аудита) ==========

-- 1. Отчётный сервис с глобальными правами на всё
CREATE USER 'reporting'@'%' IDENTIFIED BY 'reporting';
GRANT ALL PRIVILEGES ON *.* TO 'reporting'@'%';

-- 2. Старая админская учётка с GRANT OPTION и слабым паролем
CREATE USER 'legacy_admin'@'%' IDENTIFIED BY '123456';
GRANT ALL PRIVILEGES ON *.* TO 'legacy_admin'@'%' WITH GRANT OPTION;
ALTER USER 'legacy_admin'@'%' PASSWORD EXPIRE NEVER;

-- 3. Уволившийся сотрудник: учётка живая, права на боевые данные
CREATE USER 'i.petrov'@'%' IDENTIFIED BY 'petrov2021';
GRANT SELECT, INSERT, UPDATE, DELETE ON shop.* TO 'i.petrov'@'%';
GRANT SELECT ON billing.* TO 'i.petrov'@'%';

-- 4. Мониторинг вообще без пароля
CREATE USER 'monitoring'@'%';
GRANT PROCESS, REPLICATION CLIENT ON *.* TO 'monitoring'@'%';

-- 5. Деплой-учётка с доступом к платёжной схеме, хотя работает только с shop
CREATE USER 'deploy'@'%' IDENTIFIED BY 'deploy_pw';
GRANT ALL PRIVILEGES ON shop.* TO 'deploy'@'%';
GRANT ALL PRIVILEGES ON billing.* TO 'deploy'@'%';

FLUSH PRIVILEGES;
