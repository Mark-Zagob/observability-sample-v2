-- ============================================================
-- Database Initialization — Orders DB (Phase 2.1)
-- ============================================================
-- Migration Strategy:
--   Current (Phase 2.1): Single bootstrap script (this file)
--   Future  (Phase 5+):  Flyway-style versioned migrations
--                         V2.1.0__initial_schema.sql → V2.2.0__xxx.sql → ...
--                         with migration_runner.py reading schema_migrations table
-- ============================================================

-- Acquire advisory lock FIRST
-- Note: pg_advisory_lock is DATABASE-SCOPED — no cross-DB collision even with same ID.
-- Hardcoded value is intentional; parameterization adds complexity for a non-existent problem.
SELECT pg_advisory_lock(8675309);

-- ============================================================
-- Tables (6 tables: orders, products, processed_events, 
--          notifications, inventory_log, schema_migrations)
-- ============================================================
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    order_id VARCHAR(8) UNIQUE NOT NULL,
    product_id INTEGER NOT NULL,
    product_name VARCHAR(100),
    quantity INTEGER NOT NULL DEFAULT 1,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    payment_txn_id VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    price DECIMAL(10,2) NOT NULL,
    stock INTEGER DEFAULT 100,
    category VARCHAR(50) DEFAULT 'general'
);

CREATE TABLE IF NOT EXISTS processed_events (
    event_id VARCHAR(36) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    processed_by VARCHAR(50) NOT NULL,
    processed_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (event_id, processed_by)
);

CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    event_id VARCHAR(36) NOT NULL,
    order_id VARCHAR(8) NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    channel VARCHAR(20) DEFAULT 'email',
    status VARCHAR(20) DEFAULT 'sent',
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS inventory_log (
    id SERIAL PRIMARY KEY,
    event_id VARCHAR(36) NOT NULL,
    order_id VARCHAR(8) NOT NULL,
    product_id INTEGER NOT NULL,
    action VARCHAR(20) NOT NULL,
    quantity INTEGER NOT NULL,
    stock_before INTEGER,
    stock_after INTEGER,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS schema_migrations (
    version     VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    checksum    VARCHAR(64),
    applied_at  TIMESTAMP DEFAULT NOW(),
    applied_by  VARCHAR(100) DEFAULT current_user
);

-- ============================================================
-- Indexes
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_processed_events_type ON processed_events(event_type);
CREATE INDEX IF NOT EXISTS idx_notifications_order ON notifications(order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_log_order ON inventory_log(order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_log_product ON inventory_log(product_id);

-- ============================================================
-- Seed data (idempotent)
-- ============================================================
INSERT INTO products (name, price, stock, category) VALUES
    ('Widget A',   29.99, 100, 'widgets'),
    ('Widget B',   49.99,  50, 'widgets'),
    ('Gadget X',   99.99,  30, 'gadgets'),
    ('Gadget Y',  149.99,  20, 'gadgets'),
    ('Premium Z', 299.99,  10, 'premium')
ON CONFLICT (name) DO NOTHING;

INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '2.1.0',
    'Initial schema: orders, products, processed_events, notifications, inventory_log, schema_migrations',
    'init-app-v2.1.0'
)
ON CONFLICT (version) DO NOTHING;

-- ============================================================
-- Application User: DML-only (Least Privilege at DB level)
-- ============================================================
-- Password injected by run-migration.sh via psql -v app_password="..."
-- \gexec: query returns 0 rows → nothing executes; 1 row → executes the SQL.

-- Create role if not exists
SELECT format('CREATE ROLE app_user LOGIN PASSWORD %L', :'app_password') AS cmd
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user')
\gexec

-- Sync password if role already exists (secret = single source of truth)
SELECT format('ALTER ROLE app_user LOGIN PASSWORD %L', :'app_password') AS cmd
WHERE EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user')
\gexec

-- Grant CONNECT + DML-only
SELECT format('GRANT CONNECT ON DATABASE %I TO app_user', current_database()) AS cmd
\gexec

GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- Future-proof: tables created by migration user in future migrations
-- will automatically have DML grants for app_user
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app_user;

-- ============================================================
-- Verification & Lock Release (Single Source of Truth)
-- ============================================================
DO $$
DECLARE
    table_count INTEGER;
    product_count INTEGER;
    schema_version VARCHAR(50);
BEGIN
    SELECT count(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema = 'public';
    
    SELECT count(*) INTO product_count
    FROM products;
    
    SELECT version INTO schema_version
    FROM schema_migrations
    ORDER BY applied_at DESC
    LIMIT 1;
    
    -- Hard fail nếu thiếu table
    IF table_count < 6 THEN
        RAISE EXCEPTION '❌ Verification failed: Expected at least 6 tables, found %.', table_count;
    END IF;

    -- Hard fail nếu seed data bị duplicate hoặc thiếu
    IF product_count != 5 THEN
        RAISE EXCEPTION '❌ Verification failed: Expected exactly 5 products, found %. Possible duplicate seed data!', product_count;
    END IF;

    -- Verify app_user role exists
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app_user') THEN
        RAISE EXCEPTION '❌ Verification failed: app_user role was not created';
    END IF;

    -- Verify app_user has DML
    IF NOT has_table_privilege('app_user', 'orders', 'SELECT') THEN
        RAISE EXCEPTION '❌ Verification failed: app_user lacks SELECT on orders';
    END IF;

    -- Verify app_user does NOT have DDL (most important check!)
    IF has_schema_privilege('app_user', 'public', 'CREATE') THEN
        RAISE EXCEPTION '❌ Verification failed: app_user has CREATE privilege — DDL isolation violated!';
    END IF;
    
    RAISE NOTICE '✅ Migration verified: % tables, % products, schema version: %, app_user: DML-only ✓', 
        table_count, product_count, schema_version;
END $$;

-- Chỉ nhả lock khi mọi thứ (DDL + Seed + Role + Verify) đã thành công 100%
SELECT pg_advisory_unlock(8675309);