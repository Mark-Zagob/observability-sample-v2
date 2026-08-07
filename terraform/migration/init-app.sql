-- ============================================================
-- Database Initialization — Orders DB (Phase 2.1)
-- ============================================================
-- Idempotent: Safe to run multiple times (CREATE IF NOT EXISTS)
-- Production-Grade: Advisory lock, indexes, seed data, verification
-- Source: Evolved from on-premises/applications-vm/applications/init.sql
-- ============================================================

-- Advisory lock: prevents concurrent DDL race conditions
-- (e.g., if multiple migration tasks run simultaneously)
SELECT pg_advisory_lock(8675309);

-- ============================================================
-- Tables
-- ============================================================

-- Orders table
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

-- Products table (source of truth)
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,  -- natural key: prevents duplicate seed data
    price DECIMAL(10,2) NOT NULL,
    stock INTEGER DEFAULT 100,
    category VARCHAR(50) DEFAULT 'general'
);

-- Processed events — idempotency tracking for Kafka workers
CREATE TABLE IF NOT EXISTS processed_events (
    event_id VARCHAR(36) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    processed_by VARCHAR(50) NOT NULL,
    processed_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (event_id, processed_by)
);

-- Notifications — audit log for sent notifications
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    event_id VARCHAR(36) NOT NULL,
    order_id VARCHAR(8) NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    channel VARCHAR(20) DEFAULT 'email',
    status VARCHAR(20) DEFAULT 'sent',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Inventory log — audit trail for stock changes
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

-- Schema version tracking — production-grade migration history
-- Pattern: same as Flyway's flyway_schema_history / Liquibase's DATABASECHANGELOG
CREATE TABLE IF NOT EXISTS schema_migrations (
    version     VARCHAR(50) PRIMARY KEY,
    description TEXT NOT NULL,
    checksum    VARCHAR(64),                          -- SHA-256 of migration SQL (detect tampering)
    applied_at  TIMESTAMP DEFAULT NOW(),
    applied_by  VARCHAR(100) DEFAULT current_user     -- audit: who ran this migration
);

-- ============================================================
-- Indexes (all idempotent via IF NOT EXISTS)
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_processed_events_type ON processed_events(event_type);
CREATE INDEX IF NOT EXISTS idx_notifications_order ON notifications(order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_log_order ON inventory_log(order_id);
CREATE INDEX IF NOT EXISTS idx_inventory_log_product ON inventory_log(product_id);

-- ============================================================
-- Seed data (idempotent via UNIQUE(name) constraint)
-- ============================================================
INSERT INTO products (name, price, stock, category) VALUES
    ('Widget A',   29.99, 100, 'widgets'),
    ('Widget B',   49.99,  50, 'widgets'),
    ('Gadget X',   99.99,  30, 'gadgets'),
    ('Gadget Y',  149.99,  20, 'gadgets'),
    ('Premium Z', 299.99,  10, 'premium')
ON CONFLICT (name) DO NOTHING;

-- Record schema version (idempotent)
INSERT INTO schema_migrations (version, description, checksum)
VALUES (
    '2.1.0',
    'Initial schema: orders, products, processed_events, notifications, inventory_log, schema_migrations',
    'init-app-v2.1.0'  -- In production: SHA-256 of this file
)
ON CONFLICT (version) DO NOTHING;

-- Release advisory lock
SELECT pg_advisory_unlock(8675309);

-- ============================================================
-- Verification (RAISE NOTICE → visible in CloudWatch Logs)
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

    -- Exact count: detect duplicates from non-idempotent seed runs
    IF product_count != 5 THEN
        RAISE WARNING '⚠️ Expected 5 products, found %. Possible duplicate seed data!', product_count;
    END IF;

    RAISE NOTICE '✅ Migration verified: % tables, % products, schema version: %', table_count, product_count, schema_version;
END $$;
