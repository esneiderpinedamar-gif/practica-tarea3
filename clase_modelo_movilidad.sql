/* =====================================================================
   CLASE MODELO · TAREA 3 · GESTIÓN Y ALMACENAMIENTO DE DATOS (203008068)
   Caso de ejemplo: "Movilidad Caribe" (datos SINTÉTICOS, 500.000 filas)
   Docente: Esneider Pineda · ECBTI-UNAD

   ESTE NO ES EL EJERCICIO DE LOS ESTUDIANTES. Es un caso distinto que
   sigue, fase por fase, la misma lógica del Anexo 2 – Consultas_SQL:
     A1 Carga masiva  ->  A2 Diagnóstico  ->  A3 Índices  ->  A4 Grafana
   Los estudiantes aplican el método a taller_ventas / transacciones
   con el Anexo 3 – Database.csv.

   Entorno: GitHub Codespaces (MySQL 8.4 + CloudBeaver + Grafana).
   El archivo movilidad_caribe.csv debe estar en la carpeta datos/.
   ===================================================================== */


/* =====================================================================
   FASE 1 · CARGA MASIVA  (equivale al Anexo 2, sección A1)
   Se ejecuta en CloudBeaver (puerto 8978).
   ===================================================================== */

-- 1.0 ¿Desde qué carpeta deja leer archivos el servidor?
SHOW VARIABLES LIKE 'secure_file_priv';          -- esperado: /var/lib/mysql-files/

-- 1.1 Base de datos y tabla
DROP DATABASE IF EXISTS demo_movilidad;          -- permite repetir la demostración desde cero
CREATE DATABASE demo_movilidad CHARACTER SET utf8mb4;
USE demo_movilidad;

CREATE TABLE validaciones (
    id_validacion   INT AUTO_INCREMENT PRIMARY KEY,  -- clave sustituta; InnoDB ordena la tabla por ella
    codigo_viaje    VARCHAR(12),                     -- 'MC00000001'
    estacion        VARCHAR(60),                     -- 20 estaciones distintas
    ruta            VARCHAR(4),                      -- 'R12', 'A3'
    tipo_pasajero   VARCHAR(20),                     -- General, Estudiante, Adulto mayor
    fecha_hora_raw  VARCHAR(25),                     -- TEMPORAL: la fecha llega como texto
    tarifa          DECIMAL(8,2),                    -- dinero: DECIMAL es exacto
    tarjeta_id      INT NULL,                        -- NULL = pago con QR o efectivo
    observacion     VARCHAR(120) NULL
) ENGINE = InnoDB;                                   -- motor transaccional, bloqueo por fila, Buffer Pool

-- 1.2 Carga masiva con LOAD DATA INFILE
LOAD DATA INFILE '/var/lib/mysql-files/movilidad_caribe.csv'
INTO TABLE validaciones
CHARACTER SET utf8mb4                                -- el archivo trae tildes (Estación Malecón)
FIELDS TERMINATED BY ','
ENCLOSED BY '"'                                      -- textos con coma vienen entre comillas
LINES TERMINATED BY '\n'                             -- ESTE archivo usa fin de línea Linux (\n)
IGNORE 1 LINES                                       -- salta el encabezado
(codigo_viaje, estacion, ruta, tipo_pasajero, fecha_hora_raw, tarifa, @v_tarjeta, @v_obs)
SET tarjeta_id  = IF(@v_tarjeta = '', NULL, @v_tarjeta),   -- vacío -> NULL real
    observacion = IF(@v_obs = '', NULL, @v_obs);

SHOW WARNINGS;                                       -- esperado en este caso: sin advertencias

-- 1.3 Transformar la fecha de texto a DATETIME
ALTER TABLE validaciones ADD COLUMN fecha_hora DATETIME;

UPDATE validaciones
SET fecha_hora = STR_TO_DATE(fecha_hora_raw, '%d/%m/%Y %H:%i:%s');   -- dd/mm/aaaa hh:mm:ss

