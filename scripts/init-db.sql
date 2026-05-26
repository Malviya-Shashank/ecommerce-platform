-- E-Commerce Platform Local Database Initialization
-- Creates databases and seeds initial mock data for immediate developer testing.

-- 1. Create databases for all services
CREATE DATABASE user_service;
CREATE DATABASE order_service;
CREATE DATABASE product_service;
CREATE DATABASE payment_service;
CREATE DATABASE notification_service;

-- 2. Connect to product_service and seed catalog items
\c product_service;

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    category VARCHAR(100),
    stock_quantity INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    image_url TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO products (name, description, price, sku, category, stock_quantity, image_url) VALUES
('QuantumX Pro Laptop', '16-inch stellar display, 32GB RAM, 1TB SSD, next-gen GPU for developers and creators.', 1899.99, 'QTYX-PRO-16', 'Electronics', 50, 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=500'),
('Nebula Mechanical Keyboard', 'Gasket-mounted hot-swappable tactile keyboard with stunning RGB and custom switches.', 149.50, 'NEBULA-MECH-RGB', 'Accessories', 120, 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=500'),
('Apex Wireless Mouse', 'Ergonomic ultra-lightweight wireless mouse with 26K DPI sensor and 80-hour battery life.', 89.99, 'APEX-WIRELESS-M', 'Accessories', 200, 'https://images.unsplash.com/photo-1615663245857-ac93bb7c39e7?w=500'),
('Aurora Curved Monitor', '34-inch ultrawide 1440p mini-LED curved gaming monitor with 165Hz refresh rate.', 549.99, 'AURORA-CURVED-34', 'Electronics', 35, 'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?w=500'),
('EchoSound Noise-Cancelling Headphones', 'Active noise-cancelling over-ear headphones with high-fidelity spatial audio.', 299.00, 'ECHOSOUND-ANC-H', 'Audio', 80, 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=500')
ON CONFLICT (sku) DO NOTHING;

-- 3. Connect to user_service and seed initial test accounts
\c user_service;

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(255),
    hashed_password VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO users (email, username, full_name, hashed_password, is_verified) VALUES
('alex.dev@example.com', 'alex_dev', 'Alex Developer', 'dda69783f28fdf6f1c5a83e8400f2472e9300887d1dffffe12a07b92a3d0aa25', true),
('sarah.manager@example.com', 'sarah_m', 'Sarah Manager', 'f3d63c9346b22494e1dd0aca73a12ed26270ad605bd8ba9824a404334582cf55', true)
ON CONFLICT (email) DO NOTHING;
