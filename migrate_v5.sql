-- =============================================================================
-- Migration: v4 → v5
-- Applies to: property_data.db (existing v4 SQLite database)
-- Applied: 2026-02-26
-- Run ONCE on the existing database. For fresh builds, use schema.sql + seed_data.sql.
--
-- What this does:
--   Adds columns captured by the hostaway-data-hub Python pipeline that were
--   missing from the v4 schema. All changes are purely additive (ALTER TABLE
--   ADD COLUMN) — no table rebuilds, no data loss.
--
--   1. hostaway_listings     — 6 new columns (rating, currency, timezone,
--                              room_type, property_type, images_json)
--   2. hostaway_conversations — 5 new columns (listing ref, guest name,
--                              last message ts, arrival/departure dates)
--   3. hostaway_messages     — 3 new columns (status, is_incoming, sender_name)
--   4. hostaway_calendar     — 3 new columns (max_nights, closed_on_arrival,
--                              closed_on_departure)
--   5. hostaway_financial_reports — 4 new columns (total_price, host_payout,
--                              host_channel_commission, payment_status)
--   6. hostaway_reviews      — 5 new columns (channel_id, private_feedback,
--                              check_in_date, check_out_date, rating)
--   7. hostaway_webhook_configs — 1 new column (updated_at)
--   8. PRAGMA user_version   = 5
--
-- SQLite notes:
--   · ALTER TABLE ADD COLUMN does not support IF NOT EXISTS.
--     Run this script ONCE. Re-running will fail with "duplicate column name".
--   · Column order within ALTER TABLE ADD COLUMN is append-only; new columns
--     always appear after the last existing column.
--   · Foreign key checks are left ON — all new FK columns default to NULL so
--     no existing rows violate any constraint.
-- =============================================================================

PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

-- =============================================================================
-- 1. hostaway_listings
--    Developer pipeline (listings.py) captures these fields that were absent.
-- =============================================================================

-- averageReviewRating → average_rating
ALTER TABLE hostaway_listings ADD COLUMN average_rating REAL;

-- currencyCode → currency  (e.g. 'USD', 'EUR')
ALTER TABLE hostaway_listings ADD COLUMN currency TEXT;

-- timeZoneName → timezone  (e.g. 'America/New_York')
ALTER TABLE hostaway_listings ADD COLUMN timezone TEXT;

-- roomTypeId → room_type   (e.g. 'entire_home', 'private_room', 'shared_room')
ALTER TABLE hostaway_listings ADD COLUMN room_type TEXT;

-- propertyTypeId → property_type  (e.g. 'house', 'apartment', 'condo')
ALTER TABLE hostaway_listings ADD COLUMN property_type TEXT;

-- listingImages → images_json  (JSON array of {url, caption} objects)
ALTER TABLE hostaway_listings ADD COLUMN images_json TEXT;

-- =============================================================================
-- 2. hostaway_conversations
--    Developer pipeline (conversations.py) captures listing context and
--    guest identity alongside the conversation record itself.
-- =============================================================================

-- listingMapId → references which listing the conversation belongs to
ALTER TABLE hostaway_conversations ADD COLUMN hostaway_listing_id TEXT
    REFERENCES hostaway_listings(hostaway_listing_id)
    ON DELETE SET NULL;

-- guestName stored PII-scrubbed per the privacy layer
ALTER TABLE hostaway_conversations ADD COLUMN guest_name TEXT;

-- Most recent message timestamp (for sort/filter without joining messages)
ALTER TABLE hostaway_conversations ADD COLUMN last_message_at DATETIME;

-- arrivalDate / departureDate surfaced on the conversation object
ALTER TABLE hostaway_conversations ADD COLUMN arrival_date DATE;
ALTER TABLE hostaway_conversations ADD COLUMN departure_date DATE;

CREATE INDEX IF NOT EXISTS idx_conversations_listing
    ON hostaway_conversations(hostaway_listing_id);