-- 1.4 Verificar ANTES de borrar la columna de texto
SELECT fecha_hora_raw, fecha_hora FROM validaciones LIMIT 5;
SELECT COUNT(*) AS fechas_sin_convertir FROM validaciones WHERE fecha_hora IS NULL;   -- esperado: 0

ALTER TABLE validaciones DROP COLUMN fecha_hora_raw;   -- solo si el conteo anterior dio 0

-- 1.5 ENTREGABLE DE LA FASE
SELECT COUNT(*) AS total_registros FROM validaciones;                            -- esperado: 500000
SELECT COUNT(*) AS pagos_sin_tarjeta FROM validaciones WHERE tarjeta_id IS NULL;  -- esperado: 109759


/* =====================================================================
   FASE 2 · DIAGNÓSTICO INICIAL SIN ÍNDICES  (equivale al Anexo 2, sección A2)
   Se ejecuta en la TERMINAL del codespace:
     docker exec -it mysql_clase mysql -uroot -p demo_movilidad
   Clave: Clase_UNAD_2026
   ===================================================================== */

-- Activa el perfilador de la sesión (aparece un aviso de "obsoleto": es normal)
SET profiling = 1;

-- ---------- CONSULTA MODELO 1 · viajes de una tarjeta (equivale a "un cliente") ----------
-- Contadores de la sesión en cero:
FLUSH STATUS;
-- Oculta las filas en pantalla (el motor las procesa igual):
pager cat > /dev/null
SELECT * FROM validaciones WHERE tarjeta_id = 1077239;
-- Esperado: 241 rows in set
nopager
SHOW STATUS LIKE 'Handler_read%';
-- Esperado sin índice: Handler_read_rnd_next ≈ 500001 · Handler_read_next = 0 · Handler_read_key = 0
SHOW PROFILES;
-- Busque en la lista el Query_ID de su SELECT (NO suponga que es 1 o 2) y úselo aquí:
SHOW PROFILE CPU FOR QUERY 2;
EXPLAIN SELECT * FROM validaciones WHERE tarjeta_id = 1077239\G
-- Esperado: type: ALL · key: NULL

-- ---------- CONSULTA MODELO 2 · una estación en una semana (igualdad + rango) ----------
FLUSH STATUS;
pager cat > /dev/null
SELECT * FROM validaciones WHERE estacion = 'Portal Norte' AND fecha_hora >= '2026-03-02' AND fecha_hora < '2026-03-09';
-- Esperado: 3448 rows in set
nopager
SHOW STATUS LIKE 'Handler_read%';
-- Esperado sin índice: Handler_read_rnd_next ≈ 500001 · Handler_read_next = 0
SHOW PROFILES;
-- Use el Query_ID de este SELECT:
SHOW PROFILE CPU FOR QUERY 7;
EXPLAIN SELECT * FROM validaciones WHERE estacion = 'Portal Norte' AND fecha_hora >= '2026-03-02' AND fecha_hora < '2026-03-09'\G
-- Esperado: type: ALL · key: NULL

-- Tiempo total de cada sentencia en MICROSEGUNDOS (para la tabla del informe):
SELECT QUERY_ID, ROUND(SUM(DURATION) * 1000000) AS tiempo_us FROM information_schema.PROFILING GROUP BY QUERY_ID ORDER BY QUERY_ID;

-- Rigor: repita cada consulta 3 veces y reporte la mediana.


/* =====================================================================
   FASE 3 · ESTRATEGIA DE INDEXACIÓN  (equivale al Anexo 2, sección A3)
   Misma sesión de la terminal.
   ===================================================================== */

-- Índice simple: la consulta 1 filtra por igualdad en una sola columna
CREATE INDEX idx_tarjeta ON validaciones (tarjeta_id);

-- Índice compuesto: igualdad primero (estacion), rango después (fecha_hora)
CREATE INDEX idx_estacion_fecha ON validaciones (estacion, fecha_hora);

