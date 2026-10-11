-- =====================================================================
-- Pokeplan :: Layer 1 — RAW (a.k.a. bronze / landing)
-- ---------------------------------------------------------------------
-- Pattern: ELT. Land every API response exactly as received, as JSONB.
-- Nothing is parsed or cleaned here, so the raw layer is a replayable
-- source of truth: if a downstream model is wrong you rebuild it from
-- here without calling the API again (PokeAPI fair-use asks us to cache).
--
-- Grain of raw.api_response: one row per (endpoint, resource_id, payload
-- version). A new row is only inserted when the payload hash changes,
-- which gives us change history for free (insert-only / append-only).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS etl;

-- One row per pipeline execution. Every table downstream carries the
-- batch id that last touched it (an "audit dimension").
CREATE TABLE IF NOT EXISTS etl.load_batch (
    batch_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    started_at      timestamptz NOT NULL DEFAULT now(),
    finished_at     timestamptz,
    status          text        NOT NULL DEFAULT 'running'
                    CHECK (status IN ('running', 'succeeded', 'failed')),
    endpoints       text[],                 -- which endpoints this run crawled
    rows_fetched    integer     NOT NULL DEFAULT 0,
    rows_changed    integer     NOT NULL DEFAULT 0,
    notes           text
);

-- The landing table. One generic table for all 52 endpoints keeps the
-- extractor dumb: it only needs (endpoint, id) -> JSON.
CREATE TABLE IF NOT EXISTS raw.api_response (
    response_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    endpoint        text        NOT NULL,   -- e.g. 'pokemon', 'move', 'version-group'
    resource_id     integer     NOT NULL,   -- trailing integer of the resource URL
    resource_name   text,                   -- NULL for unnamed endpoints (machine, evolution-chain, ...)
    source_url      text        NOT NULL,
    payload         jsonb       NOT NULL,
    payload_sha256  text        NOT NULL,   -- change detection: skip insert if unchanged
    http_status     smallint    NOT NULL DEFAULT 200,
    fetched_at      timestamptz NOT NULL DEFAULT now(),
    batch_id        bigint      NOT NULL REFERENCES etl.load_batch (batch_id),
    is_current      boolean     NOT NULL DEFAULT true,  -- latest version of this resource
    UNIQUE (endpoint, resource_id, payload_sha256)
);

-- Only one current version per resource.
CREATE UNIQUE INDEX IF NOT EXISTS ux_api_response_current
    ON raw.api_response (endpoint, resource_id) WHERE is_current;

-- Handy for ad-hoc JSON exploration while learning.
CREATE INDEX IF NOT EXISTS ix_api_response_payload
    ON raw.api_response USING gin (payload jsonb_path_ops);

-- The /pokemon/{id}/encounters sub-resource returns a JSON *array*, not an
-- object, so it gets the same treatment under its own endpoint name
-- 'pokemon-encounters' (resource_id = pokemon id).

-- Convenience view: the current payload of every resource.
CREATE OR REPLACE VIEW raw.current_response AS
SELECT endpoint, resource_id, resource_name, payload, fetched_at, batch_id
FROM raw.api_response
WHERE is_current;

-- Helper: PokeAPI never gives us a bare FK, it gives a URL such as
-- https://pokeapi.co/api/v2/version-group/5/ . Parse the trailing integer.
CREATE OR REPLACE FUNCTION raw.url_id(url text)
RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT NULLIF(substring(url FROM '/(\d+)/?$'), '')::integer $$;
