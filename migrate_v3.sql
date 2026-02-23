-- =============================================================================
-- Migration: v2 → v3
-- Applies to: property_data.db (existing v2 SQLite database)
-- Run ONCE on the existing database. For fresh builds, use schema.sql + seed_data.sql.
--
-- What this does:
--   1. Creates all new v3 Hostaway tables (all use IF NOT EXISTS — safe to re-run)
--   2. Replaces listing_ids_json on hostaway_groups with the hostaway_group_listings
--      junction table (manual data migration required if groups data already exists)
--   3. Expands webhook_inbox.event_type CHECK to include Hostaway event types
--      (requires a table rebuild — handled below via rename/recreate)
--   4. Updates PRAGMA user_version to 3
--
-- SQLite notes:
--   · ALTER TABLE ADD COLUMN does not support IF NOT EXISTS.
--     The new v3 tables are all net-new, so we use CREATE TABLE IF NOT EXISTS.
--   · SQLite does not support ALTER TABLE DROP COLUMN in older versions.
--     webhook_inbox event_type CHECK expansion is handled via table rename + recreate.
--   · If any CREATE TABLE fails, run the remaining statements manually.
-- =============================================================================

PRAGMA foreign_keys = OFF;

BEGIN;

-- =============================================================================
-- 1. NEW HOSTAWAY TABLES (all net-new — safe with IF NOT EXISTS)
-- =============================================================================

CREATE TABLE IF NOT EXISTS hostaway_users (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_user_id    TEXT     UNIQUE NOT NULL,
    first_name          TEXT,
    last_name           TEXT,
    email               TEXT,
    role                TEXT,
    is_active           INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_synced_at      DATETIME
);

