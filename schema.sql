-- =============================================================================
-- Centralized Property Management MCP Database
-- Schema v4: Hostaway · OpenPhone (Quo) · Gmail · Discord · WhatsApp
--            + LLM Trigger Detection · Outbound Notification Tracking
--
-- Data flows:
--   IN  ← Hostaway (reservations, guests, messages)
--   IN  ← OpenPhone/Quo (SMS, calls, voicemails, transcripts)
--   IN  ← Gmail (emails)
--   IN  ← Discord (channel messages)
--   IN  ← WhatsApp (messages)
--
--   OUT → OpenPhone/Quo (send SMS)
--   OUT → Discord (post alerts)
--   OUT → WhatsApp (send messages)
--
--   PROCESSING: LLM detects triggers from inbound data → queues outbound actions
--
-- Design notes (same philosophy as v1, extended):
--   SCD Type 2 — guests and properties are slowly-changing dimensions.
--     Stable natural/business keys (guest_key, property_key) survive across
--     versions; surrogate PKs (id) capture the exact version active at event time.
--
--   Bidirectional tracking — detected_triggers records what the LLM noticed;
--     outbound_notifications records every message pushed back out. Both link
--     to the source event and reservation/guest/property for full audit trails.
--
--   hostaway_listings — a sync snapshot of the Hostaway listing object.
--     Distinct from the properties SCD dimension: listings hold API-level
--     detail (pricing, capacity, policies, check-in windows) and are refreshed
--     on each sync. Properties track business-level SCD history.
--
--   openphone_phone_numbers — maps each of our OpenPhone numbers to a user
--     and/or property so we know which inbox a call/SMS came through.
--
-- v2 additions over v1:
--   · properties: city, state, country, zipcode, lat, lng, capacity, bedrooms, bathrooms
--   · guests: hostaway_guest_id
--   · hostaway_listings (new table)
--   · reservations: adults, children, infants, pets, base_rate, cleaning_fee,
--                   platform_fee, total_price, remaining_balance,
--                   cancellation_date, cancelled_by, hostaway_listing_id
--   · hostaway_conversations: participant_id, subject, updated_at
--   · hostaway_messages: hostaway_msg_id, inserted_on, updated_at
--   · openphone_phone_numbers (new table)
--   · openphone_calls: openphone_phone_number_id, openphone_user_id, full status
--                      enum, answered_at, call_route, forwarded_from/to, ai_handled
--   · openphone_call_transcripts: start_seconds, end_seconds, speaker_phone,
--                                 speaker_user_id, transcript_status
--   · openphone_sms_messages: openphone_phone_number_id, openphone_user_id, status, updated_at
--   · openphone_voicemails (new table)
--   · whatsapp_conversations + whatsapp_messages (new platform)
--   · detected_triggers (new: LLM trigger detection log)
--   · outbound_notifications (new: outbound action audit log)
--   · unified_communications view updated to include WhatsApp
--   · open_triggers view (new)
--   · notification_log view (new)
--
-- v3 additions (Phase 1 complete — all 19 Hostaway data categories):
--   · hostaway_users (team members — housekeepers, managers, etc.)
--   · hostaway_groups + hostaway_group_listings (named property groups / portfolios)
--   · hostaway_listing_units (multi-unit / connected listings)
--   · hostaway_reviews (guest ratings + per-category scores + host replies)
--   · hostaway_coupon_codes (discount codes with validity windows)
--   · hostaway_custom_fields (user-defined field definitions)
--   · hostaway_reference_data (amenities, bed types, property types, policies, etc.)
--   · hostaway_message_templates (saved automated message templates)
--   · hostaway_tasks (cleaning, maintenance, inspection tasks)
--   · hostaway_seasonal_rules (date-range pricing overrides)
--   · hostaway_tax_settings (per-listing + account-level taxes)
--   · hostaway_guest_charges (per-reservation payment charges)
--   · hostaway_auto_charges (automatic charge rules per listing)
--   · hostaway_financial_reports (per-reservation income breakdown)
--   · hostaway_owner_statements (per-listing per-period financial rollup)
--   · hostaway_expenses (property expenses, optionally tied to reservations)
--   · hostaway_calendar (per-date availability + pricing snapshot per listing)
--   · hostaway_webhook_configs (Hostaway configured webhook endpoints)
--   · webhook_inbox: event_type expanded to include Hostaway reservation events
-- =============================================================================

PRAGMA foreign_keys = ON;
PRAGMA journal_mode  = WAL;     -- enable WAL for concurrent readers + single writer

