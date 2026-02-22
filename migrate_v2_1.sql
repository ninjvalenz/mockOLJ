-- =============================================================================
-- Migration: v2 → v2.1
-- Adds webhook_inbox table for OpenPhone SMS ingest pipeline.
--
-- Apply to an existing v2 database:
--   sqlite3 property_data.db < migrate_v2_1.sql
--
-- Safe to run multiple times (all DDL uses IF NOT EXISTS).
-- =============================================================================

PRAGMA foreign_keys = ON;

-- webhook_inbox: raw ingest buffer for incoming webhook payloads
CREATE TABLE IF NOT EXISTS webhook_inbox (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    source              TEXT     NOT NULL DEFAULT 'openphone'
                                          CHECK(source IN ('openphone', 'hostaway')),
    raw_payload         TEXT     NOT NULL,
    received_at         DATETIME NOT NULL DEFAULT (datetime('now')),
    status              TEXT     NOT NULL DEFAULT 'unprocessed'
                                          CHECK(status IN (
                                              'unprocessed', 'processing', 'processed', 'failed'
                                          )),
    attempts            INTEGER  NOT NULL DEFAULT 0,
    last_attempted_at   DATETIME,
    processed_at        DATETIME,
    error_message       TEXT,
    processed_table     TEXT,
    processed_row_id    TEXT
);

CREATE INDEX IF NOT EXISTS idx_inbox_status      ON webhook_inbox(status);
CREATE INDEX IF NOT EXISTS idx_inbox_source      ON webhook_inbox(source);
CREATE INDEX IF NOT EXISTS idx_inbox_received_at ON webhook_inbox(received_at);

PRAGMA user_version = 3;
