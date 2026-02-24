-- =============================================================================
-- Migration v3 → v4
-- Centralized Property Management MCP Database
-- Applied: 2026-02-24
--
-- Addresses 6 production-readiness issues identified in audit:
--   1. WAL mode          — journal_mode = WAL (concurrent read/write)
--   2. Missing indexes   — 15 new indexes on FK and filter columns
--   3. CHECK gaps        — 10 enum columns now have CHECK constraints
--   4. NOT NULL gaps     — status/type columns get NOT NULL + DEFAULT
--   5. Soft-delete fields — deleted_at on 10 configurable entity tables
--   6. PRAGMA user_version = 4
--
-- Strategy:
--   · ALTER TABLE ADD COLUMN — for new columns only (no structural changes)
--   · DROP + CREATE           — v3 tables are ALL EMPTY; safe for full rebuild
--   · Rename dance            — for the one v2 table needing structural changes
--                               (openphone_voicemails)
-- =============================================================================

PRAGMA foreign_keys = OFF;   -- must be OFF during table rebuilds
PRAGMA journal_mode  = WAL;  -- persists to the DB file; only needs setting once

BEGIN TRANSACTION;

-- =============================================================================
-- SECTION 1: SOFT-DELETE COLUMNS (ALTER TABLE ADD COLUMN)
-- Safe for tables that only need new columns — no constraint changes.
-- =============================================================================

-- hostaway_groups: new entity-level is_active + soft-delete
ALTER TABLE hostaway_groups ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1
    CHECK(is_active IN (0, 1));
ALTER TABLE hostaway_groups ADD COLUMN deleted_at DATETIME;

-- hostaway_listing_units: lifecycle tracking
ALTER TABLE hostaway_listing_units ADD COLUMN deleted_at DATETIME;

-- hostaway_seasonal_rules: date-range override can be deactivated
ALTER TABLE hostaway_seasonal_rules ADD COLUMN deleted_at DATETIME;

-- hostaway_webhook_configs: endpoint lifecycle
ALTER TABLE hostaway_webhook_configs ADD COLUMN deleted_at DATETIME;

