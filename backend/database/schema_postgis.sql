-- =====================================================================
-- KapsülAR: PostgreSQL + PostGIS Uzamsal Şema ve İndeks Kıyaslama SQL
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS time_capsules (
    id              VARCHAR(32) PRIMARY KEY,
    title           VARCHAR(160) NOT NULL,
    description     TEXT,
    category        VARCHAR(64) NOT NULL,
    content_type    VARCHAR(24) NOT NULL, -- note | photo | pixelArt | audio
    geom            GEOGRAPHY(Point, 4326) NOT NULL,
    geom_planar     GEOMETRY(Point, 3857) NOT NULL,
    geohash_7       VARCHAR(12) NOT NULL,
    unlock_radius_m DOUBLE PRECISION NOT NULL DEFAULT 5.0,
    ar_radius_m     DOUBLE PRECISION NOT NULL DEFAULT 15.0,
    visual_sig      VARCHAR(64) NOT NULL,
    payload_json    JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unlock_count    INTEGER NOT NULL DEFAULT 0
);

-- 1) GiST (Generalized Search Tree - R-Tree tabanlı uzamsal indeks)
CREATE INDEX IF NOT EXISTS idx_capsules_gist
    ON time_capsules USING GIST (geom);

-- 2) SP-GiST (Space-Partitioned GiST - QuadTree/KD-Tree bölümleme)
CREATE INDEX IF NOT EXISTS idx_capsules_spgist
    ON time_capsules USING SPGIST (geom_planar);

-- 3) Geohash Ön Filtreleme B-Tree İndeksi
CREATE INDEX IF NOT EXISTS idx_capsules_geohash
    ON time_capsules (geohash_7);

-- Örnek "5 metre yakınlık" sorgusu (GiST + ST_DWithin)
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT id, title, ST_Distance(geom, ST_SetSRID(ST_MakePoint(28.9639, 41.0119), 4326)::geography) AS dist_m
-- FROM time_capsules
-- WHERE ST_DWithin(geom, ST_SetSRID(ST_MakePoint(28.9639, 41.0119), 4326)::geography, 5.0);

-- Örnek Geohash ön filtreli sorgu
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT id, title
-- FROM time_capsules
-- WHERE geohash_7 = ANY(ARRAY['sxk97b2','sxk97b3','sxk97b8','sxk97b9'])
--   AND ST_DWithin(geom, ST_SetSRID(ST_MakePoint(28.9639, 41.0119), 4326)::geography, 5.0);
