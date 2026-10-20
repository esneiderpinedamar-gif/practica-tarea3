/* =====================================================================
   PRÁCTICA GUIADA · TAREA 3 · Gestión y Almacenamiento de Datos (203008068)
   Entorno: GitHub Codespaces + MySQL 8.4 + CloudBeaver + Grafana
   Basado en el Anexo 2 (Consultas_SQL) y el Anexo 3 (Database.csv)
   ===================================================================== */

/* ---------- PASO 1 · CARGA MASIVA (en CloudBeaver) ---------- */
SHOW VARIABLES LIKE 'secure_file_priv';          -- esperado: /var/lib/mysql-files/

CREATE DATABASE taller_ventas;
USE taller_ventas;

CREATE TABLE transacciones (
    id_transaccion   INT AUTO_INCREMENT PRIMARY KEY,
    invoice_no       VARCHAR(20),
    stock_code       VARCHAR(20),
    description      VARCHAR(255),
    quantity         INT,
    invoice_date_raw VARCHAR(30),                 -- temporal: la fecha llega como texto
    unit_price       DECIMAL(10,2),
    customer_id      INT NULL,
    country          VARCHAR(100)
) ENGINE = InnoDB;

LOAD DATA INFILE '/var/lib/mysql-files/Anexo_3 - Database.csv'
INTO TABLE transacciones
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'                        -- el Anexo 3 usa fin de línea de Windows
IGNORE 1 LINES
(invoice_no, stock_code, description, quantity, invoice_date_raw, unit_price, @v_customer_id, country)
SET customer_id = IF(@v_customer_id = '', NULL, @v_customer_id);

SHOW WARNINGS;                                    -- esperado: notas por precios 0.001 redondeados a 0.00

ALTER TABLE transacciones ADD COLUMN invoice_date DATETIME;
UPDATE transacciones SET invoice_date = STR_TO_DATE(invoice_date_raw, '%m/%d/%Y %H:%i');

SELECT invoice_date_raw, invoice_date FROM transacciones LIMIT 5;
SELECT COUNT(*) AS sin_convertir FROM transacciones WHERE invoice_date IS NULL;   -- esperado: 0
ALTER TABLE transacciones DROP COLUMN invoice_date_raw;

SELECT COUNT(*) AS total_registros FROM transacciones;                            -- esperado: 541909
SELECT COUNT(*) AS clientes_nulos FROM transacciones WHERE customer_id IS NULL;   -- esperado: 135080


/* ---------- PASO 2 · DIAGNÓSTICO (en la TERMINAL del codespace) ----------
   docker exec -it mysql_clase mysql -uroot -p taller_ventas        (clave: Clase_UNAD_2026)
   En la terminal no hay límite de filas: la medición es exacta.             */
SET profiling = 1;

FLUSH STATUS;
-- 'pager' es un comando del cliente: oculta las filas y deja solo el resumen (va sin comentario en su línea)
pager cat > /dev/null
SELECT * FROM transacciones WHERE customer_id = 17850;                  -- 312 rows in set
nopager
SHOW STATUS LIKE 'Handler_read%next';             -- read_next ≈ 0 · read_rnd_next ≈ 541910
SHOW PROFILES;                                    -- ubicar el Query_ID real
SHOW PROFILE CPU FOR QUERY 2;                     -- cambiar 2 por su Query_ID
EXPLAIN SELECT * FROM transacciones WHERE customer_id = 17850;          -- type ALL

FLUSH STATUS;
pager cat > /dev/null
SELECT * FROM transacciones WHERE country = 'United Kingdom' AND unit_price > 10.00;   -- 22250 rows in set
nopager
SHOW STATUS LIKE 'Handler_read%next';
SHOW PROFILES;
SHOW PROFILE CPU FOR QUERY 6;                     -- cambiar por su Query_ID
EXPLAIN SELECT * FROM transacciones WHERE country = 'United Kingdom' AND unit_price > 10.00;

-- Tiempo en microsegundos sin sumar a mano:
SELECT QUERY_ID, ROUND(SUM(DURATION)*1000000) AS tiempo_us, ROUND(SUM(CPU_USER+CPU_SYSTEM)*1000000) AS cpu_us
FROM information_schema.PROFILING GROUP BY QUERY_ID ORDER BY QUERY_ID;


/* ---------- PASO 3 · ÍNDICES (en la terminal, misma sesión) ---------- */
CREATE INDEX idx_customer ON transacciones(customer_id);
EXPLAIN SELECT * FROM transacciones WHERE customer_id = 17850;          -- type ref
FLUSH STATUS;
pager cat > /dev/null
SELECT * FROM transacciones WHERE customer_id = 17850;
nopager
SHOW STATUS LIKE 'Handler_read%';                 -- key 1 · next ≈ 312 · rnd_next 0
SHOW PROFILES;

CREATE INDEX idx_country_price ON transacciones(country, unit_price);  -- igualdad primero, rango después
EXPLAIN SELECT * FROM transacciones WHERE country = 'United Kingdom' AND unit_price > 10.00;   -- type range
FLUSH STATUS;
pager cat > /dev/null
SELECT * FROM transacciones WHERE country = 'United Kingdom' AND unit_price > 10.00;
nopager
SHOW STATUS LIKE 'Handler_read%';                 -- key 1 · next ≈ 22250 · rnd_next 0
SHOW PROFILES;
-- Si EXPLAIN no usa el índice:  ANALYZE TABLE transacciones;  y repetir.


/* ---------- PASO 4 · GRAFANA (preparación en la terminal) ---------- */
CREATE USER 'grafana_ro'@'%' IDENTIFIED BY 'Lectura_2026';
GRANT SELECT ON taller_ventas.* TO 'grafana_ro'@'%';
SET GLOBAL information_schema_stats_expiry = 0;   -- el panel de MB se actualiza sin esperar 24 h

-- Data Source en Grafana: Host URL  mysql:3306 · Database taller_ventas · User grafana_ro
-- Panel 1 (Stat):   SELECT NOW() as time, COUNT(*) as "Total Registros" FROM transacciones;
-- Panel 2 (Gauge):  SELECT NOW() as time, ROUND(((data_length + index_length) / 1024 / 1024), 2) AS "Tamaño Total Base Datos (MB)"
--                   FROM information_schema.TABLES WHERE table_schema = "taller_ventas" AND table_name = "transacciones";

-- Prueba de dinamismo (y limpieza al final)
INSERT INTO transacciones (invoice_no, stock_code, description, quantity, unit_price, customer_id, country, invoice_date)
SELECT 'DEMO', stock_code, description, quantity, unit_price, customer_id, country, NOW() FROM transacciones LIMIT 1000;
DELETE FROM transacciones WHERE invoice_no = 'DEMO';