CREATE TABLE IF NOT EXISTS hostaway_groups (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_group_id   TEXT     UNIQUE NOT NULL,
    name                TEXT     NOT NULL,
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS hostaway_group_listings (
    group_id            INTEGER  NOT NULL
                                    REFERENCES hostaway_groups(id)
                                    ON DELETE CASCADE,
    hostaway_listing_id TEXT     NOT NULL
                                    REFERENCES hostaway_listings(hostaway_listing_id)
                                    ON DELETE CASCADE,
    PRIMARY KEY (group_id, hostaway_listing_id)
);

CREATE TABLE IF NOT EXISTS hostaway_listing_units (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_unit_id    TEXT     UNIQUE NOT NULL,
    hostaway_listing_id TEXT     NOT NULL
                                    REFERENCES hostaway_listings(hostaway_listing_id)
                                    ON DELETE CASCADE,
    name                TEXT,
    unit_number         TEXT,
    is_active           INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_listing_units_listing ON hostaway_listing_units(hostaway_listing_id);

CREATE TABLE IF NOT EXISTS hostaway_reviews (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_review_id      TEXT     UNIQUE,
    reservation_id          INTEGER  REFERENCES reservations(id) ON DELETE SET NULL,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    overall_rating          REAL     CHECK(overall_rating BETWEEN 1 AND 5),
    category_ratings_json   TEXT,
    review_content          TEXT,
    host_reply              TEXT,
    reviewer_name           TEXT,
    submitted_at            DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reviews_listing_id   ON hostaway_reviews(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_reviews_submitted_at ON hostaway_reviews(submitted_at);

CREATE TABLE IF NOT EXISTS hostaway_coupon_codes (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_coupon_id      TEXT     UNIQUE,
    code                    TEXT     NOT NULL,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    discount_type           TEXT     CHECK(discount_type IN ('percent', 'fixed')),
    discount_value          REAL,
    discount_percent        REAL,
    max_uses                INTEGER,
    times_used              INTEGER  NOT NULL DEFAULT 0,
    valid_from              DATE,
    valid_to                DATE,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS hostaway_custom_fields (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_field_id       TEXT     UNIQUE NOT NULL,
    name                    TEXT     NOT NULL,
    field_type              TEXT,
    description             TEXT,
    is_required             INTEGER  NOT NULL DEFAULT 0 CHECK(is_required IN (0, 1)),
    default_value           TEXT,
    options_json            TEXT,
    applies_to              TEXT,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME
);

CREATE TABLE IF NOT EXISTS hostaway_reference_data (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    category                TEXT     NOT NULL,
    hostaway_id             TEXT,
    name                    TEXT     NOT NULL,
    metadata_json           TEXT,
    last_synced_at          DATETIME,
    UNIQUE(category, hostaway_id)
);

CREATE INDEX IF NOT EXISTS idx_reference_data_category ON hostaway_reference_data(category);

CREATE TABLE IF NOT EXISTS hostaway_message_templates (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_template_id    TEXT     UNIQUE NOT NULL,
    name                    TEXT     NOT NULL,
    subject                 TEXT,
    body                    TEXT,
    trigger                 TEXT,
    channel                 TEXT,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    language                TEXT,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS hostaway_tasks (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_task_id        TEXT     UNIQUE NOT NULL,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    reservation_id          INTEGER  REFERENCES reservations(id) ON DELETE SET NULL,
    assigned_user_id        INTEGER  REFERENCES hostaway_users(id) ON DELETE SET NULL,
    type                    TEXT,
    status                  TEXT     CHECK(status IN ('pending', 'in_progress', 'completed', 'cancelled')),
    title                   TEXT,
    description             TEXT,
    due_date                DATE,
    completed_at            DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tasks_listing_id     ON hostaway_tasks(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_tasks_reservation_id ON hostaway_tasks(reservation_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status         ON hostaway_tasks(status);

CREATE TABLE IF NOT EXISTS hostaway_seasonal_rules (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_rule_id        TEXT     UNIQUE NOT NULL,
    name                    TEXT,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    date_ranges_json        TEXT,
    nightly_price           REAL,
    min_nights              INTEGER,
    max_nights              INTEGER,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_seasonal_rules_listing ON hostaway_seasonal_rules(hostaway_listing_id);

CREATE TABLE IF NOT EXISTS hostaway_tax_settings (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    is_account_level        INTEGER  NOT NULL DEFAULT 0 CHECK(is_account_level IN (0, 1)),
    tax_name                TEXT,
    tax_type                TEXT,
    tax_rate                REAL,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tax_settings_listing ON hostaway_tax_settings(hostaway_listing_id);

CREATE TABLE IF NOT EXISTS hostaway_guest_charges (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_charge_id      TEXT     UNIQUE NOT NULL,
    reservation_id          INTEGER  REFERENCES reservations(id) ON DELETE SET NULL,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    amount                  REAL     NOT NULL,
    currency                TEXT,
    status                  TEXT     CHECK(status IN ('pending', 'completed', 'failed', 'refunded')),
    charge_type             TEXT,
    description             TEXT,
    payment_method          TEXT,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_guest_charges_reservation ON hostaway_guest_charges(reservation_id);

CREATE TABLE IF NOT EXISTS hostaway_auto_charges (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_auto_charge_id TEXT     UNIQUE NOT NULL,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    amount                  REAL,
    currency                TEXT,
    trigger                 TEXT,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS hostaway_owner_statements (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_statement_id   TEXT     UNIQUE,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    period_start            DATE,
    period_end              DATE,
    total_income            REAL,
    total_expenses          REAL,
    net_income              REAL,
    status                  TEXT,
    currency                TEXT     NOT NULL DEFAULT 'USD',
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_owner_statements_listing ON hostaway_owner_statements(hostaway_listing_id);

CREATE TABLE IF NOT EXISTS hostaway_expenses (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_expense_id     TEXT     UNIQUE,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    reservation_id          INTEGER  REFERENCES reservations(id) ON DELETE SET NULL,
    category                TEXT,
    amount                  REAL     NOT NULL,
    currency                TEXT     NOT NULL DEFAULT 'USD',
    description             TEXT,
    expense_date            DATE,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_expenses_listing      ON hostaway_expenses(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_expenses_expense_date ON hostaway_expenses(expense_date);

CREATE TABLE IF NOT EXISTS hostaway_financial_reports (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_report_id      TEXT     UNIQUE,
    reservation_id          INTEGER  REFERENCES reservations(id) ON DELETE SET NULL,
    hostaway_listing_id     TEXT     REFERENCES hostaway_listings(hostaway_listing_id) ON DELETE SET NULL,
    channel                 TEXT,
    check_in                DATE,
    check_out               DATE,
    accommodation_fare      REAL,
    cleaning_fee            REAL,
    platform_commission     REAL,
    net_income              REAL,
    currency                TEXT     NOT NULL DEFAULT 'USD',
    report_date             DATE,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_financial_reports_listing     ON hostaway_financial_reports(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_financial_reports_reservation ON hostaway_financial_reports(reservation_id);
CREATE INDEX IF NOT EXISTS idx_financial_reports_date        ON hostaway_financial_reports(report_date);

CREATE TABLE IF NOT EXISTS hostaway_calendar (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_listing_id     TEXT     NOT NULL
                                        REFERENCES hostaway_listings(hostaway_listing_id)
                                        ON DELETE CASCADE,
    date                    DATE     NOT NULL,
    is_available            INTEGER  NOT NULL DEFAULT 1 CHECK(is_available IN (0, 1)),
    price                   REAL,
    min_nights              INTEGER,
    notes                   TEXT,
    last_synced_at          DATETIME,
    UNIQUE (hostaway_listing_id, date)
);

CREATE INDEX IF NOT EXISTS idx_calendar_listing ON hostaway_calendar(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_calendar_date    ON hostaway_calendar(date);

CREATE TABLE IF NOT EXISTS hostaway_webhook_configs (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_webhook_id     TEXT     UNIQUE,
    url                     TEXT,
    events_json             TEXT,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- 2. webhook_inbox — expand event_type CHECK to include Hostaway event types
--
-- SQLite does not support ALTER TABLE MODIFY COLUMN. The only safe approach
-- is rename → recreate → copy → drop old.
-- Skip this block if webhook_inbox has existing data you cannot afford to lose
-- and run the INSERT INTO manually after verifying your data.
-- =============================================================================

ALTER TABLE webhook_inbox RENAME TO _webhook_inbox_v2;

CREATE TABLE webhook_inbox (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    source              TEXT     NOT NULL DEFAULT 'openphone'
                                          CHECK(source IN ('openphone', 'hostaway')),
    event_type          TEXT     NOT NULL DEFAULT 'sms'
                                          CHECK(event_type IN (
                                              'sms', 'call', 'voicemail',
                                              'reservation_created', 'reservation_updated',
                                              'reservation_cancelled', 'new_message'
                                          )),
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

INSERT INTO webhook_inbox (
    id, source, event_type, raw_payload, received_at, status, attempts,
    last_attempted_at, processed_at, error_message, processed_table, processed_row_id
)
SELECT
    id, source, event_type, raw_payload, received_at, status, attempts,
    last_attempted_at, processed_at, error_message, processed_table, processed_row_id
FROM _webhook_inbox_v2;
DROP TABLE _webhook_inbox_v2;

CREATE INDEX IF NOT EXISTS idx_inbox_status      ON webhook_inbox(status);
CREATE INDEX IF NOT EXISTS idx_inbox_source      ON webhook_inbox(source);
CREATE INDEX IF NOT EXISTS idx_inbox_received_at ON webhook_inbox(received_at);

-- =============================================================================
-- 3. Update schema version
-- =============================================================================
PRAGMA user_version = 3;

COMMIT;

PRAGMA foreign_keys = ON;
