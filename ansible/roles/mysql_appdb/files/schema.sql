-- Application schema for the appdb database. Idempotent (IF NOT EXISTS) so the
-- role can be re-run safely against either the dev or the prod database.

SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS customers (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  full_name   VARCHAR(120)  NOT NULL,
  email       VARCHAR(160)  NOT NULL UNIQUE,
  created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS products (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  sku         VARCHAR(40)   NOT NULL UNIQUE,
  name        VARCHAR(160)  NOT NULL,
  price_cents INT           NOT NULL
) ENGINE = InnoDB;

CREATE TABLE IF NOT EXISTS orders (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  customer_id   INT NOT NULL,
  product_id    INT NOT NULL,
  quantity      INT NOT NULL DEFAULT 1,
  ordered_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers (id),
  CONSTRAINT fk_orders_product  FOREIGN KEY (product_id)  REFERENCES products (id)
) ENGINE = InnoDB;

SET FOREIGN_KEY_CHECKS = 1;
