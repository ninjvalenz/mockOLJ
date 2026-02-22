-- =============================================================================
-- Example Queries — Centralized Property Management MCP Database  v2
-- Demonstrates cross-platform querying across Hostaway, OpenPhone (Quo),
-- Gmail, Discord, and WhatsApp with SCD Type 2 guest/property handling.
-- Queries 1-6 (+ bonus): v1 queries (unchanged, still valid).
-- Queries 7-10: v2 queries covering trigger detection and outbound notifications.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- QUERY 1: "Show me all communication related to the guest arriving on March 5th"
--
-- SCD note: the reservation stores the surrogate guest_id active at booking
-- time (v1 of Sarah Chen). We resolve the stable guest_key from that surrogate,
-- then match all unified_communications rows sharing that guest_key — this
-- captures interactions linked to both her v1 and v2 profiles in one result.
-- -----------------------------------------------------------------------------

WITH march5_booking AS (
    SELECT
        r.id            AS res_id,
        g.guest_key,                -- stable key: finds comms across all SCD versions
        r.property_id,
        cp.name         AS property_name,
        cg.first_name || ' ' || cg.last_name AS guest_name   -- current name from current_guests
    FROM reservations r
    JOIN guests            g  ON r.guest_id    = g.id         -- resolves guest_key from reservation surrogate
    JOIN current_guests    cg ON g.guest_key   = cg.guest_key -- current name/email
    JOIN properties        p  ON r.property_id = p.id         -- resolves property_key
    JOIN current_properties cp ON p.property_key = cp.property_key
    WHERE r.check_in = '2026-03-05'
)
SELECT
    mb.guest_name,
    mb.property_name,
    uc.source,
    uc.sent_at,
    uc.direction,
    SUBSTR(uc.content, 1, 80) AS content_preview
FROM unified_communications uc
JOIN march5_booking mb ON uc.guest_key = mb.guest_key
ORDER BY uc.sent_at;


-- -----------------------------------------------------------------------------
-- QUERY 2: "What maintenance issues were reported in Discord for Cottage 3 this month?"
--
-- Discord messages are property-level (no guest_id), so we join through
-- discord_channels → properties using the current property version.
-- -----------------------------------------------------------------------------

SELECT
    dm.sent_at,
    dm.author_display_name  AS reported_by,
    cp.name                 AS property,
    dm.content              AS message
FROM discord_messages dm
JOIN discord_channels   dc ON dm.channel_id  = dc.id
JOIN properties         p  ON dc.property_id = p.id
JOIN current_properties cp ON p.property_key = cp.property_key
WHERE cp.name = 'Cottage 3'
  AND strftime('%Y-%m', dm.sent_at) = strftime('%Y-%m', 'now')
  AND (
      dm.content LIKE '%mainten%'
   OR dm.content LIKE '%broken%'
   OR dm.content LIKE '%repair%'
   OR dm.content LIKE '%issue%'
   OR dm.content LIKE '%fix%'
   OR dm.content LIKE '%leak%'
   OR dm.content LIKE '%hvac%'
   OR dm.content LIKE '%heat%'
   OR dm.content LIKE '%blind%'
  )
ORDER BY dm.sent_at;


-- -----------------------------------------------------------------------------
-- QUERY 3: "Show me the full call transcript for the most recent call with Marcus Johnson"
--
-- We look up the guest by name via current_guests (is_current = 1),
-- which gives us both the surrogate id and guest_key.
-- -----------------------------------------------------------------------------

SELECT
    cg.first_name || ' ' || cg.last_name AS guest,
    c.started_at,
    c.direction,
    c.duration_seconds  AS total_seconds,
    t.speaker,
    t.timestamp_offset_seconds          AS elapsed_s,
    t.text
FROM openphone_call_transcripts t
JOIN openphone_calls c  ON t.call_id  = c.id
JOIN guests          g  ON c.guest_id = g.id
JOIN current_guests  cg ON g.guest_key = cg.guest_key
WHERE cg.first_name = 'Marcus'
  AND cg.last_name  = 'Johnson'
  AND c.started_at = (
      -- Most recent call across ALL versions of this guest
      SELECT MAX(c2.started_at)
      FROM openphone_calls c2
      JOIN guests g2 ON c2.guest_id = g2.id
      WHERE g2.guest_key = cg.guest_key
  )
ORDER BY t.timestamp_offset_seconds;


-- -----------------------------------------------------------------------------
-- QUERY 4: "What emails were exchanged about Beach House 1 reservations?"
--
-- We join reservations → properties → property_key → current_properties
-- to resolve the current property name regardless of which version's
-- surrogate the reservation was booked against.
-- -----------------------------------------------------------------------------

SELECT
    ge.sent_at,
    ge.from_email,
    cg.first_name || ' ' || cg.last_name AS guest,
    ge.subject,
    SUBSTR(ge.body_text, 1, 120)          AS body_preview