-- =============================================================================
-- SECTION 2: TABLE REBUILDS — v3 TABLES (ALL EMPTY — SAFE DROP + CREATE)
-- All 19 v3 Hostaway tables have zero rows in the live DB.
-- Rebuild applies NOT NULL, CHECK, and new columns in one step.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- hostaway_users: CHECK(role IN ...) + deleted_at
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_users;
CREATE TABLE hostaway_users (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_user_id        TEXT     UNIQUE NOT NULL,
    first_name              TEXT,
    last_name               TEXT,
    email                   TEXT,    -- stored redacted (PII scrubbed)
    role                    TEXT     CHECK(role IN (
                                'admin', 'owner', 'cleaner',
                                'maintenance', 'housekeeper', 'property_manager'
                            )),
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- hostaway_coupon_codes: discount_type NOT NULL + deleted_at
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_coupon_codes;
CREATE TABLE hostaway_coupon_codes (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_coupon_id      TEXT     UNIQUE,
    code                    TEXT     NOT NULL,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE SET NULL,
    discount_type           TEXT     NOT NULL CHECK(discount_type IN ('percent', 'fixed')),
    discount_value          REAL,
    discount_percent        REAL,
    max_uses                INTEGER,
    times_used              INTEGER  NOT NULL DEFAULT 0,
    valid_from              DATE,
    valid_to                DATE,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_coupons_code      ON hostaway_coupon_codes(code);
CREATE INDEX IF NOT EXISTS idx_coupons_is_active ON hostaway_coupon_codes(is_active);
CREATE INDEX IF NOT EXISTS idx_coupons_listing   ON hostaway_coupon_codes(hostaway_listing_id);

-- -----------------------------------------------------------------------------
-- hostaway_custom_fields: field_type CHECK + is_required NOT NULL DEFAULT +
--                         is_active + deleted_at
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_custom_fields;
CREATE TABLE hostaway_custom_fields (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_field_id       TEXT     UNIQUE,
    name                    TEXT     NOT NULL,
    field_type              TEXT     CHECK(field_type IN ('text', 'number', 'date', 'boolean', 'select')),
    description             TEXT,
    is_required             INTEGER  NOT NULL DEFAULT 0 CHECK(is_required IN (0, 1)),
    default_value           TEXT,
    options_json            TEXT,
    applies_to              TEXT     CHECK(applies_to IN ('listing', 'reservation', 'guest')),
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME
);
CREATE INDEX IF NOT EXISTS idx_custom_fields_applies_to ON hostaway_custom_fields(applies_to);
CREATE INDEX IF NOT EXISTS idx_custom_fields_is_active  ON hostaway_custom_fields(is_active);

-- -----------------------------------------------------------------------------
-- hostaway_message_templates: CHECK(trigger IN ...) + deleted_at
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_message_templates;
CREATE TABLE hostaway_message_templates (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_template_id    TEXT     UNIQUE,
    name                    TEXT     NOT NULL,
    subject                 TEXT,
    body                    TEXT     NOT NULL,
    trigger                 TEXT     CHECK(trigger IN (
                                'reservation_confirmed', 'checkin_day', 'checkout',
                                'guest_arrival', 'check_in_instructions', 'reminder', 'other'
                            )),
    channel                 TEXT     CHECK(channel IN ('email', 'sms', 'hostaway', 'all')),
    language                TEXT     NOT NULL DEFAULT 'en',
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_msg_templates_is_active ON hostaway_message_templates(is_active);

-- -----------------------------------------------------------------------------
-- hostaway_tasks: task_type NOT NULL CHECK + status NOT NULL DEFAULT
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_tasks;
CREATE TABLE hostaway_tasks (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_task_id        TEXT     UNIQUE,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE SET NULL,
    reservation_id          INTEGER
                                REFERENCES reservations(id)
                                ON DELETE SET NULL,
    assigned_user_id        TEXT
                                REFERENCES hostaway_users(hostaway_user_id)
                                ON DELETE SET NULL,
    task_type               TEXT     NOT NULL CHECK(task_type IN (
                                'cleaning', 'maintenance', 'inspection', 'other'
                            )),
    status                  TEXT     NOT NULL DEFAULT 'pending'
                                     CHECK(status IN (
                                'pending', 'in_progress', 'completed', 'cancelled'
                            )),
    title                   TEXT     NOT NULL,
    description             TEXT,
    due_date                DATE,
    completed_at            DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME
);
CREATE INDEX IF NOT EXISTS idx_tasks_listing       ON hostaway_tasks(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status        ON hostaway_tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date      ON hostaway_tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_tasks_reservation   ON hostaway_tasks(reservation_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_user ON hostaway_tasks(assigned_user_id);

-- -----------------------------------------------------------------------------
-- hostaway_owner_statements: status NOT NULL DEFAULT CHECK
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_owner_statements;
CREATE TABLE hostaway_owner_statements (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_statement_id   TEXT     UNIQUE,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE SET NULL,
    period_start            DATE     NOT NULL,
    period_end              DATE     NOT NULL,
    total_income            REAL,
    total_expenses          REAL,
    net_income              REAL,
    status                  TEXT     NOT NULL DEFAULT 'draft'
                                     CHECK(status IN ('draft', 'sent', 'approved')),
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_owner_statements_listing ON hostaway_owner_statements(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_owner_statements_period  ON hostaway_owner_statements(period_start);

-- -----------------------------------------------------------------------------
-- hostaway_expenses: category NOT NULL CHECK + new indexes
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_expenses;
CREATE TABLE hostaway_expenses (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_expense_id     TEXT     UNIQUE,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE SET NULL,
    reservation_id          INTEGER
                                REFERENCES reservations(id)
                                ON DELETE SET NULL,
    category                TEXT     NOT NULL CHECK(category IN (
                                'maintenance', 'supplies', 'utilities',
                                'labor', 'marketing', 'other'
                            )),
    amount                  REAL     NOT NULL,
    currency                TEXT     NOT NULL DEFAULT 'USD',
    description             TEXT,
    expense_date            DATE,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_expenses_listing      ON hostaway_expenses(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_expenses_expense_date ON hostaway_expenses(expense_date);
CREATE INDEX IF NOT EXISTS idx_expenses_reservation  ON hostaway_expenses(reservation_id);
CREATE INDEX IF NOT EXISTS idx_expenses_category     ON hostaway_expenses(category);

-- -----------------------------------------------------------------------------
-- hostaway_guest_charges: status NOT NULL DEFAULT + charge_type NOT NULL CHECK
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_guest_charges;
CREATE TABLE hostaway_guest_charges (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_charge_id      TEXT     UNIQUE,
    reservation_id          INTEGER
                                REFERENCES reservations(id)
                                ON DELETE SET NULL,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE SET NULL,
    amount                  REAL     NOT NULL,
    currency                TEXT     NOT NULL DEFAULT 'USD',
    status                  TEXT     NOT NULL DEFAULT 'pending'
                                     CHECK(status IN (
                                'pending', 'authorized', 'captured',
                                'voided', 'refunded', 'failed'
                            )),
    charge_type             TEXT     NOT NULL CHECK(charge_type IN (
                                'damage_deposit', 'extra_guest', 'cleaning', 'other'
                            )),
    description             TEXT,
    payment_method          TEXT,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_guest_charges_reservation ON hostaway_guest_charges(reservation_id);
CREATE INDEX IF NOT EXISTS idx_guest_charges_status      ON hostaway_guest_charges(status);
CREATE INDEX IF NOT EXISTS idx_guest_charges_listing     ON hostaway_guest_charges(hostaway_listing_id);

-- -----------------------------------------------------------------------------
-- hostaway_auto_charges: trigger NOT NULL CHECK + deleted_at
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_auto_charges;
CREATE TABLE hostaway_auto_charges (
    id                          INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_auto_charge_id     TEXT     UNIQUE,
    hostaway_listing_id         TEXT
                                    REFERENCES hostaway_listings(hostaway_listing_id)
                                    ON DELETE CASCADE,
    amount                      REAL     NOT NULL,
    currency                    TEXT     NOT NULL DEFAULT 'USD',
    trigger                     TEXT     NOT NULL CHECK(trigger IN (
                                    'on_booking', 'before_checkin', 'after_checkout',
                                    'on_checkin', 'immediate'
                                )),
    days_offset                 INTEGER,
    is_active                   INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at                  DATETIME,
    created_at                  DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_auto_charges_listing   ON hostaway_auto_charges(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_auto_charges_is_active ON hostaway_auto_charges(is_active);

-- -----------------------------------------------------------------------------
-- hostaway_tax_settings: CHECK(applies_to IN ...) + deleted_at
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS hostaway_tax_settings;
CREATE TABLE hostaway_tax_settings (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE CASCADE,
    tax_name                TEXT,
    tax_type                TEXT     CHECK(tax_type IN ('percent', 'fixed', 'per_night')),
    tax_value               REAL,
    applies_to              TEXT     CHECK(applies_to IN (
                                'base_rate', 'total', 'cleaning_fee', 'nightly_rate'
                            )),
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_tax_settings_listing   ON hostaway_tax_settings(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_tax_settings_is_active ON hostaway_tax_settings(is_active);

-- =============================================================================
-- SECTION 3: TABLE REBUILD — v2 TABLE WITH DATA (openphone_voicemails)
-- voicemail_status needs NOT NULL DEFAULT 'pending'.
-- Existing NULLs coalesced to 'pending' during copy.
-- =============================================================================
CREATE TABLE openphone_voicemails_v4 (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    call_id             INTEGER  NOT NULL UNIQUE
                                    REFERENCES openphone_calls(id)
                                    ON DELETE CASCADE
                                    ON UPDATE CASCADE,
    voicemail_status    TEXT     NOT NULL DEFAULT 'pending'
                                 CHECK(voicemail_status IN (
                                    'pending', 'completed', 'failed', 'absent'
                                )),
    transcript          TEXT,
    duration_seconds    INTEGER,
    recording_url       TEXT,
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at        DATETIME
);

INSERT INTO openphone_voicemails_v4
    (id, call_id, voicemail_status, transcript,
     duration_seconds, recording_url, created_at, processed_at)
SELECT  id, call_id,
        COALESCE(voicemail_status, 'pending'),
        transcript, duration_seconds,
        recording_url, created_at, processed_at
FROM openphone_voicemails;

DROP TABLE openphone_voicemails;
ALTER TABLE openphone_voicemails_v4 RENAME TO openphone_voicemails;

-- =============================================================================
-- SECTION 4: NEW INDEXES ON EXISTING v2 TABLES
-- =============================================================================

-- OpenPhone: FK to phone_number_id (high-frequency join in call/SMS routing)
CREATE INDEX IF NOT EXISTS idx_calls_phone_number ON openphone_calls(openphone_phone_number_id);
CREATE INDEX IF NOT EXISTS idx_sms_phone_number   ON openphone_sms_messages(openphone_phone_number_id);

-- hostaway_groups: is_active filter (just added via ALTER TABLE above)
CREATE INDEX IF NOT EXISTS idx_groups_is_active ON hostaway_groups(is_active);

-- hostaway_seasonal_rules: is_active filter for pricing lookups
CREATE INDEX IF NOT EXISTS idx_seasonal_rules_is_active ON hostaway_seasonal_rules(is_active);

-- hostaway_webhook_configs: is_active filter
CREATE INDEX IF NOT EXISTS idx_webhook_configs_is_active ON hostaway_webhook_configs(is_active);

-- =============================================================================
-- SECTION 5: BUMP SCHEMA VERSION
-- =============================================================================
PRAGMA user_version = 4;

COMMIT;

PRAGMA foreign_keys = ON;  -- re-enable after all table rebuilds