-- Estadísticas frescas para el optimizador y para el tamaño en MB:
ANALYZE TABLE validaciones;
SHOW INDEX FROM validaciones;

-- Repetir EXACTAMENTE el protocolo de la Fase 2:
FLUSH STATUS;
pager cat > /dev/null
SELECT * FROM validaciones WHERE tarjeta_id = 1077239;
nopager
SHOW STATUS LIKE 'Handler_read%';
-- Esperado: Handler_read_key = 1 · Handler_read_next ≈ 241 · Handler_read_rnd_next = 0
SHOW PROFILES;
EXPLAIN SELECT * FROM validaciones WHERE tarjeta_id = 1077239\G
-- Esperado: type: ref · key: idx_tarjeta

FLUSH STATUS;
pager cat > /dev/null
SELECT * FROM validaciones WHERE estacion = 'Portal Norte' AND fecha_hora >= '2026-03-02' AND fecha_hora < '2026-03-09';
nopager
SHOW STATUS LIKE 'Handler_read%';
-- Esperado: Handler_read_key = 1 · Handler_read_next ≈ 3448 · Handler_read_rnd_next = 0
SHOW PROFILES;
EXPLAIN SELECT * FROM validaciones WHERE estacion = 'Portal Norte' AND fecha_hora >= '2026-03-02' AND fecha_hora < '2026-03-09'\G
-- Esperado: type: range · key: idx_estacion_fecha

-- Cálculos para el informe:
--   % mejora en tiempo   = (T_antes - T_despues) / T_antes * 100
--   % reducción de filas = (Filas_antes - Filas_despues) / Filas_antes * 100


/* =====================================================================
   FASE 4 · MONITOREO CON GRAFANA  (equivale al Anexo 2, sección A4)
   Primero en la terminal; luego en Grafana (puerto 3000).
   ===================================================================== */

-- Usuario de SOLO LECTURA para Grafana (nunca conectar Grafana con root)
CREATE USER 'grafana_demo'@'%' IDENTIFIED BY 'Lectura_Demo_2026';
GRANT SELECT ON demo_movilidad.* TO 'grafana_demo'@'%';

-- MySQL guarda en caché las estadísticas de tamaño hasta 24 h; para la clase, sin caché:
SET GLOBAL information_schema_stats_expiry = 0;

-- Data Source en Grafana:
--   Host URL: mysql:3306 · Database: demo_movilidad · User: grafana_demo · Password: Lectura_Demo_2026

-- PANEL 1 · Stat · volumen de registros
SELECT NOW() AS time, COUNT(*) AS "Total validaciones" FROM validaciones;

-- PANEL 2 · Gauge · tamaño de la tabla (datos + índices) en MB
SELECT NOW() AS time,
       ROUND(((data_length + index_length) / 1024 / 1024), 2) AS "Tamaño total (MB)"
FROM information_schema.TABLES
WHERE table_schema = 'demo_movilidad' AND table_name = 'validaciones';

-- PRUEBA DE DINAMISMO (en la terminal, con el dashboard abierto y refresco cada 5 s)
INSERT INTO validaciones (codigo_viaje, estacion, ruta, tipo_pasajero, fecha_hora, tarifa, tarjeta_id, observacion)
SELECT CONCAT('EN', LPAD(id_validacion, 8, '0')), estacion, ruta, tipo_pasajero, NOW(), tarifa, tarjeta_id,
       'Insercion en vivo (clase)'
FROM validaciones
LIMIT 5000;                           -- Panel 1: 500000 -> 505000
ANALYZE TABLE validaciones;           -- actualiza el tamaño que lee el Panel 2

-- Limpieza al terminar la demostración
DELETE FROM validaciones WHERE observacion = 'Insercion en vivo (clase)';   -- Panel 1 vuelve a 500000
ANALYZE TABLE validaciones;