FROM gmail_emails ge
JOIN gmail_threads      gt ON ge.thread_id       = gt.id
JOIN reservations       r  ON gt.reservation_id  = r.id
JOIN properties         p  ON r.property_id      = p.id
JOIN current_properties cp ON p.property_key     = cp.property_key
JOIN guests             g  ON r.guest_id         = g.id
JOIN current_guests     cg ON g.guest_key        = cg.guest_key
WHERE cp.name = 'Beach House 1'
ORDER BY ge.sent_at;


-- -----------------------------------------------------------------------------
-- QUERY 5: "Show me a full communication timeline for Emily Rodriguez"
--
-- Filter by guest_key (stable), not guest_id (surrogate). This ensures we
-- capture all interactions regardless of which SCD version they were linked to.
-- -----------------------------------------------------------------------------

SELECT
    uc.source,
    uc.sent_at,
    uc.direction,
    COALESCE(cp.name, '—') AS property,
    SUBSTR(uc.content, 1, 90) AS content_preview
FROM unified_communications uc
LEFT JOIN properties        p  ON uc.property_id = p.id
LEFT JOIN current_properties cp ON p.property_key = cp.property_key
WHERE uc.guest_key = (
    SELECT guest_key FROM current_guests
    WHERE first_name = 'Emily' AND last_name = 'Rodriguez'
)
ORDER BY uc.sent_at;


-- -----------------------------------------------------------------------------
-- QUERY 6 (SCD): "Show the full version history for Sarah Chen and highlight
--                 what changed between versions"
--
-- Demonstrates SCD Type 2 auditing: see every version of a guest record,
-- when it was active, and what data it held.
-- -----------------------------------------------------------------------------

SELECT
    g.id                AS surrogate_id,
    g.guest_key,
    g.first_name || ' ' || g.last_name AS name,
    g.primary_email,
    g.primary_phone,
    g.valid_from,
    COALESCE(g.valid_to, 'CURRENT')     AS valid_to,
    CASE g.is_current WHEN 1 THEN 'YES' ELSE 'no' END AS is_current,
    -- Show which surrogate the reservation was booked against
    (SELECT GROUP_CONCAT(r.hostaway_reservation_id)
     FROM reservations r WHERE r.guest_id = g.id)   AS reservations_booked_under_this_version,
    -- Count interactions linked to this specific version
    (SELECT COUNT(*) FROM openphone_sms_messages sms WHERE sms.guest_id = g.id) AS sms_count,
    (SELECT COUNT(*) FROM openphone_calls        c   WHERE c.guest_id   = g.id) AS call_count
FROM guests g
WHERE g.guest_key = (
    SELECT guest_key FROM current_guests
    WHERE first_name = 'Sarah' AND last_name = 'Chen'
)
ORDER BY g.valid_from;


-- -----------------------------------------------------------------------------
-- BONUS: "Show monthly maintenance activity per property (with current names)"
-- -----------------------------------------------------------------------------

SELECT
    cp.name             AS property,
    COUNT(*)            AS maintenance_mentions,
    MIN(dm.sent_at)     AS first_reported,
    MAX(dm.sent_at)     AS last_activity
FROM discord_messages dm
JOIN discord_channels   dc ON dm.channel_id  = dc.id
JOIN properties         p  ON dc.property_id = p.id
JOIN current_properties cp ON p.property_key = cp.property_key
WHERE strftime('%Y-%m', dm.sent_at) = strftime('%Y-%m', 'now')
  AND (
      dm.content LIKE '%mainten%'
   OR dm.content LIKE '%broken%'
   OR dm.content LIKE '%repair%'
   OR dm.content LIKE '%issue%'
   OR dm.content LIKE '%fix%'
   OR dm.content LIKE '%leak%'
   OR dm.content LIKE '%hvac%'
   OR dm.content LIKE '%heat%'
  )
GROUP BY cp.name
ORDER BY maintenance_mentions DESC;


-- =============================================================================
-- v2 QUERIES — LLM Trigger Detection · Outbound Notifications · WhatsApp
-- =============================================================================

-- -----------------------------------------------------------------------------
-- QUERY 7: "What open issues do we have right now, and what's been done about each?"
--
-- Uses the open_triggers view (sorted by severity DESC, detected_at DESC).
-- The notifications_sent column counts how many automated responses have
-- already gone out for each trigger.
-- -----------------------------------------------------------------------------

SELECT
    ot.severity,
    ot.trigger_type,
    ot.detected_at,
    ot.source_platform,
    ot.property_name,
    COALESCE(ot.guest_name, '(no guest)')   AS guest,
    ot.status,
    ot.notifications_sent,
    SUBSTR(ot.raw_content, 1, 80)           AS trigger_content,
    SUBSTR(ot.llm_reasoning, 1, 100)        AS why_flagged
FROM open_triggers ot;


-- -----------------------------------------------------------------------------
-- QUERY 8: "Show me the complete audit trail for the Mountain Cabin A keypad issue"
--
-- Traces a single trigger from detection through every automated notification
-- that went out in response. Useful for ops review and debugging.
-- -----------------------------------------------------------------------------

