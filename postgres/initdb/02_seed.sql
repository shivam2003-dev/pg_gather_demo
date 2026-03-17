-- =============================================================================
-- 02_seed.sql  —  Ecommerce schema + realistic data (~300k rows total)
-- Runs automatically on first-boot via docker-entrypoint-initdb.d/
-- =============================================================================

\echo '>>> [02_seed.sql] Creating ecommerce schema and seed data...'

-- Keep everything isolated in its own schema
CREATE SCHEMA IF NOT EXISTS ecommerce;
SET search_path = ecommerce, public;

-- ── users ────────────────────────────────────────────────────────────────────
CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    email         TEXT        NOT NULL UNIQUE,
    username      TEXT        NOT NULL,
    country       TEXT        NOT NULL DEFAULT 'US',
    plan          TEXT        NOT NULL DEFAULT 'free',  -- free | pro | enterprise
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ
);

INSERT INTO users (email, username, country, plan, created_at, last_login_at)
SELECT
    'user_' || i || '@example.com',
    'user_' || i,
    (ARRAY['US','GB','DE','IN','BR','CA','AU','FR','JP','SG'])[1 + (i % 10)],
    (ARRAY['free','free','free','pro','pro','enterprise'])[1 + (i % 6)],
    now() - (random() * interval '2 years'),
    CASE WHEN i % 5 = 0 THEN NULL
         ELSE now() - (random() * interval '30 days') END
FROM generate_series(1, 50000) AS s(i);

\echo '    users: 50 000 rows inserted'

-- ── products ─────────────────────────────────────────────────────────────────
CREATE TABLE products (
    id          SERIAL PRIMARY KEY,
    sku         TEXT           NOT NULL UNIQUE,
    name        TEXT           NOT NULL,
    category    TEXT           NOT NULL,
    price       NUMERIC(10,2)  NOT NULL,
    cost        NUMERIC(10,2)  NOT NULL,
    is_active   BOOLEAN        NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_category ON products (category);
CREATE INDEX idx_products_is_active ON products (is_active);

INSERT INTO products (sku, name, category, price, cost, is_active)
SELECT
    'SKU-' || lpad(i::text, 6, '0'),
    'Product ' || i,
    (ARRAY['Electronics','Clothing','Books','Sports','Home','Beauty','Toys','Food'])[1 + (i % 8)],
    round((random() * 499 + 1)::numeric, 2),
    round((random() * 200 + 1)::numeric, 2),
    i % 20 != 0   -- 5% of products are inactive
FROM generate_series(1, 10000) AS s(i);

\echo '    products: 10 000 rows inserted'

-- ── orders ───────────────────────────────────────────────────────────────────
CREATE TABLE orders (
    id          SERIAL PRIMARY KEY,
    user_id     INT            NOT NULL REFERENCES users(id),
    status      TEXT           NOT NULL DEFAULT 'pending',
                                -- pending | processing | shipped | delivered | cancelled
    total       NUMERIC(12,2)  NOT NULL DEFAULT 0,
    coupon_code TEXT,
    created_at  TIMESTAMPTZ    NOT NULL DEFAULT now(),
    shipped_at  TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ
);

-- Intentionally have an index on user_id (good practice — FKs should be indexed)
CREATE INDEX idx_orders_user_id   ON orders (user_id);
CREATE INDEX idx_orders_status    ON orders (status);
CREATE INDEX idx_orders_created_at ON orders (created_at DESC);

INSERT INTO orders (user_id, status, total, coupon_code, created_at, shipped_at, delivered_at)
SELECT
    1 + (random() * 49999)::int,
    (ARRAY['pending','processing','shipped','shipped','delivered','delivered','delivered','cancelled'])[1 + (i % 8)],
    round((random() * 999 + 10)::numeric, 2),
    CASE WHEN i % 10 = 0 THEN 'SAVE' || (i % 5 * 10) ELSE NULL END,
    now() - (random() * interval '1 year'),
    CASE WHEN i % 8 IN (2,3,4,5,6) THEN now() - (random() * interval '20 days') ELSE NULL END,
    CASE WHEN i % 8 IN (4,5,6)     THEN now() - (random() * interval '10 days') ELSE NULL END
FROM generate_series(1, 100000) AS s(i);

\echo '    orders: 100 000 rows inserted'

-- ── order_items ───────────────────────────────────────────────────────────────
CREATE TABLE order_items (
    id          SERIAL PRIMARY KEY,
    order_id    INT           NOT NULL REFERENCES orders(id),
    product_id  INT           NOT NULL REFERENCES products(id),
    quantity    INT           NOT NULL DEFAULT 1,
    unit_price  NUMERIC(10,2) NOT NULL,
    discount    NUMERIC(5,2)  NOT NULL DEFAULT 0
);

CREATE INDEX idx_order_items_order_id   ON order_items (order_id);
CREATE INDEX idx_order_items_product_id ON order_items (product_id);

-- Each order gets 1–5 items
INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount)
SELECT
    o.id,
    1 + (random() * 9999)::int,
    1 + (random() * 4)::int,
    round((random() * 499 + 1)::numeric, 2),
    round((random() * 20)::numeric, 2)
FROM orders o,
     generate_series(1, 1 + (o.id % 5)) AS s(i);

\echo '    order_items: ~200 000-300 000 rows inserted'

-- ── inventory ─────────────────────────────────────────────────────────────────
CREATE TABLE inventory (
    id           SERIAL PRIMARY KEY,
    product_id   INT  NOT NULL REFERENCES products(id) UNIQUE,
    warehouse    TEXT NOT NULL DEFAULT 'US-EAST',
    qty_on_hand  INT  NOT NULL DEFAULT 0,
    qty_reserved INT  NOT NULL DEFAULT 0,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO inventory (product_id, warehouse, qty_on_hand, qty_reserved)
SELECT
    id,
    (ARRAY['US-EAST','US-WEST','EU-CENTRAL','APAC'])[1 + (id % 4)],
    (random() * 5000)::int,
    (random() * 200)::int
FROM products;

\echo '    inventory: 10 000 rows inserted'

-- ── Collect statistics so the planner has accurate estimates ─────────────────
ANALYZE ecommerce.users;
ANALYZE ecommerce.products;
ANALYZE ecommerce.orders;
ANALYZE ecommerce.order_items;
ANALYZE ecommerce.inventory;

\echo '>>> [02_seed.sql] All seed data inserted and ANALYZE complete.'