CREATE INDEX IF NOT EXISTS idx_conversations_last_message
    ON hostaway_conversations(last_message_at);

-- =============================================================================
-- 3. hostaway_messages
--    Developer pipeline captures message direction and delivery status, plus
--    the raw sender name (separate from the categorical sender_type).
-- =============================================================================

-- Message delivery / read status (e.g. 'sent', 'delivered', 'read', 'failed')
ALTER TABLE hostaway_messages ADD COLUMN status TEXT;

-- Direction flag: 1 = guest→host (inbound), 0 = host→guest (outbound)
ALTER TABLE hostaway_messages ADD COLUMN is_incoming INTEGER
    CHECK(is_incoming IN (0, 1));

-- Raw sender identifier from senderName / communicationFrom fields.
-- Distinct from sender_type (categorical). Stored PII-scrubbed when applicable.
ALTER TABLE hostaway_messages ADD COLUMN sender_name TEXT;

CREATE INDEX IF NOT EXISTS idx_messages_is_incoming
    ON hostaway_messages(is_incoming);

-- =============================================================================
-- 4. hostaway_calendar
--    Developer pipeline (calendar.py) extracts three per-day fields that
--    affect booking eligibility beyond simple min/max stay.
-- =============================================================================

-- maximumStay per calendar day (complements existing min_nights column)
ALTER TABLE hostaway_calendar ADD COLUMN max_nights INTEGER;

-- closedOnArrival: guests cannot check in on this date
ALTER TABLE hostaway_calendar ADD COLUMN closed_on_arrival INTEGER
    CHECK(closed_on_arrival IN (0, 1));

-- closedOnDeparture: guests cannot check out on this date
ALTER TABLE hostaway_calendar ADD COLUMN closed_on_departure INTEGER
    CHECK(closed_on_departure IN (0, 1));

-- =============================================================================
-- 5. hostaway_financial_reports
--    Developer pipeline (financials.py) exposes additional per-reservation
--    financial fields beyond the net income breakdown already stored.
-- =============================================================================

-- totalPrice: total amount charged to the guest
ALTER TABLE hostaway_financial_reports ADD COLUMN total_price REAL;

-- hostPayout: amount remitted to the host after all deductions
ALTER TABLE hostaway_financial_reports ADD COLUMN host_payout REAL;

-- hostChannelCommission: OTA commission taken from the host payout
ALTER TABLE hostaway_financial_reports ADD COLUMN host_channel_commission REAL;

-- paymentStatus: payment collection state (e.g. 'paid', 'pending', 'partial')
ALTER TABLE hostaway_financial_reports ADD COLUMN payment_status TEXT;

-- =============================================================================
-- 6. hostaway_reviews
--    Developer pipeline (reviews.py) captures channel context, private
--    feedback, stay dates from the review record, and the raw rating score.
-- =============================================================================

-- channelId: booking channel where the review was submitted (e.g. 'airbnb')
ALTER TABLE hostaway_reviews ADD COLUMN channel_id TEXT;

-- privateFeedback: host-only feedback, stored PII-scrubbed
ALTER TABLE hostaway_reviews ADD COLUMN private_feedback TEXT;

-- arrivalDate / departureDate from the review record itself
ALTER TABLE hostaway_reviews ADD COLUMN check_in_date DATE;
ALTER TABLE hostaway_reviews ADD COLUMN check_out_date DATE;

-- rating: raw numeric score from the API (may differ from overall_rating
--         which is the computed average across all categories)
ALTER TABLE hostaway_reviews ADD COLUMN rating REAL
    CHECK(rating BETWEEN 1 AND 5);

-- =============================================================================
-- 7. hostaway_webhook_configs
--    Developer pipeline (webhooks.py) captures updatedOn which was missing.
-- =============================================================================

ALTER TABLE hostaway_webhook_configs ADD COLUMN updated_at DATETIME;

-- =============================================================================
-- 8. Bump schema version
-- =============================================================================

PRAGMA user_version = 5;

COMMIT;