WITH target_trigger AS (
    SELECT dt.id AS trigger_id, dt.detected_at, dt.trigger_type, dt.severity,
           dt.source_platform, dt.status, dt.raw_content,
           cg.first_name || ' ' || cg.last_name AS guest_name,
           cp.name AS property_name
    FROM detected_triggers dt
    LEFT JOIN guests g              ON dt.guest_id    = g.id
    LEFT JOIN current_guests cg     ON g.guest_key    = cg.guest_key
    LEFT JOIN properties p          ON dt.property_id = p.id
    LEFT JOIN current_properties cp ON p.property_key = cp.property_key
    WHERE dt.trigger_type = 'checkin_issue'
      AND cp.name = 'Mountain Cabin A'
)
SELECT
    'TRIGGER'                       AS record_type,
    tt.detected_at                  AS event_time,
    tt.severity,
    tt.source_platform              AS platform,
    NULL                            AS recipient,
    tt.raw_content                  AS content,
    tt.status                       AS status
FROM target_trigger tt

UNION ALL

SELECT
    'NOTIFICATION'                  AS record_type,
    n.queued_at,
    NULL                            AS severity,
    n.platform,
    n.recipient,
    n.message_body,
    n.status
FROM outbound_notifications n
JOIN target_trigger tt ON n.trigger_id = tt.trigger_id

ORDER BY event_time;


-- -----------------------------------------------------------------------------
-- QUERY 9: "Show me Emily Rodriguez's full WhatsApp conversation during her stay"
--
-- Joins through whatsapp_conversations → whatsapp_messages, resolved to the
-- current guest profile. Includes delivery and read receipts.
-- -----------------------------------------------------------------------------

SELECT
    wm.sent_at,
    wm.direction,
    CASE wm.direction
        WHEN 'inbound'  THEN cg.first_name || ' ' || cg.last_name
        WHEN 'outbound' THEN 'Property Ops (auto)'
    END                             AS from_party,
    wm.body,
    wm.status                       AS delivery_status,
    wm.delivered_at,
    wm.read_at
FROM whatsapp_messages wm
JOIN whatsapp_conversations wc  ON wm.conversation_id = wc.id
JOIN guests g                   ON wc.guest_id        = g.id
JOIN current_guests cg          ON g.guest_key        = cg.guest_key
WHERE cg.first_name = 'Emily'
  AND cg.last_name  = 'Rodriguez'
ORDER BY wm.sent_at;


-- -----------------------------------------------------------------------------
-- QUERY 10: "What did the system auto-send this month, grouped by platform
--            and delivery status?"
--
-- Aggregates outbound_notifications by platform and status for the current
-- month. Surfaces failed deliveries and delivery success rates by channel.
-- -----------------------------------------------------------------------------

SELECT
    n.platform,
    n.status,
    COUNT(*)                                    AS message_count,
    COUNT(DISTINCT n.trigger_id)                AS distinct_triggers,
    MIN(n.queued_at)                            AS first_sent,
    MAX(n.queued_at)                            AS last_sent,
    -- Show which trigger types drove the most outbound traffic
    GROUP_CONCAT(DISTINCT dt.trigger_type)      AS trigger_types
FROM outbound_notifications n
LEFT JOIN detected_triggers dt ON n.trigger_id = dt.id
WHERE strftime('%Y-%m', n.queued_at) = strftime('%Y-%m', 'now')
  AND n.initiated_by = 'system'
GROUP BY n.platform, n.status
ORDER BY n.platform, n.status;


-- =============================================================================
-- v2.1 QUERIES — Webhook Inbox (OpenPhone SMS ingest pipeline)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- QUERY 11: "What's in the webhook inbox right now — what needs processing
--            and what has failed?"
--
-- Shows the processing queue for the webhook receiver → SMS mapper pipeline.
-- Unprocessed rows are pending first attempt; failed rows need retry or manual
-- review. Processed rows shown for audit. Ordered: unprocessed first, then
-- failed (retry candidates), then processed (audit trail).
-- -----------------------------------------------------------------------------

SELECT
    wi.id,
    wi.source,
    wi.status,
    wi.attempts,
    wi.received_at,
    wi.last_attempted_at,
    -- For processed rows: show which final table row was created
    wi.processed_table,
    wi.processed_row_id,
    -- For failed rows: show the error
    wi.error_message,
    -- Parse key fields out of the raw JSON for readability
    json_extract(wi.raw_payload, '$.id')        AS webhook_sms_id,
    json_extract(wi.raw_payload, '$.from')      AS from_number,
    json_extract(wi.raw_payload, '$.direction') AS direction,
    SUBSTR(
        json_extract(wi.raw_payload, '$.text'), 1, 80
    )                                           AS message_preview
FROM webhook_inbox wi
ORDER BY
    CASE wi.status
        WHEN 'unprocessed' THEN 1
        WHEN 'failed'      THEN 2
        WHEN 'processing'  THEN 3
        WHEN 'processed'   THEN 4
    END,
    wi.received_at DESC;
