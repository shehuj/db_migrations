-- Sample seed data for appdb. Idempotent via ON DUPLICATE KEY UPDATE so the
-- role can be re-run without creating duplicate rows.

INSERT INTO customers (full_name, email) VALUES
  ('Ada Lovelace',      'ada@example.com'),
  ('Alan Turing',       'alan@example.com'),
  ('Grace Hopper',      'grace@example.com'),
  ('Katherine Johnson', 'katherine@example.com')
ON DUPLICATE KEY UPDATE full_name = VALUES(full_name);

INSERT INTO products (sku, name, price_cents) VALUES
  ('SKU-001', 'Mechanical Keyboard', 12900),
  ('SKU-002', 'Noise-Cancelling Headphones', 24900),
  ('SKU-003', 'USB-C Hub', 4900),
  ('SKU-004', '4K Monitor', 39900)
ON DUPLICATE KEY UPDATE name = VALUES(name);

INSERT INTO orders (customer_id, product_id, quantity) VALUES
  (1, 1, 1),
  (1, 3, 2),
  (2, 2, 1),
  (3, 4, 1),
  (4, 1, 1)
ON DUPLICATE KEY UPDATE quantity = VALUES(quantity);
