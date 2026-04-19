-- ============================================================
-- FMRZ BILLING SYSTEM — WEB LAYER ADDITIONS
-- Run this AFTER the main Billing.sql
-- ============================================================

-- ------------------------------------------------------------
-- APP_USER — login accounts for admin and customer users
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_user (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name     VARCHAR(255) NOT NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'customer',
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- Link customer profiles to login accounts
-- user_id is nullable: not all customers need an account
-- (admins can create customers without giving them login access)
-- ------------------------------------------------------------
ALTER TABLE customer ADD COLUMN IF NOT EXISTS user_id INTEGER REFERENCES app_user(id) UNIQUE;

-- Index for faster lookups when customer logs in
CREATE INDEX IF NOT EXISTS idx_customer_user_id ON customer(user_id);

-- ------------------------------------------------------------
-- DEFAULT ADMIN ACCOUNT
-- Username: admin | Password: admin
-- BCrypt hashed — never store plain text passwords!
-- Change this password before going to production.
--
-- The bcrypt hash below is a standard $2a$ hash for "admin"
-- ------------------------------------------------------------
INSERT INTO app_user (username, password_hash, full_name, role)
VALUES (
    'admin',
    '$2a$10$8K1p/90Gv.2ouWn.yYmhu.7IQWOZebhzOGS4shf.A6yYpG75T69mG',
    'System Admin',
    'admin'
) ON CONFLICT (username) DO NOTHING;
-- ON CONFLICT: skip if admin already exists (safe to re-run)
