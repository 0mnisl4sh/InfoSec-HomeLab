-- Три схемы с разным уровнем чувствительности данных.
-- shop      — рабочие данные приложения
-- billing   — платёжка, сюда доступ дают единицам
-- analytics — логи событий, здесь тренируемся в разборе активности

CREATE DATABASE IF NOT EXISTS shop      CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS billing   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE DATABASE IF NOT EXISTS analytics CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

USE shop;

CREATE TABLE customers (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  email       VARCHAR(190) NOT NULL UNIQUE,
  full_name   VARCHAR(190) NOT NULL,
  country     CHAR(2)      NOT NULL DEFAULT 'RU',
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  customer_id  INT NOT NULL,
  status       ENUM('new','paid','shipped','cancelled') NOT NULL DEFAULT 'new',
  total        DECIMAL(10,2) NOT NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id)
);

CREATE TABLE order_items (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  order_id  INT NOT NULL,
  sku       VARCHAR(32) NOT NULL,
  qty       INT NOT NULL,
  price     DECIMAL(10,2) NOT NULL,
  CONSTRAINT fk_items_order FOREIGN KEY (order_id) REFERENCES orders(id)
);

INSERT INTO customers (email, full_name, country) VALUES
  ('a.ivanov@example.com',  'Иванов Алексей',   'RU'),
  ('m.petrova@example.com', 'Петрова Мария',    'RU'),
  ('d.smirnov@example.com', 'Смирнов Дмитрий',  'RU'),
  ('k.orlova@example.com',  'Орлова Ксения',    'RU'),
  ('s.wagner@example.com',  'Sabine Wagner',    'DE'),
  ('j.kowalski@example.com','Jan Kowalski',     'PL'),
  ('t.nguyen@example.com',  'Thanh Nguyen',     'VN'),
  ('e.volkov@example.com',  'Волков Егор',      'RU');

INSERT INTO orders (customer_id, status, total) VALUES
  (1,'paid',4990.00), (1,'shipped',1250.50), (2,'new',780.00),
  (3,'paid',15300.00), (3,'cancelled',450.00), (4,'shipped',2300.00),
  (5,'paid',99.99),   (6,'new',3120.75),     (7,'paid',640.00),
  (8,'shipped',8800.00), (2,'paid',1990.00), (4,'new',560.40);

INSERT INTO order_items (order_id, sku, qty, price) VALUES
  (1,'KB-101',1,3490.00), (1,'MS-204',1,1500.00),
  (2,'CBL-USB-C',5,250.10), (3,'HDD-1TB',1,780.00),
  (4,'SRV-RAM-32',2,7650.00), (6,'MON-24',1,2300.00),
  (7,'STK-01',1,99.99),   (8,'NAS-BAY4',1,3120.75),
  (9,'CBL-HDMI',4,160.00),(10,'GPU-LITE',1,8800.00),
  (11,'KB-101',1,1990.00),(12,'MS-204',1,560.40);

USE billing;

CREATE TABLE invoices (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  order_id   INT NOT NULL,
  amount     DECIMAL(10,2) NOT NULL,
  paid       TINYINT(1) NOT NULL DEFAULT 0,
  issued_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Условно чувствительная таблица: пригодится в разговоре про least privilege
CREATE TABLE payment_methods (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  customer_id  INT NOT NULL,
  kind         ENUM('card','sbp','invoice') NOT NULL,
  last4        CHAR(4) NULL,
  added_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO invoices (order_id, amount, paid) VALUES
  (1,4990.00,1), (2,1250.50,1), (4,15300.00,1), (7,99.99,1),
  (9,640.00,1),  (10,8800.00,0), (11,1990.00,1), (3,780.00,0);

INSERT INTO payment_methods (customer_id, kind, last4) VALUES
  (1,'card','4242'), (2,'sbp',NULL), (3,'card','1881'),
  (4,'invoice',NULL), (5,'card','0007'), (8,'card','3310');

USE analytics;

-- Похоже на поток событий из веб-приложения: есть IP, есть неудачные входы.
CREATE TABLE events (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  customer_id  INT NULL,
  event        VARCHAR(64) NOT NULL,
  ip           VARCHAR(45) NOT NULL,
  user_agent   VARCHAR(255) NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO events (customer_id, event, ip, user_agent, created_at) VALUES
  (1,'login_ok',      '203.0.113.15','Mozilla/5.0', NOW() - INTERVAL 5 DAY),
  (1,'order_created', '203.0.113.15','Mozilla/5.0', NOW() - INTERVAL 5 DAY),
  (2,'login_failed',  '198.51.100.7','curl/8.5.0',  NOW() - INTERVAL 2 DAY),
  (2,'login_failed',  '198.51.100.7','curl/8.5.0',  NOW() - INTERVAL 2 DAY),
  (2,'login_failed',  '198.51.100.7','curl/8.5.0',  NOW() - INTERVAL 2 DAY),
  (2,'login_failed',  '198.51.100.7','curl/8.5.0',  NOW() - INTERVAL 2 DAY),
  (2,'login_ok',      '198.51.100.7','curl/8.5.0',  NOW() - INTERVAL 2 DAY),
  (NULL,'login_failed','192.0.2.44', 'python-requests/2.31', NOW() - INTERVAL 1 DAY),
  (NULL,'login_failed','192.0.2.44', 'python-requests/2.31', NOW() - INTERVAL 1 DAY),
  (NULL,'login_failed','192.0.2.44', 'python-requests/2.31', NOW() - INTERVAL 1 DAY),
  (3,'login_ok',      '203.0.113.99','Mozilla/5.0', NOW() - INTERVAL 3 HOUR),
  (3,'password_reset','203.0.113.99','Mozilla/5.0', NOW() - INTERVAL 3 HOUR),
  (4,'login_ok',      '203.0.113.31','Mozilla/5.0', NOW() - INTERVAL 1 HOUR),
  (8,'export_report', '10.10.0.5',   'Mozilla/5.0', NOW() - INTERVAL 30 MINUTE);