-- =============================================================================
-- DIMENSION: GUESTS  (SCD Type 2)
-- =============================================================================
CREATE TABLE IF NOT EXISTS guests (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,  -- surrogate (version-specific)
    guest_key           TEXT     NOT NULL,                   -- stable business key, e.g. 'G-001'
    first_name          TEXT     NOT NULL,
    last_name           TEXT     NOT NULL,
    primary_email       TEXT,
    primary_phone       TEXT,                                -- E.164 format
    hostaway_guest_id   TEXT,                                -- v2: Hostaway internal contact/guest ID
    valid_from          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to            DATETIME,                            -- NULL = active version
    is_current          INTEGER  NOT NULL DEFAULT 1 CHECK(is_current IN (0, 1)),
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Exactly one active version per guest at DB level
CREATE UNIQUE INDEX IF NOT EXISTS ux_guests_one_active
    ON guests(guest_key) WHERE is_current = 1;

CREATE VIEW IF NOT EXISTS current_guests AS
    SELECT * FROM guests WHERE is_current = 1;

-- =============================================================================
-- DIMENSION: PROPERTIES  (SCD Type 2)
-- =============================================================================
CREATE TABLE IF NOT EXISTS properties (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    property_key            TEXT     NOT NULL,               -- stable business key
    name                    TEXT     NOT NULL,
    address                 TEXT,
    city                    TEXT,                            -- v2: from Hostaway listing
    state                   TEXT,                            -- v2
    country                 TEXT,                            -- v2
    zipcode                 TEXT,                            -- v2
    lat                     REAL,                            -- v2
    lng                     REAL,                            -- v2
    hostaway_property_id    TEXT,                            -- Hostaway platform ID (stable across versions)
    person_capacity         INTEGER,                         -- v2: max guests
    bedrooms_number         INTEGER,                         -- v2
    bathrooms_number        REAL,                            -- v2 (can be 1.5, 2.5, etc.)
    valid_from              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_to                DATETIME,
    is_current              INTEGER  NOT NULL DEFAULT 1 CHECK(is_current IN (0, 1)),
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_properties_one_active
    ON properties(property_key) WHERE is_current = 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_properties_hostaway_active
    ON properties(hostaway_property_id)
    WHERE is_current = 1 AND hostaway_property_id IS NOT NULL;

CREATE VIEW IF NOT EXISTS current_properties AS
    SELECT * FROM properties WHERE is_current = 1;

-- =============================================================================
-- HOSTAWAY: LISTINGS
-- Snapshot of the Hostaway listing object, refreshed on each API sync.
-- Holds API-level detail (pricing, capacity, policies, check-in windows)
-- that changes less frequently than reservation data.
-- Linked to the properties dimension by hostaway_property_id.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_listings (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_listing_id     TEXT     UNIQUE NOT NULL,        -- Hostaway listing.id
    property_key            TEXT,                            -- links to properties dimension
    -- Names
    name                    TEXT,
    internal_listing_name   TEXT,
    external_listing_name   TEXT,
    description             TEXT,
    -- Location
    address                 TEXT,
    city                    TEXT,
    state                   TEXT,
    country                 TEXT,
    country_code            TEXT,
    zipcode                 TEXT,
    lat                     REAL,
    lng                     REAL,
    -- Capacity
    person_capacity         INTEGER,
    bedrooms_number         INTEGER,
    beds_number             INTEGER,
    bathrooms_number        REAL,
    guest_bathrooms_number  REAL,
    -- Pricing
    price                   REAL,                            -- base nightly rate
    cleaning_fee            REAL,
    price_for_extra_person  REAL,
    weekly_discount         REAL,
    monthly_discount        REAL,
    -- Policies
    min_nights              INTEGER,
    max_nights              INTEGER,
    cancellation_policy     TEXT,
    -- Check-in/out windows (hour integer, 0–23)
    check_in_time_start     INTEGER,
    check_in_time_end       INTEGER,
    check_out_time          INTEGER,
    -- Taxes
    property_rent_tax       REAL,
    guest_stay_tax          REAL,
    guest_nightly_tax       REAL,
    -- Booking flags
    instant_bookable        INTEGER  CHECK(instant_bookable IN (0, 1)),
    allow_same_day_booking  INTEGER  CHECK(allow_same_day_booking IN (0, 1)),
    -- Amenities and bed types stored as JSON arrays (raw from API)
    amenities_json          TEXT,                            -- e.g. '["WiFi","Hot Tub","BBQ"]'
    bed_types_json          TEXT,
    -- Lifecycle
    is_archived             INTEGER  NOT NULL DEFAULT 0 CHECK(is_archived IN (0, 1)),
    last_synced_at          DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_listings_property_key ON hostaway_listings(property_key);

-- =============================================================================
-- RESERVATIONS (from Hostaway) — expanded with financial + guest count fields
-- References surrogate guest_id and property_id (version-specific snapshot).
-- =============================================================================
CREATE TABLE IF NOT EXISTS reservations (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    hostaway_reservation_id     TEXT    UNIQUE,
    guest_id                    INTEGER NOT NULL
                                    REFERENCES guests(id)
                                    ON DELETE RESTRICT
                                    ON UPDATE RESTRICT,
    property_id                 INTEGER NOT NULL
                                    REFERENCES properties(id)
                                    ON DELETE RESTRICT
                                    ON UPDATE RESTRICT,
    hostaway_listing_id         TEXT
                                    REFERENCES hostaway_listings(hostaway_listing_id)
                                    ON DELETE SET NULL,
    check_in                    DATE    NOT NULL,
    check_out                   DATE    NOT NULL,
    status                      TEXT    NOT NULL DEFAULT 'confirmed'
                                    CHECK(status IN (
                                        'inquiry', 'pending', 'confirmed',
                                        'checked_in', 'checked_out',
                                        'cancelled', 'owner_stay'
                                    )),
    channel                     TEXT,                   -- booking source: airbnb, vrbo, direct, etc.
    -- v2: Guest counts from Hostaway reservation object
    adults                      INTEGER,
    children                    INTEGER,
    infants                     INTEGER,
    pets                        INTEGER,
    -- v2: Financials from Hostaway API
    base_rate                   REAL,                   -- nightly rate × nights
    cleaning_fee                REAL,
    platform_fee                REAL,                   -- OTA commission/service fee
    total_price                 REAL,                   -- total charged (Hostaway totalPrice)
    remaining_balance           REAL,                   -- unpaid balance
    -- v2: Cancellation tracking
    cancellation_date           DATE,
    cancelled_by                TEXT    CHECK(cancelled_by IN ('guest', 'host', 'system', 'ota')),
    -- Legacy field kept for v1 seed compatibility
    total_amount                REAL,
    notes                       TEXT,
    created_at                  DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reservations_check_in     ON reservations(check_in);
CREATE INDEX IF NOT EXISTS idx_reservations_check_out    ON reservations(check_out);
CREATE INDEX IF NOT EXISTS idx_reservations_guest_id     ON reservations(guest_id);
CREATE INDEX IF NOT EXISTS idx_reservations_property_id  ON reservations(property_id);
CREATE INDEX IF NOT EXISTS idx_reservations_status       ON reservations(status);

-- =============================================================================
-- HOSTAWAY: Conversations & Messages
-- Cascade: reservation delete → conversation delete → message delete
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_conversations (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    hostaway_conversation_id    TEXT    UNIQUE,
    reservation_id              INTEGER
                                    REFERENCES reservations(id)
                                    ON DELETE CASCADE
                                    ON UPDATE CASCADE,
    participant_id              TEXT,                   -- v2: Hostaway participantId
    subject                     TEXT,                   -- v2: conversation subject
    channel                     TEXT,
    created_at                  DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at                  DATETIME                -- v2: Hostaway updatedOn
);

CREATE TABLE IF NOT EXISTS hostaway_messages (
    id              INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_msg_id TEXT     UNIQUE,                    -- v2: Hostaway message.id
    conversation_id INTEGER  NOT NULL
                                REFERENCES hostaway_conversations(id)
                                ON DELETE CASCADE
                                ON UPDATE CASCADE,
    sender_type     TEXT     NOT NULL CHECK(sender_type IN ('host', 'guest', 'system')),
    body            TEXT     NOT NULL,
    sent_at         DATETIME NOT NULL,
    inserted_on     DATETIME,                           -- v2: Hostaway insertedOn
    updated_at      DATETIME                            -- v2: Hostaway updatedOn
);

-- =============================================================================
-- HOSTAWAY: Reviews  (v3)
-- Guest star ratings and written reviews with optional host reply.
-- category_ratings_json holds per-category scores (cleanliness, communication, etc.)
-- reviewer_name is stored PII-scrubbed per Jan Marc's privacy layer.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_reviews (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_review_id      TEXT     UNIQUE,
    reservation_id          INTEGER
                                REFERENCES reservations(id)
                                ON DELETE SET NULL,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE SET NULL,
    overall_rating          REAL     CHECK(overall_rating BETWEEN 1 AND 5),
    category_ratings_json   TEXT,    -- {"cleanliness": 5, "communication": 4, "location": 5, ...}
    review_content          TEXT,    -- guest review body
    host_reply              TEXT,    -- host public response
    reviewer_name           TEXT,    -- PII-scrubbed (no raw names stored)
    submitted_at            DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reviews_listing_id   ON hostaway_reviews(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_reviews_submitted_at ON hostaway_reviews(submitted_at);

-- =============================================================================
-- HOSTAWAY: Coupon Codes  (v3)
-- Discount codes applicable to one specific listing or all listings (NULL).
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_coupon_codes (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_coupon_id      TEXT     UNIQUE,
    code                    TEXT     NOT NULL,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE SET NULL,             -- NULL = applies to all listings
    discount_type           TEXT     NOT NULL CHECK(discount_type IN ('percent', 'fixed')),
    discount_value          REAL,                               -- dollar amount if type='fixed'
    discount_percent        REAL,                               -- 0–100 if type='percent'
    max_uses                INTEGER,                            -- NULL = unlimited
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

-- =============================================================================
-- HOSTAWAY: Custom Fields  (v3)
-- User-defined fields that extend the standard Hostaway data model.
-- options_json holds allowed values for 'select' type fields.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_custom_fields (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_field_id       TEXT     UNIQUE,
    name                    TEXT     NOT NULL,
    field_type              TEXT     CHECK(field_type IN ('text', 'number', 'date', 'boolean', 'select')),
    description             TEXT,
    is_required             INTEGER  NOT NULL DEFAULT 0 CHECK(is_required IN (0, 1)),
    default_value           TEXT,
    options_json            TEXT,    -- JSON array of allowed values (select fields only)
    applies_to              TEXT     CHECK(applies_to IN ('listing', 'reservation', 'guest')),
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at              DATETIME
);

CREATE INDEX IF NOT EXISTS idx_custom_fields_applies_to ON hostaway_custom_fields(applies_to);
CREATE INDEX IF NOT EXISTS idx_custom_fields_is_active  ON hostaway_custom_fields(is_active);

-- =============================================================================
-- HOSTAWAY: Users (Team Members)  (v3)
-- Internal team — housekeepers, managers, maintenance staff, owners.
-- Email stored PII-scrubbed per Jan Marc's privacy layer.
-- Referenced by hostaway_tasks.assigned_user_id.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_users (
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

-- =============================================================================
-- HOSTAWAY: Property Groups  (v3)
-- Named bundles of listings (e.g. "Beach Portfolio", "Mountain Cabins").
-- listing_ids_json is a JSON array of hostaway_listing_id values.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_groups (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_group_id       TEXT     UNIQUE NOT NULL,
    name                    TEXT     NOT NULL,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Junction table: which listings belong to which group (many-to-many)
CREATE TABLE IF NOT EXISTS hostaway_group_listings (
    group_id            INTEGER  NOT NULL
                                    REFERENCES hostaway_groups(id)
                                    ON DELETE CASCADE,
    hostaway_listing_id TEXT     NOT NULL
                                    REFERENCES hostaway_listings(hostaway_listing_id)
                                    ON DELETE CASCADE,
    PRIMARY KEY (group_id, hostaway_listing_id)
);

CREATE INDEX IF NOT EXISTS idx_groups_is_active ON hostaway_groups(is_active);

-- =============================================================================
-- HOSTAWAY: Listing Units (Multi-Unit / Connected Listings)  (v3)
-- Individual bookable units within a parent listing.
-- Cascade: listing delete → unit delete.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_listing_units (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_unit_id        TEXT     UNIQUE NOT NULL,
    hostaway_listing_id     TEXT     NOT NULL
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE CASCADE,
    name                    TEXT,
    unit_number             TEXT,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_listing_units_listing ON hostaway_listing_units(hostaway_listing_id);

-- =============================================================================
-- HOSTAWAY: Guest Payment Charges  (v3)
-- Individual charge events against a reservation (damage deposits, extras, etc.).
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_guest_charges (
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

-- =============================================================================
-- HOSTAWAY: Auto-Charge Rules  (v3)
-- Rules that trigger automatic charges on reservations.
-- e.g. charge 30% on booking, charge remainder 7 days before check-in.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_auto_charges (
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
    days_offset                 INTEGER, -- days before/after trigger event (negative = before)
    is_active                   INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at                  DATETIME,
    created_at                  DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_auto_charges_listing   ON hostaway_auto_charges(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_auto_charges_is_active ON hostaway_auto_charges(is_active);

-- =============================================================================
-- HOSTAWAY: Seasonal Pricing Rules  (v3)
-- Date-range overrides for nightly pricing and stay constraints per listing.
-- date_ranges_json: [{"start": "2025-06-01", "end": "2025-08-31"}, ...]
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_seasonal_rules (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_rule_id        TEXT     UNIQUE,
    name                    TEXT,
    hostaway_listing_id     TEXT     NOT NULL
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE CASCADE,
    date_ranges_json        TEXT,    -- JSON array of {start, end} date range objects
    nightly_price           REAL,
    min_nights              INTEGER,
    max_nights              INTEGER,
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_seasonal_rules_listing   ON hostaway_seasonal_rules(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_seasonal_rules_is_active ON hostaway_seasonal_rules(is_active);

-- =============================================================================
-- HOSTAWAY: Tax Settings  (v3)
-- Per-listing tax configuration synced from Hostaway.
-- hostaway_listing_id = NULL means account-level default taxes.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_tax_settings (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE CASCADE,              -- NULL = account-level default
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
-- HOSTAWAY: Message Templates  (v3)
-- Saved templates for automated guest communications.
-- trigger: the Hostaway automation event that fires this template.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_message_templates (
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

-- =============================================================================
-- HOSTAWAY: Tasks  (v3)
-- Housekeeping, maintenance, and inspection tasks.
-- Linked to listings; optionally to reservations and assigned team members.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_tasks (
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

CREATE INDEX IF NOT EXISTS idx_tasks_listing      ON hostaway_tasks(hostaway_listing_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status       ON hostaway_tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date     ON hostaway_tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_tasks_reservation  ON hostaway_tasks(reservation_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_user ON hostaway_tasks(assigned_user_id);

-- =============================================================================
-- HOSTAWAY: Owner Statements  (v3)
-- Monthly/period financial summaries sent to property owners.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_owner_statements (
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

-- =============================================================================
-- HOSTAWAY: Expenses  (v3)
-- Property expenses (maintenance, supplies, utilities, etc.).
-- Optionally tied to a specific reservation (e.g. damage repair).
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_expenses (
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

-- =============================================================================
-- HOSTAWAY: Financial Reports  (v3)
-- Per-reservation income breakdown from /v1/finance/report/reservations.
-- Complements hostaway_owner_statements (period rollup) with line-item detail.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_financial_reports (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_report_id      TEXT     UNIQUE,
    reservation_id          INTEGER
                                REFERENCES reservations(id)
                                ON DELETE SET NULL,
    hostaway_listing_id     TEXT
                                REFERENCES hostaway_listings(hostaway_listing_id)
                                ON DELETE SET NULL,
    channel                 TEXT,                    -- airbnb, vrbo, direct, etc.
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

-- =============================================================================
-- HOSTAWAY: Calendar  (v3)
-- Per-date availability and pricing snapshot per listing, refreshed on each sync.
-- UPSERT-safe: unique constraint on (hostaway_listing_id, date).
-- =============================================================================
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

-- =============================================================================
-- HOSTAWAY: Reference Data  (v3)
-- Generic lookup table for all Hostaway reference endpoints.
-- category values: 'amenity' | 'bed_type' | 'property_type' |
--   'cancellation_policy' | 'country' | 'currency' | 'timezone' | 'language'
-- metadata_json holds any extra fields (ISO codes, policy text, etc.)
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_reference_data (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    category                TEXT     NOT NULL,
    hostaway_id             TEXT,    -- Hostaway's ID for this item (if applicable)
    name                    TEXT     NOT NULL,
    metadata_json           TEXT,
    last_synced_at          DATETIME,
    UNIQUE(category, hostaway_id)
);

CREATE INDEX IF NOT EXISTS idx_reference_data_category ON hostaway_reference_data(category);

-- =============================================================================
-- HOSTAWAY: Webhook Configurations  (v3)
-- The webhook endpoints configured in Hostaway (i.e. where Hostaway posts events).
-- Distinct from webhook_inbox, which is the inbound raw event buffer.
-- =============================================================================
CREATE TABLE IF NOT EXISTS hostaway_webhook_configs (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    hostaway_webhook_id     TEXT     UNIQUE NOT NULL,
    url                     TEXT     NOT NULL,   -- endpoint Hostaway posts to
    events_json             TEXT,    -- JSON array of subscribed event types
    is_active               INTEGER  NOT NULL DEFAULT 1 CHECK(is_active IN (0, 1)),
    deleted_at              DATETIME,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_webhook_configs_is_active ON hostaway_webhook_configs(is_active);

-- =============================================================================
-- OPENPHONE (Quo): Phone Numbers
-- Maps each of our OpenPhone/Quo numbers to a property and/or label.
-- Used to route inbound SMS/calls to the right property context.
-- =============================================================================
CREATE TABLE IF NOT EXISTS openphone_phone_numbers (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    openphone_number_id     TEXT     UNIQUE NOT NULL,   -- Quo API id, pattern PN...
    phone_number            TEXT     NOT NULL,           -- E.164
    label                   TEXT,                        -- e.g. 'Beach House 1 Main', 'Ops Line'
    property_id             INTEGER
                                REFERENCES properties(id)
                                ON DELETE SET NULL,
    created_at              DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- OPENPHONE: Calls — full API field set from Quo API spec
-- Cascade: call delete → transcript delete, voicemail delete
-- =============================================================================
CREATE TABLE IF NOT EXISTS openphone_calls (
    id                          INTEGER  PRIMARY KEY AUTOINCREMENT,
    openphone_call_id           TEXT     UNIQUE,         -- Quo API id, pattern AC...
    openphone_phone_number_id   TEXT
                                    REFERENCES openphone_phone_numbers(openphone_number_id)
                                    ON DELETE SET NULL,
    openphone_user_id           TEXT,                    -- v2: Quo userId (US...) who handled call
    guest_id                    INTEGER
                                    REFERENCES guests(id)
                                    ON DELETE SET NULL
                                    ON UPDATE CASCADE,
    guest_phone                 TEXT     NOT NULL,
    our_phone                   TEXT     NOT NULL,
    direction                   TEXT     NOT NULL CHECK(direction IN ('inbound', 'outbound')),
    -- v2: full status enum from Quo API
    status                      TEXT     CHECK(status IN (
                                    'queued', 'initiated', 'ringing', 'in-progress',
                                    'completed', 'busy', 'failed', 'no-answer',
                                    'canceled', 'missed', 'answered', 'forwarded', 'abandoned'
                                )),
    duration_seconds            INTEGER,
    -- v2: precise timestamps
    started_at                  DATETIME NOT NULL,
    answered_at                 DATETIME,                -- v2: when call was picked up
    ended_at                    DATETIME,
    -- v2: routing fields from Quo API
    call_route                  TEXT     CHECK(call_route IN ('phone-number', 'phone-menu')),
    forwarded_from              TEXT,                    -- phone or userId
    forwarded_to                TEXT,                    -- phone or userId
    ai_handled                  TEXT,                    -- 'ai-agent' or NULL
    -- Summary/recording
    recording_url               TEXT,
    summary                     TEXT,
    updated_at                  DATETIME
);

CREATE INDEX IF NOT EXISTS idx_calls_guest_id      ON openphone_calls(guest_id);
CREATE INDEX IF NOT EXISTS idx_calls_started_at    ON openphone_calls(started_at);
CREATE INDEX IF NOT EXISTS idx_calls_status        ON openphone_calls(status);
CREATE INDEX IF NOT EXISTS idx_calls_direction     ON openphone_calls(direction);
CREATE INDEX IF NOT EXISTS idx_calls_phone_number  ON openphone_calls(openphone_phone_number_id);

-- =============================================================================
-- OPENPHONE: Call Transcripts
-- v2: start_seconds/end_seconds per dialogue segment (from Quo transcript API).
--     speaker_phone and speaker_user_id match the 'identifier' and 'userId'
--     fields in the Quo dialogue object.
-- =============================================================================
CREATE TABLE IF NOT EXISTS openphone_call_transcripts (
    id                          INTEGER  PRIMARY KEY AUTOINCREMENT,
    call_id                     INTEGER  NOT NULL
                                            REFERENCES openphone_calls(id)
                                            ON DELETE CASCADE
                                            ON UPDATE CASCADE,
    transcript_status           TEXT     CHECK(transcript_status IN (
                                    'absent', 'in-progress', 'completed', 'failed'
                                )),
    speaker                     TEXT     NOT NULL DEFAULT 'unknown'
                                         CHECK(speaker IN ('host', 'guest', 'unknown')),
    speaker_phone               TEXT,                   -- v2: E.164 from Quo 'identifier' field
    speaker_user_id             TEXT,                   -- v2: Quo userId if internal user
    text                        TEXT     NOT NULL,
    -- v2: segment timing (replaces single timestamp_offset_seconds)
    start_seconds               REAL,                   -- dialogue segment start
    end_seconds                 REAL,                   -- dialogue segment end
    -- Legacy (kept for v1 seed compatibility)
    timestamp_offset_seconds    INTEGER
);

CREATE INDEX IF NOT EXISTS idx_transcripts_call_id ON openphone_call_transcripts(call_id);

-- =============================================================================
-- OPENPHONE: Voicemails
-- One voicemail per call (missed/no-answer calls only).
-- Processing is async — status starts 'pending', becomes 'completed' when
-- transcript and audio are available.
-- =============================================================================
CREATE TABLE IF NOT EXISTS openphone_voicemails (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    call_id             INTEGER  NOT NULL UNIQUE
                                    REFERENCES openphone_calls(id)
                                    ON DELETE CASCADE
                                    ON UPDATE CASCADE,
    voicemail_status    TEXT     NOT NULL DEFAULT 'pending'
                                 CHECK(voicemail_status IN (
                                    'pending', 'completed', 'failed', 'absent'
                                )),
    transcript          TEXT,                           -- auto-transcribed voicemail text
    duration_seconds    INTEGER,
    recording_url       TEXT,
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at        DATETIME
);

-- =============================================================================
-- OPENPHONE: SMS Messages — full API field set
-- v2 adds delivery status, phone_number_id, user_id, updated_at
-- =============================================================================
CREATE TABLE IF NOT EXISTS openphone_sms_messages (
    id                          INTEGER  PRIMARY KEY AUTOINCREMENT,
    openphone_sms_id            TEXT     UNIQUE,
    openphone_phone_number_id   TEXT
                                    REFERENCES openphone_phone_numbers(openphone_number_id)
                                    ON DELETE SET NULL,
    openphone_user_id           TEXT,                   -- v2: Quo userId for outbound (null for inbound)
    guest_id                    INTEGER
                                    REFERENCES guests(id)
                                    ON DELETE SET NULL
                                    ON UPDATE CASCADE,
    guest_phone                 TEXT     NOT NULL,
    our_phone                   TEXT     NOT NULL,
    direction                   TEXT     NOT NULL CHECK(direction IN ('inbound', 'outbound')),
    body                        TEXT     NOT NULL,
    -- v2: delivery status from Quo API
    status                      TEXT     CHECK(status IN ('queued', 'sent', 'delivered', 'undelivered')),
    sent_at                     DATETIME NOT NULL,
    updated_at                  DATETIME                -- v2: last status update timestamp
);

CREATE INDEX IF NOT EXISTS idx_sms_guest_id      ON openphone_sms_messages(guest_id);
CREATE INDEX IF NOT EXISTS idx_sms_sent_at       ON openphone_sms_messages(sent_at);
CREATE INDEX IF NOT EXISTS idx_sms_direction     ON openphone_sms_messages(direction);
CREATE INDEX IF NOT EXISTS idx_sms_phone_number  ON openphone_sms_messages(openphone_phone_number_id);

-- =============================================================================
-- GMAIL: Threads & Emails (unchanged from v1)
-- Cascade: thread delete → email delete
-- =============================================================================
CREATE TABLE IF NOT EXISTS gmail_threads (
    id              INTEGER  PRIMARY KEY AUTOINCREMENT,
    gmail_thread_id TEXT     UNIQUE NOT NULL,
    subject         TEXT,
    guest_id        INTEGER
                        REFERENCES guests(id)
                        ON DELETE SET NULL
                        ON UPDATE CASCADE,
    reservation_id  INTEGER
                        REFERENCES reservations(id)
                        ON DELETE SET NULL
                        ON UPDATE CASCADE,
    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS gmail_emails (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    gmail_message_id    TEXT     UNIQUE NOT NULL,
    thread_id           INTEGER  NOT NULL
                                    REFERENCES gmail_threads(id)
                                    ON DELETE CASCADE
                                    ON UPDATE CASCADE,
    from_email          TEXT     NOT NULL,
    to_email            TEXT     NOT NULL,
    cc_email            TEXT,
    subject             TEXT,
    body_text           TEXT,
    sent_at             DATETIME NOT NULL,
    labels              TEXT                            -- JSON array, e.g. '["inbox","reservation"]'
);

CREATE INDEX IF NOT EXISTS idx_gmail_threads_guest    ON gmail_threads(guest_id);
CREATE INDEX IF NOT EXISTS idx_gmail_emails_sent_at   ON gmail_emails(sent_at);

-- =============================================================================
-- DISCORD: Channels & Messages (unchanged from v1)
-- Internal ops channel — linked to properties, not guests.
-- Cascade: channel delete → message delete
-- =============================================================================
CREATE TABLE IF NOT EXISTS discord_channels (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    discord_channel_id  TEXT    UNIQUE NOT NULL,
    channel_name        TEXT    NOT NULL,
    server_name         TEXT,
    property_id         INTEGER
                            REFERENCES properties(id)
                            ON DELETE SET NULL
                            ON UPDATE CASCADE
);

CREATE TABLE IF NOT EXISTS discord_messages (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    discord_message_id  TEXT     UNIQUE NOT NULL,
    channel_id          INTEGER  NOT NULL
                                    REFERENCES discord_channels(id)
                                    ON DELETE CASCADE
                                    ON UPDATE CASCADE,
    author_username     TEXT     NOT NULL,
    author_display_name TEXT,
    content             TEXT     NOT NULL,
    sent_at             DATETIME NOT NULL,
    reservation_id      INTEGER
                            REFERENCES reservations(id)
                            ON DELETE SET NULL
                            ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_discord_msgs_channel  ON discord_messages(channel_id);
CREATE INDEX IF NOT EXISTS idx_discord_msgs_sent_at  ON discord_messages(sent_at);

-- =============================================================================
-- WHATSAPP: Conversations & Messages  (v2: new inbound + outbound platform)
-- Cascade: conversation delete → message delete
-- =============================================================================
CREATE TABLE IF NOT EXISTS whatsapp_conversations (
    id                          INTEGER  PRIMARY KEY AUTOINCREMENT,
    whatsapp_conversation_id    TEXT     UNIQUE,
    guest_id                    INTEGER
                                    REFERENCES guests(id)
                                    ON DELETE SET NULL
                                    ON UPDATE CASCADE,
    guest_phone                 TEXT     NOT NULL,       -- E.164
    our_phone                   TEXT     NOT NULL,       -- E.164 WhatsApp business number
    created_at                  DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_message_at             DATETIME
);

CREATE TABLE IF NOT EXISTS whatsapp_messages (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    whatsapp_msg_id         TEXT     UNIQUE NOT NULL,
    conversation_id         INTEGER  NOT NULL
                                        REFERENCES whatsapp_conversations(id)
                                        ON DELETE CASCADE
                                        ON UPDATE CASCADE,
    direction               TEXT     NOT NULL CHECK(direction IN ('inbound', 'outbound')),
    body                    TEXT,
    media_url               TEXT,                        -- for image/audio/document messages
    media_type              TEXT,                        -- 'image', 'document', 'audio', 'video'
    status                  TEXT     CHECK(status IN ('sent', 'delivered', 'read', 'failed')),
    sent_at                 DATETIME NOT NULL,
    delivered_at            DATETIME,
    read_at                 DATETIME
);

CREATE INDEX IF NOT EXISTS idx_wa_conversations_guest  ON whatsapp_conversations(guest_id);
CREATE INDEX IF NOT EXISTS idx_wa_messages_sent_at     ON whatsapp_messages(sent_at);
CREATE INDEX IF NOT EXISTS idx_wa_messages_direction   ON whatsapp_messages(direction);

-- =============================================================================
-- LLM TRIGGER DETECTION
-- Records every meaningful event the LLM detects from inbound communications.
-- A trigger represents a semantically actionable event: a guest complaint,
-- a maintenance issue, a scheduling conflict, etc.
--
-- source_table + source_row_id: polymorphic pointer to the specific inbound
-- message that triggered detection (avoids a FK to every message table).
-- =============================================================================
CREATE TABLE IF NOT EXISTS detected_triggers (
    id              INTEGER  PRIMARY KEY AUTOINCREMENT,
    detected_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    trigger_type    TEXT     NOT NULL
                             CHECK(trigger_type IN (
                                 'guest_complaint',      -- e.g. "heater isn't working"
                                 'maintenance_issue',    -- e.g. "toilet is leaking"
                                 'scheduling_problem',   -- e.g. check-in conflict
                                 'payment_issue',        -- e.g. charge dispute
                                 'checkin_issue',        -- e.g. keypad not working
                                 'emergency',            -- e.g. gas smell, flooding
                                 'positive_feedback',    -- e.g. great stay review
                                 'info_request',         -- e.g. "where is the WiFi password"
                                 'other'
                             )),
    severity        TEXT     NOT NULL DEFAULT 'medium'
                             CHECK(severity IN ('low', 'medium', 'high', 'critical')),
    -- Polymorphic source: which message caused this detection
    source_platform TEXT     NOT NULL
                             CHECK(source_platform IN (
                                 'hostaway', 'openphone_sms', 'openphone_call',
                                 'openphone_voicemail', 'gmail', 'discord', 'whatsapp'
                             )),
    source_table    TEXT     NOT NULL,  -- e.g. 'openphone_sms_messages'
    source_row_id   INTEGER  NOT NULL,  -- PK of the triggering row
    -- Context links (populated by ingestion layer)
    reservation_id  INTEGER  REFERENCES reservations(id) ON DELETE SET NULL,
    guest_id        INTEGER  REFERENCES guests(id)        ON DELETE SET NULL,
    property_id     INTEGER  REFERENCES properties(id)    ON DELETE SET NULL,
    -- LLM metadata
    raw_content     TEXT     NOT NULL,  -- the text that was analyzed
    llm_reasoning   TEXT,               -- why the LLM flagged this
    llm_model       TEXT,               -- e.g. 'claude-sonnet-4-6'
    llm_confidence  REAL,               -- 0.0–1.0, if the model returns confidence
    -- Lifecycle
    status          TEXT     NOT NULL DEFAULT 'open'
                             CHECK(status IN ('open', 'acknowledged', 'resolved', 'dismissed')),
    acknowledged_at DATETIME,
    resolved_at     DATETIME,
    resolved_by     TEXT                -- username or 'system'
);

CREATE INDEX IF NOT EXISTS idx_triggers_status       ON detected_triggers(status);
CREATE INDEX IF NOT EXISTS idx_triggers_type         ON detected_triggers(trigger_type);
CREATE INDEX IF NOT EXISTS idx_triggers_severity     ON detected_triggers(severity);
CREATE INDEX IF NOT EXISTS idx_triggers_reservation  ON detected_triggers(reservation_id);
CREATE INDEX IF NOT EXISTS idx_triggers_detected_at  ON detected_triggers(detected_at);

-- =============================================================================
-- OUTBOUND NOTIFICATIONS
-- Audit log of every message, alert, or action pushed OUT to a platform.
-- Created either by the LLM automation layer (initiated_by='system') or by
-- a human operator (initiated_by='human') manually triggering a send.
--
-- trigger_id links back to the detected_trigger that caused this notification.
-- platform_message_id is the ID returned by the destination platform after
-- a successful send (e.g. OpenPhone SMS id, Discord message id).
-- =============================================================================
CREATE TABLE IF NOT EXISTS outbound_notifications (
    id                      INTEGER  PRIMARY KEY AUTOINCREMENT,
    trigger_id              INTEGER
                                REFERENCES detected_triggers(id)
                                ON DELETE SET NULL,
    -- Destination
    platform                TEXT     NOT NULL
                                     CHECK(platform IN (
                                         'openphone_sms', 'discord', 'whatsapp', 'gmail'
                                     )),
    recipient               TEXT     NOT NULL,  -- E.164, Discord channel ID, email, etc.
    message_body            TEXT     NOT NULL,
    -- Authorization
    initiated_by            TEXT     NOT NULL DEFAULT 'system'
                                     CHECK(initiated_by IN ('system', 'human')),
    -- Delivery lifecycle
    status                  TEXT     NOT NULL DEFAULT 'pending'
                                     CHECK(status IN ('pending', 'sent', 'delivered', 'failed')),
    platform_message_id     TEXT,               -- ID returned by destination platform on success
    error_message           TEXT,               -- populated if status = 'failed'
    -- Optional context (for filtering/reporting)
    reservation_id          INTEGER  REFERENCES reservations(id)  ON DELETE SET NULL,
    guest_id                INTEGER  REFERENCES guests(id)        ON DELETE SET NULL,
    property_id             INTEGER  REFERENCES properties(id)    ON DELETE SET NULL,
    -- Timestamps
    queued_at               DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sent_at                 DATETIME,
    delivered_at            DATETIME,
    updated_at              DATETIME
);

CREATE INDEX IF NOT EXISTS idx_notifications_trigger    ON outbound_notifications(trigger_id);
CREATE INDEX IF NOT EXISTS idx_notifications_status     ON outbound_notifications(status);
CREATE INDEX IF NOT EXISTS idx_notifications_platform   ON outbound_notifications(platform);
CREATE INDEX IF NOT EXISTS idx_notifications_queued_at  ON outbound_notifications(queued_at);

-- =============================================================================
-- WEBHOOK INBOX
-- Raw ingest buffer for incoming webhook payloads before processing.
-- Decouples fast acknowledgment (write raw JSON + return 200) from the slower
-- mapping work that populates the final platform tables.
--
-- Flow:
--   1. Receiver validates signature, writes raw_payload here (status=unprocessed)
--   2. Processing job reads unprocessed/failed rows, maps to final table
--      (e.g. openphone_sms_messages), sets status=processed + processed_row_id
--   3. On mapping failure: status=failed, error_message populated, attempts++
--   4. Retry logic reads failed rows where attempts < threshold
-- =============================================================================
CREATE TABLE IF NOT EXISTS webhook_inbox (
    id                  INTEGER  PRIMARY KEY AUTOINCREMENT,
    source              TEXT     NOT NULL DEFAULT 'openphone'
                                          CHECK(source IN ('openphone', 'hostaway')),
    event_type          TEXT     NOT NULL DEFAULT 'sms'
                                          -- OpenPhone: sms, call, voicemail
                                          -- Hostaway: reservation_created, reservation_updated, reservation_cancelled, new_message
                                          CHECK(event_type IN (
                                              'sms', 'call', 'voicemail',
                                              'reservation_created', 'reservation_updated',
                                              'reservation_cancelled', 'new_message'
                                          )),
    raw_payload         TEXT     NOT NULL,                   -- full JSON blob as received
    received_at         DATETIME NOT NULL DEFAULT (datetime('now')),
    status              TEXT     NOT NULL DEFAULT 'unprocessed'
                                          CHECK(status IN (
                                              'unprocessed', 'processing', 'processed', 'failed'
                                          )),
    attempts            INTEGER  NOT NULL DEFAULT 0,
    last_attempted_at   DATETIME,
    processed_at        DATETIME,
    error_message       TEXT,                                -- populated when status='failed'
    processed_table     TEXT,                                -- 'openphone_sms_messages' | 'openphone_calls' | 'openphone_voicemails'
    processed_row_id    TEXT                                 -- PK of the final inserted row
);

CREATE INDEX IF NOT EXISTS idx_inbox_status      ON webhook_inbox(status);
CREATE INDEX IF NOT EXISTS idx_inbox_source      ON webhook_inbox(source);
CREATE INDEX IF NOT EXISTS idx_inbox_received_at ON webhook_inbox(received_at);

-- =============================================================================
-- DIMENSION INDEXES
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_guests_guest_key         ON guests(guest_key);
CREATE INDEX IF NOT EXISTS idx_guests_valid_from        ON guests(valid_from);
CREATE INDEX IF NOT EXISTS idx_properties_property_key  ON properties(property_key);

-- =============================================================================
-- VIEW: UNIFIED COMMUNICATIONS  (v2: adds WhatsApp arm)
-- Single queryable timeline across all five inbound message sources.
-- Use guest_key (stable) for cross-version guest queries.
-- Use guest_id (surrogate) when you need the exact SCD snapshot.
-- =============================================================================
CREATE VIEW IF NOT EXISTS unified_communications AS

    -- Hostaway messages (linked via reservation → guest)
    SELECT
        'hostaway'      AS source,
        hm.id           AS source_row_id,
        hm.sent_at,
        hm.body         AS content,
        hm.sender_type  AS direction,
        g.guest_key,
        r.guest_id,
        r.property_id,
        r.id            AS reservation_id
    FROM hostaway_messages hm
    JOIN hostaway_conversations hc ON hm.conversation_id = hc.id
    JOIN reservations r            ON hc.reservation_id  = r.id
    JOIN guests g                  ON r.guest_id          = g.id

UNION ALL

    -- OpenPhone SMS
    SELECT
        'openphone_sms' AS source,
        sms.id,
        sms.sent_at,
        sms.body,
        sms.direction,
        g.guest_key,
        sms.guest_id,
        NULL            AS property_id,
        NULL            AS reservation_id
    FROM openphone_sms_messages sms
    LEFT JOIN guests g ON sms.guest_id = g.id

UNION ALL

    -- OpenPhone calls (one summary row per call)
    SELECT
        'openphone_call' AS source,
        c.id,
        c.started_at,
        COALESCE(c.summary,
            c.direction || ' call · ' || c.duration_seconds || 's') AS content,
        c.direction,
        g.guest_key,
        c.guest_id,
        NULL,
        NULL
    FROM openphone_calls c
    LEFT JOIN guests g ON c.guest_id = g.id

UNION ALL

    -- Gmail
    SELECT
        'gmail'         AS source,
        ge.id,
        ge.sent_at,
        '[' || ge.subject || '] ' || COALESCE(ge.body_text, '') AS content,
        CASE WHEN ge.from_email = 'host@propertymgmt.com' THEN 'outbound'
             ELSE 'inbound' END AS direction,
        g.guest_key,
        gt.guest_id,
        NULL            AS property_id,
        gt.reservation_id
    FROM gmail_emails ge
    JOIN gmail_threads gt ON ge.thread_id = gt.id
    LEFT JOIN guests g    ON gt.guest_id  = g.id

UNION ALL

    -- Discord (property-level, internal ops)
    SELECT
        'discord'       AS source,
        dm.id,
        dm.sent_at,
        '@' || dm.author_display_name || ': ' || dm.content AS content,
        'internal'      AS direction,
        NULL            AS guest_key,
        NULL            AS guest_id,
        dc.property_id,
        dm.reservation_id
    FROM discord_messages dm
    JOIN discord_channels dc ON dm.channel_id = dc.id

UNION ALL

    -- WhatsApp  (v2: new platform)
    SELECT
        'whatsapp'      AS source,
        wm.id,
        wm.sent_at,
        wm.body         AS content,
        wm.direction,
        g.guest_key,
        wc.guest_id,
        NULL            AS property_id,
        NULL            AS reservation_id
    FROM whatsapp_messages wm
    JOIN whatsapp_conversations wc ON wm.conversation_id = wc.id
    LEFT JOIN guests g             ON wc.guest_id         = g.id;

-- =============================================================================
-- VIEW: OPEN TRIGGERS
-- All LLM-detected triggers that are still open or acknowledged (not yet
-- resolved or dismissed). Primary surface for the ops dashboard / alert router.
-- Sorted by severity DESC, then detected_at DESC.
-- =============================================================================
CREATE VIEW IF NOT EXISTS open_triggers AS
    SELECT
        dt.id,
        dt.detected_at,
        dt.trigger_type,
        dt.severity,
        dt.source_platform,
        dt.status,
        dt.raw_content,
        dt.llm_reasoning,
        dt.llm_confidence,
        cg.first_name || ' ' || cg.last_name   AS guest_name,
        cg.primary_phone                        AS guest_phone,
        cp.name                                 AS property_name,
        r.check_in,
        r.check_out,
        -- How many notifications have already gone out for this trigger
        (SELECT COUNT(*) FROM outbound_notifications n WHERE n.trigger_id = dt.id) AS notifications_sent
    FROM detected_triggers dt
    LEFT JOIN reservations r        ON dt.reservation_id = r.id
    LEFT JOIN guests g              ON dt.guest_id        = g.id
    LEFT JOIN current_guests cg     ON g.guest_key        = cg.guest_key
    LEFT JOIN properties p          ON dt.property_id     = p.id
    LEFT JOIN current_properties cp ON p.property_key     = cp.property_key
    WHERE dt.status IN ('open', 'acknowledged')
    ORDER BY
        CASE dt.severity
            WHEN 'critical' THEN 1
            WHEN 'high'     THEN 2
            WHEN 'medium'   THEN 3
            WHEN 'low'      THEN 4
        END,
        dt.detected_at DESC;

-- =============================================================================
-- VIEW: NOTIFICATION LOG
-- Full audit of every outbound notification with trigger context.
-- Used for ops reporting, retry logic, and debugging delivery failures.
-- =============================================================================
CREATE VIEW IF NOT EXISTS notification_log AS
    SELECT
        n.id,
        n.queued_at,
        n.sent_at,
        n.platform,
        n.recipient,
        SUBSTR(n.message_body, 1, 100) AS message_preview,
        n.status,
        n.initiated_by,
        n.platform_message_id,
        n.error_message,
        dt.trigger_type,
        dt.severity,
        cg.first_name || ' ' || cg.last_name   AS guest_name,
        cp.name                                 AS property_name
    FROM outbound_notifications n
    LEFT JOIN detected_triggers dt  ON n.trigger_id   = dt.id
    LEFT JOIN guests g              ON n.guest_id      = g.id
    LEFT JOIN current_guests cg     ON g.guest_key     = cg.guest_key
    LEFT JOIN properties p          ON n.property_id   = p.id
    LEFT JOIN current_properties cp ON p.property_key  = cp.property_key
    ORDER BY n.queued_at DESC;

-- =============================================================================
-- SCHEMA VERSION
-- =============================================================================
PRAGMA user_version = 4;
