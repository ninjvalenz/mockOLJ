# Centralized Property Management MCP Database

A unified SQLite database that ingests data from **Hostaway**, **OpenPhone (Quo)**, **Gmail**, **Discord**, and **WhatsApp** — and tracks outbound notifications back to those same platforms. An LLM layer detects actionable triggers from inbound data and routes alerts, SMS, and messages back out. Designed for bidirectional, fully auditable data flow.

---

## Files

| File | Description |
|------|-------------|
| `schema.sql` | Full v2.1 schema — SCD Type 2 dimensions, all tables (incl. `webhook_inbox`), cascading FKs, views, indexes |
| `seed_data.sql` | Realistic mock data across all platforms and new v2.1 tables |
| `migrate_v2.sql` | One-time migration script for upgrading an existing v1 `property_data.db` to v2 |
| `migrate_v2_1.sql` | Incremental migration for upgrading a v2 database to v2.1 — adds `webhook_inbox` |
| `example_queries.sql` | All 11 example queries, copy-paste ready for sqlite3 |
| `property_data.db` | Ready-to-query SQLite database (migrated to v2.1, schema version = 3) |
| `run_queries.py` | Python script that builds a fresh DB from schema + seed and runs all queries |

---

## Schema Diagram (v2.1)

```
DATA FLOW
=========
  IN  ← Hostaway · OpenPhone/Quo · Gmail · Discord · WhatsApp
  OUT → OpenPhone SMS · Discord alerts · WhatsApp messages
  LLM:  inbound message → detected_triggers → outbound_notifications

┌─────────────────────────────────────────────────────────────────────┐
│                    DIMENSION TABLES (SCD Type 2)                    │
│                                                                     │
│  ┌───────────────────────────┐  ┌──────────────────────────────┐   │
│  │          guests           │  │         properties           │   │
│  │  id (surrogate PK)        │  │  id (surrogate PK)           │   │
│  │  guest_key (stable)       │  │  property_key (stable)       │   │
│  │  first_name, last_name    │  │  name, address               │   │
│  │  primary_email            │  │  city, state, lat, lng       │   │
│  │  primary_phone (E.164)    │  │  person_capacity             │   │
│  │  hostaway_guest_id        │  │  bedrooms, bathrooms         │   │
│  │  valid_from, valid_to     │  │  hostaway_property_id        │   │
│  │  is_current               │  │  valid_from, valid_to        │   │
│  └──────────┬────────────────┘  │  is_current                  │   │
│             │                   └──────────────┬───────────────┘   │
│             │                                  │                    │
│    ┌────────▼──────────────────────────────────▼──────┐            │
│    │                   reservations                    │            │
│    │  hostaway_reservation_id · guest_id(FK)           │            │
│    │  property_id(FK) · hostaway_listing_id(FK)        │            │
│    │  check_in · check_out · status · channel          │            │
│    │  adults · children · infants · pets               │            │
│    │  base_rate · cleaning_fee · platform_fee          │            │
│    │  total_price · remaining_balance                  │            │
│    │  cancellation_date · cancelled_by                 │            │
│    └────┬──────────────────────────────────────────────┘            │
│         │                                                           │
│    ┌────▼───────────────────────┐                                   │
│    │   hostaway_conversations   │ ← CASCADE on reservation delete   │
│    │   participant_id · subject │                                   │
│    └────┬───────────────────────┘                                   │
│         │                                                           │
│    ┌────▼───────────────────────┐                                   │
│    │     hostaway_messages      │ ← CASCADE on conversation delete  │
│    │     sender_type · body     │                                   │
│    │     inserted_on · updated  │                                   │
│    └────────────────────────────┘                                   │
│                                                                     │
│    ┌────────────────────────────┐                                   │
│    │     hostaway_listings      │ ← sync snapshot from Hostaway API │
│    │     pricing · capacity     │   refreshed on each sync          │
│    │     check-in windows       │   linked to properties by         │
│    │     amenities_json         │   hostaway_property_id            │
│    └────────────────────────────┘                                   │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│               OPENPHONE / QUO  (inbound + outbound)                  │
│                                                                      │
│  ┌────────────────────────────┐                                      │
│  │  openphone_phone_numbers   │  our numbers → property mapping      │
│  │  openphone_number_id (PN…) │  calls and SMS reference this        │
│  │  phone_number · label      │  for automatic property context      │
│  │  property_id(FK)           │                                      │
│  └────────────────────────────┘                                      │
│                                                                      │
│  ┌──────────────────────────┐    ┌──────────────────────────────┐   │
│  │     openphone_calls      │    │   openphone_sms_messages     │   │
│  │  openphone_call_id (AC…) │    │   openphone_sms_id           │   │
│  │  phone_number_id(FK)     │    │   phone_number_id(FK)        │   │
│  │  openphone_user_id       │    │   openphone_user_id          │   │
│  │  guest_id(FK)            │    │   guest_id(FK)               │   │
│  │  direction               │    │   direction · body            │   │
│  │  status (13-value enum)  │    │   status (delivery tracking) │   │
│  │  started_at · answered_at│    │   sent_at · updated_at       │   │
│  │  call_route              │    └──────────────────────────────┘   │
│  │  forwarded_from/to       │                                       │
│  │  ai_handled              │                                       │
│  └──────────┬───────────────┘                                       │
│             │                                                        │
│  ┌──────────▼───────────────────┐  ┌────────────────────────────┐  │
│  │  openphone_call_transcripts  │  │     openphone_voicemails   │  │
│  │  transcript_status           │  │   call_id(FK, UNIQUE)      │  │
│  │  speaker · speaker_phone     │  │   voicemail_status         │  │
│  │  speaker_user_id             │  │   transcript · recording   │  │
│  │  text                        │  │   pending → completed      │  │
│  │  start_seconds · end_seconds │  └────────────────────────────┘  │
│  └──────────────────────────────┘                                   │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                 GMAIL                    DISCORD                     │
│                                                                      │
│  gmail_threads ──→ gmail_emails          discord_channels            │
│  guest_id(FK)       CASCADE delete       property_id(FK)             │
│  reservation_id(FK) from_email/to        ↓                           │
│                     body_text · labels   discord_messages            │
│                                          CASCADE delete              │
│                                          author · content · sent_at  │
│                                          reservation_id(FK, nullable)│
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                        WHATSAPP                                      │
│                                                                      │
│  ┌─────────────────────────────────────┐                            │
│  │       whatsapp_conversations        │                            │
│  │  guest_id(FK) · guest_phone         │                            │
│  │  our_phone · last_message_at        │                            │
│  └──────────────┬──────────────────────┘                            │
│                 │                                                    │
│  ┌──────────────▼──────────────────────┐ ← CASCADE on conv delete   │
│  │         whatsapp_messages           │                            │
│  │  direction · body · media_url       │                            │
│  │  status · sent_at                   │                            │
│  │  delivered_at · read_at             │                            │
│  └─────────────────────────────────────┘                            │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                      LLM PROCESSING LAYER                            │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                     detected_triggers                          │  │
│  │                                                               │  │
│  │  trigger_type  guest_complaint · maintenance_issue ·          │  │
│  │                scheduling_problem · payment_issue ·           │  │
│  │                checkin_issue · emergency · info_request       │  │
│  │  severity      low · medium · high · critical                 │  │
│  │                                                               │  │
│  │  source_platform + source_table + source_row_id               │  │
│  │    → polymorphic pointer to the triggering inbound message    │  │
│  │                                                               │  │
│  │  reservation_id · guest_id · property_id  (context FKs)      │  │
│  │  raw_content · llm_reasoning · llm_model · llm_confidence     │  │
│  │  status  open · acknowledged · resolved · dismissed           │  │
│  └──────────────────────────┬────────────────────────────────────┘  │
│                             │  1:many                                │
│  ┌──────────────────────────▼────────────────────────────────────┐  │
│  │                   outbound_notifications                       │  │
│  │                                                               │  │
│  │  platform   openphone_sms · discord · whatsapp · gmail        │  │
│  │  recipient  E.164 phone · Discord channel ID · email          │  │
│  │  message_body                                                 │  │
│  │  initiated_by   system (LLM) · human (manual)                │  │
│  │  status     pending · sent · delivered · failed               │  │
│  │  platform_message_id  → ID returned by destination platform   │  │
│  │  queued_at · sent_at · delivered_at                           │  │
│  └───────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│              WEBHOOK INBOX  (v2.1: OpenPhone ingest pipeline)        │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                       webhook_inbox                           │  │
│  │                                                               │  │
│  │  Decouples fast acknowledgment from processing:               │  │
│  │    1. Receiver validates signature → writes raw JSON here     │  │
│  │    2. Processing job maps payload → openphone_sms_messages    │  │
│  │    3. Failed rows tracked with error_message + attempts       │  │
│  │                                                               │  │
│  │  source       openphone | hostaway                            │  │
│  │  raw_payload  full JSON blob as received                      │  │
│  │  status       unprocessed → processing → processed | failed   │  │
│  │  attempts     retry counter (incremented on each failure)     │  │
│  │  processed_table + processed_row_id                           │  │
│  │    → pointer to the final mapped row after success            │  │
│  └───────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│                              VIEWS                                   │
│                                                                      │
│  current_guests        → guests WHERE is_current = 1                │
│  current_properties    → properties WHERE is_current = 1            │
│                                                                      │
│  unified_communications  UNION ALL of all 6 inbound sources:        │
│    hostaway (21) · openphone_sms (19) · openphone_call (3) ·        │
│    gmail (9) · discord (15) · whatsapp (5)  =  72 total rows        │
│    Columns: source · sent_at · content · direction ·                │
│             guest_key (stable) · guest_id (surrogate) ·             │
│             property_id · reservation_id                            │
│                                                                      │
│  open_triggers     unresolved detected_triggers, sorted by          │
│                    severity DESC · detected_at DESC                  │
│                    includes notifications_sent count per trigger     │
│                                                                      │
│  notification_log  all outbound_notifications with trigger context,  │
│                    guest name, property name, delivery status        │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Mock Data Overview

| Table | Rows | Notes |
|-------|------|-------|
| `guests` | 5 | 4 guests · Sarah Chen has 2 SCD versions (email changed Feb 15) |
| `properties` | 4 | 3 properties · Beach House 1 has 2 SCD versions (address corrected Jan 1) |
| `hostaway_listings` | 3 | One per active property — pricing, capacity, check-in windows, amenities |
| `reservations` | 4 | Marcus (checked out), Emily (active), Sarah (upcoming), David (checked out) |
| `hostaway_conversations` | 4 | One per reservation |
| `hostaway_messages` | 21 | Realistic guest ↔ host exchanges across all four bookings |
| `openphone_phone_numbers` | 1 | Main ops line (PN-001 → +18185550001) |
| `openphone_calls` | 3 | Marcus (parking/pet), Sarah (early check-in/fire pit), Emily (missed → voicemail) |
| `openphone_call_transcripts` | 19 | Word-for-word dialogue with segment start/end timestamps |
| `openphone_voicemails` | 1 | Emily's check-in day voicemail — hot tub temp + keypad issue |
| `openphone_sms_messages` | 19 | Full threads per guest with delivery status on outbound messages |
| `gmail_threads` | 3 | One per reservation |
| `gmail_emails` | 9 | Multi-reply threads |
| `discord_channels` | 4 | One ops channel per property + general |
| `discord_messages` | 15 | Maintenance reports, check-in notes, team comms |
| `whatsapp_conversations` | 1 | Emily Rodriguez, Mountain Cabin A check-in day |
| `whatsapp_messages` | 5 | Emily reports issues → 2 automated replies → Emily confirms resolved |
| `detected_triggers` | 5 | 4 resolved · 1 open (Mountain Cabin A keypad battery) |
| `outbound_notifications` | 7 | 5 Discord alerts + 2 WhatsApp auto-replies, all delivered |
| `webhook_inbox` | 3 | 1 processed (Marcus SMS-013) · 1 unprocessed (Emily post-stay) · 1 failed (unknown number) |

---

## Example Queries & Results

### Query 1 — All communication for the guest arriving March 5th

> *"Show me all communication related to the guest arriving on March 5th"*

Uses `guest_key` (stable SCD identifier) to pull interactions across both versions of Sarah Chen's profile — her January SMS (linked to v1/Gmail) and her February SMS and call (linked to v2/ProtonMail) all appear in one result.

```sql
WITH march5_booking AS (
    SELECT g.guest_key, cp.name AS property_name,
           cg.first_name || ' ' || cg.last_name AS guest_name
    FROM reservations r
    JOIN guests g ON r.guest_id = g.id
    JOIN current_guests cg ON g.guest_key = cg.guest_key
    JOIN properties p ON r.property_id = p.id
    JOIN current_properties cp ON p.property_key = cp.property_key
    WHERE r.check_in = '2026-03-05'
)
SELECT mb.guest_name, mb.property_name, uc.source, uc.sent_at,
       uc.direction, SUBSTR(uc.content, 1, 65) AS content_preview
FROM unified_communications uc
JOIN march5_booking mb ON uc.guest_key = mb.guest_key
ORDER BY uc.sent_at;
```

**Results (17 rows):**
```
guest_name  property_name  source          sent_at              direction  content_preview
----------  -------------  --------------  -------------------  ---------  -----------------------------------------------------------------
Sarah Chen  Cottage 3      openphone_sms   2026-01-15 13:05:00  inbound    Hi, this is Sarah. Interested in Cottage 3 for early March — is i
Sarah Chen  Cottage 3      openphone_sms   2026-01-15 13:12:00  outbound   Hi Sarah! Yes, Cottage 3 is open March 5-10. Sending the booking
Sarah Chen  Cottage 3      openphone_sms   2026-01-15 13:30:00  inbound    Booked! So excited. Quick question — is the hot tub working?
Sarah Chen  Cottage 3      openphone_sms   2026-01-15 13:38:00  outbound   Yes! Hot tub is fully operational and seats 6. You'll love it.
Sarah Chen  Cottage 3      hostaway        2026-02-01 08:30:00  guest      Hi! Just booked Cottage 3 for March 5-10. So excited for our stay
Sarah Chen  Cottage 3      hostaway        2026-02-01 09:00:00  host       Welcome Sarah! We're thrilled to have you. Cottage 3 is stunning
Sarah Chen  Cottage 3      hostaway        2026-02-03 14:15:00  guest      Quick question — is there parking for two cars? We're each drivin
Sarah Chen  Cottage 3      hostaway        2026-02-03 14:45:00  host       Absolutely! Two-car garage plus overflow in the driveway. No prob
Sarah Chen  Cottage 3      gmail           2026-02-18 09:00:00  outbound   [Pre-Arrival Instructions — Cottage 3, March 5-10 | Booking #R-10
Sarah Chen  Cottage 3      openphone_sms   2026-02-18 09:00:00  outbound   Hi Sarah! Check-in is March 5th. Gate: 4821 · Door: 7392. Any que
Sarah Chen  Cottage 3      openphone_sms   2026-02-18 09:45:00  inbound    Thank you! Any chance we could do a 1pm early check-in instead of
Sarah Chen  Cottage 3      openphone_sms   2026-02-18 09:50:00  outbound   Let me check with housekeeping and get back to you by end of day!
Sarah Chen  Cottage 3      gmail           2026-02-18 10:30:00  inbound    [Re: Pre-Arrival Instructions — Cottage 3, March 5-10 | Booking #
Sarah Chen  Cottage 3      hostaway        2026-02-18 16:00:00  guest      Wonderful. One more thing — could we do an early check-in around
Sarah Chen  Cottage 3      hostaway        2026-02-18 16:30:00  host       Let me check with housekeeping. I'll confirm by end of day!
Sarah Chen  Cottage 3      openphone_call  2026-02-19 10:15:00  inbound    Sarah called to confirm 1pm early check-in and asked about the fi
Sarah Chen  Cottage 3      gmail           2026-02-19 11:00:00  outbound   [Re: Pre-Arrival Instructions — Cottage 3, March 5-10 | Booking #
```

---

### Query 2 — Discord maintenance issues for Cottage 3 this month

> *"What maintenance issues were reported in Discord for Cottage 3 this month?"*

```sql
SELECT dm.sent_at, dm.author_display_name AS reported_by,
       SUBSTR(dm.content, 1, 80) AS message
FROM discord_messages dm
JOIN discord_channels dc ON dm.channel_id = dc.id
JOIN properties p ON dc.property_id = p.id
JOIN current_properties cp ON p.property_key = cp.property_key
WHERE cp.name = 'Cottage 3'
  AND strftime('%Y-%m', dm.sent_at) = strftime('%Y-%m', 'now')
  AND (dm.content LIKE '%mainten%' OR dm.content LIKE '%broken%'
   OR dm.content LIKE '%repair%'   OR dm.content LIKE '%issue%'
   OR dm.content LIKE '%fix%'      OR dm.content LIKE '%leak%'
   OR dm.content LIKE '%hvac%'     OR dm.content LIKE '%heat%'
   OR dm.content LIKE '%blind%')
ORDER BY dm.sent_at;
```

**Results (6 rows):**
```
sent_at              reported_by           message
-------------------  --------------------  --------------------------------------------------------------------------------
2026-02-03 11:15:00  Tony (Manager)        Heads up — guest in Cottage 3 reported the hot tub isn't heating to temp. Came i
2026-02-04 10:45:00  Marco (Pool Tech)     Hot tub issue at Cottage 3 resolved. Replaced the faulty heating element. Runnin
2026-02-12 14:00:00  Rena (Ops)            HVAC filter at Cottage 3 is overdue. Scheduling replacement for the Feb 15 turno
2026-02-15 16:20:00  Linda (Housekeeping)  Cottage 3 turnover complete. HVAC filter replaced. Also caught a small leak unde
2026-02-17 09:00:00  Tony (Manager)        New issue at Cottage 3: current guest reporting a broken window blind in the mas
2026-02-20 13:10:00  Linda (Housekeeping)  Replaced the blind in Cottage 3 master bedroom during today's inspection. Looks
```

---

### Query 3 — Full call transcript, Marcus Johnson (most recent)

> *"Show me the transcript from the most recent call with Marcus Johnson"*

```sql
SELECT cg.first_name || ' ' || cg.last_name AS guest,
       c.started_at, c.direction, c.duration_seconds AS total_s,
       t.speaker, t.start_seconds AS start_s, t.text
FROM openphone_call_transcripts t
JOIN openphone_calls c ON t.call_id = c.id
JOIN guests g ON c.guest_id = g.id
JOIN current_guests cg ON g.guest_key = cg.guest_key
WHERE cg.first_name = 'Marcus' AND cg.last_name = 'Johnson'
  AND c.started_at = (
      SELECT MAX(c2.started_at) FROM openphone_calls c2
      JOIN guests g2 ON c2.guest_id = g2.id
      WHERE g2.guest_key = cg.guest_key)
ORDER BY t.start_seconds;
```

**Results (10 rows):**
```
guest           started_at           direction  total_s  speaker  start_s  text
--------------  -------------------  ---------  -------  -------  -------  -------------------------------------------------------
Marcus Johnson  2026-01-30 15:30:00  inbound    262      host     0        Good afternoon, property management, how can I help?
Marcus Johnson  2026-01-30 15:30:00  inbound    262      guest    5        Hi, this is Marcus Johnson. I have a reservation at Beach House 1 starting February 1st.
Marcus Johnson  2026-01-30 15:30:00  inbound    262      host     13       Of course, hi Marcus! Looking forward to your stay. What can I help with?
Marcus Johnson  2026-01-30 15:30:00  inbound    262      guest    20       I wanted to confirm parking — I'm driving up from San Diego with my truck.
Marcus Johnson  2026-01-30 15:30:00  inbound    262      host     32       No problem. The driveway fits two to three vehicles comfortably.
Marcus Johnson  2026-01-30 15:30:00  inbound    262      guest    44       Great. Also — can we bring our dog? Golden retriever, very well-behaved.
Marcus Johnson  2026-01-30 15:30:00  inbound    262      host     56       Good news — Beach House 1 is pet-friendly. There's a $50 pet deposit I can add now.
Marcus Johnson  2026-01-30 15:30:00  inbound    262      guest    74       Perfect, let's do it. Thank you!
Marcus Johnson  2026-01-30 15:30:00  inbound    262      host     82       Done! Reservation updated. Looking forward to hosting you February 1st, Marcus.
Marcus Johnson  2026-01-30 15:30:00  inbound    262      guest    93       Appreciate it. See you then. Bye!
```

---

### Query 4 — Email threads for Beach House 1 reservations

> *"What emails were exchanged about Beach House 1 reservations?"*

```sql
SELECT ge.sent_at, ge.from_email,
       cg.first_name || ' ' || cg.last_name AS guest,
       ge.subject, SUBSTR(ge.body_text, 1, 70) AS body_preview
FROM gmail_emails ge
JOIN gmail_threads gt ON ge.thread_id = gt.id
JOIN reservations r ON gt.reservation_id = r.id
JOIN properties p ON r.property_id = p.id
JOIN current_properties cp ON p.property_key = cp.property_key
JOIN guests g ON r.guest_id = g.id
JOIN current_guests cg ON g.guest_key = cg.guest_key
WHERE cp.name = 'Beach House 1'
ORDER BY ge.sent_at;
```

**Results (3 rows):**
```
sent_at              from_email             guest           subject                                                body_preview
-------------------  ---------------------  --------------  -----------------------------------------------------  ----------------------------------------------------------------------
2026-01-25 10:00:00  host@propertymgmt.com  Marcus Johnson  Reservation Confirmation — Beach House 1, Feb 1-8    Dear Marcus, Thank you for booking Beach House 1 for February 1-8.
2026-01-25 14:22:00  marcus.j@outlook.com   Marcus Johnson  Re: Reservation Confirmation — Beach House 1, Feb 1  Thanks for the confirmation! Two questions: is the kayak available
2026-01-26 09:15:00  host@propertymgmt.com  Marcus Johnson  Re: Reservation Confirmation — Beach House 1, Feb 1  Hi Marcus! Kayak is available — stored in the dock shed with life v
```

---

### Query 5 — Full communication timeline for Emily Rodriguez

> *"Show me every interaction we've had with Emily Rodriguez"*

Filters by `guest_key` (stable across SCD versions) through `unified_communications`. Now includes WhatsApp messages from her check-in day.

```sql
SELECT uc.source, uc.sent_at, uc.direction,
       COALESCE(cp.name, '—') AS property,
       SUBSTR(uc.content, 1, 75) AS content_preview
FROM unified_communications uc
LEFT JOIN properties p ON uc.property_id = p.id
LEFT JOIN current_properties cp ON p.property_key = cp.property_key
WHERE uc.guest_key = (
    SELECT guest_key FROM current_guests
    WHERE first_name = 'Emily' AND last_name = 'Rodriguez')
ORDER BY uc.sent_at;
```

**Results (17 rows — 12 original + 5 WhatsApp):**
```
source          sent_at              direction  property          content_preview
--------------  -------------------  ---------  ----------------  ---------------------------------------------------------------------------
openphone_sms   2026-02-10 10:30:00  inbound    —                 Hi! Emily here. Looking forward to Mountain Cabin A! Is snowshoeing gear av
openphone_sms   2026-02-10 10:42:00  outbound   —                 Hi Emily! Two pairs of snowshoes in the garage + sleds for the hills. Super
gmail           2026-02-12 10:00:00  outbound   —                 [Your Upcoming Stay — Mountain Cabin A, Feb 25-Mar 1 | Booking #R-1002] Dea
gmail           2026-02-14 09:45:00  inbound    —                 [Re: Your Upcoming Stay — Mountain Cabin A, Feb 25-Mar 1 | Booking #R-1002]
hostaway        2026-02-14 11:00:00  guest      Mountain Cabin A  Hi! Booked Mountain Cabin A for Feb 25 - Mar 1. Any local activity recommen
hostaway        2026-02-14 11:45:00  host       Mountain Cabin A  Hi Emily! Late February is magical up there. Ski resorts are 20 min away, s
hostaway        2026-02-14 12:10:00  guest      Mountain Cabin A  Perfect! We'll have 4 adults. Is there enough bedding?
hostaway        2026-02-14 12:30:00  host       Mountain Cabin A  Absolutely — two king bedrooms plus a queen loft. Sleeps 6 comfortably!
gmail           2026-02-14 14:00:00  outbound   —                 [Re: Your Upcoming Stay — Mountain Cabin A, Feb 25-Mar 1 | Booking #R-1002]
openphone_sms   2026-02-18 09:00:00  outbound   —                 Emily — confirming Feb 25 arrival at Mountain Cabin A. Door code: 6614. Can
openphone_sms   2026-02-18 09:30:00  inbound    —                 Perfect! We are so excited. Will the hot tub be cleaned and ready?
openphone_sms   2026-02-18 09:45:00  outbound   —                 Absolutely — hot tub will be fresh and set to 104°F for your arrival.
whatsapp        2026-02-25 17:05:00  inbound    —                 Hi! Just checked in to Mountain Cabin A — it's gorgeous! Quick thing: the h
whatsapp        2026-02-25 17:12:00  outbound   —                 Hi Emily! So glad you love it! The hot tub typically needs 30-45 min to ful
whatsapp        2026-02-25 17:35:00  inbound    —                 Perfect, thanks! One more thing on the keypad — we got it to work eventuall
whatsapp        2026-02-25 17:38:00  outbound   —                 Thanks for flagging! You're likely right — we'll have maintenance check the
whatsapp        2026-02-25 19:30:00  inbound    —                 Hot tub is perfect now — exactly 104°F. Thank you!! The stars out here are
```

---

### Query 6 — SCD Type 2 audit: Sarah Chen version history

> *"Show Sarah Chen's guest record history — what changed and when?"*

Demonstrates SCD Type 2: Sarah changed her email on Feb 15. Her reservation (`R-1003`) remains linked to surrogate `id=1` (the version active at booking time). Post-Feb-15 SMS and the call are linked to `id=5` (new version).

```sql
SELECT g.id AS surrogate_id, g.guest_key, g.primary_email,
       g.valid_from, COALESCE(g.valid_to, 'CURRENT') AS valid_to,
       CASE g.is_current WHEN 1 THEN 'YES' ELSE 'no' END AS is_current,
       (SELECT GROUP_CONCAT(r.hostaway_reservation_id)
        FROM reservations r WHERE r.guest_id = g.id) AS reservations_on_version,
       (SELECT COUNT(*) FROM openphone_sms_messages s WHERE s.guest_id = g.id) AS sms_count,
       (SELECT COUNT(*) FROM openphone_calls c WHERE c.guest_id = g.id) AS call_count
FROM guests g
WHERE g.guest_key = (SELECT guest_key FROM current_guests
    WHERE first_name = 'Sarah' AND last_name = 'Chen')
ORDER BY g.valid_from;
```

**Results (2 rows):**
```
surrogate_id  guest_key  primary_email          valid_from           valid_to             is_current  reservations_on_version  sms_count  call_count
------------  ---------  ---------------------  -------------------  -------------------  ----------  -----------------------  ---------  ----------
1             G-001      sarah.chen@gmail.com   2026-01-01           2026-02-15 10:00:00  no          R-1003                   4          0
5             G-001      s.chen@protonmail.com  2026-02-15 10:00:00  CURRENT              YES                                  3          1
```

---

### Bonus — Monthly maintenance activity by property

> *"Summarize maintenance mentions per property this month"*

```sql
SELECT cp.name AS property, COUNT(*) AS maintenance_mentions,
       MIN(dm.sent_at) AS first_reported, MAX(dm.sent_at) AS last_activity
FROM discord_messages dm
JOIN discord_channels dc ON dm.channel_id = dc.id
JOIN properties p ON dc.property_id = p.id
JOIN current_properties cp ON p.property_key = cp.property_key
WHERE strftime('%Y-%m', dm.sent_at) = strftime('%Y-%m', 'now')
  AND (dm.content LIKE '%mainten%' OR dm.content LIKE '%broken%'
   OR dm.content LIKE '%repair%'   OR dm.content LIKE '%issue%'
   OR dm.content LIKE '%fix%'      OR dm.content LIKE '%leak%'
   OR dm.content LIKE '%hvac%'     OR dm.content LIKE '%heat%')
GROUP BY cp.name ORDER BY maintenance_mentions DESC;
```

**Results (2 rows):**
```
property       maintenance_mentions  first_reported       last_activity
-------------  --------------------  -------------------  -------------------
Cottage 3      5                     2026-02-03 11:15:00  2026-02-17 09:00:00
Beach House 1  2                     2026-02-01 15:30:00  2026-02-08 12:00:00
```

---

### Query 7 — Open issues dashboard

> *"What open issues do we have right now, and what actions have already been taken?"*

Uses the `open_triggers` view, which is sorted by severity DESC then recency. The `notifications_sent` column shows how many automated responses the system has already dispatched per trigger.

```sql
SELECT ot.severity, ot.trigger_type, ot.detected_at,
       ot.source_platform, ot.property_name,
       COALESCE(ot.guest_name, '(no guest)') AS guest,
       ot.status, ot.notifications_sent,
       SUBSTR(ot.raw_content, 1, 80) AS trigger_content
FROM open_triggers ot;
```

**Results (1 row — all other triggers resolved):**
```
severity  trigger_type   detected_at          source_platform  property_name     guest            status  notifications_sent  trigger_content
--------  -------------  -------------------  ---------------  ----------------  ---------------  ------  ------------------  --------------------------------------------------------------------------------
medium    checkin_issue  2026-02-25 17:36:00  whatsapp         Mountain Cabin A  Emily Rodriguez  open    2                   One more thing on the keypad — we got it to work eventually but it took 5 tries.
```

---

### Query 8 — Full trigger-to-notification audit trail

> *"Show me the complete audit trail for the Mountain Cabin A keypad issue"*

Traces one trigger from detection through every automated notification sent in response — the full chain of what was detected, what the system decided, and where it sent alerts.

```sql
WITH target_trigger AS (
    SELECT dt.id AS trigger_id, dt.detected_at, dt.trigger_type, dt.severity,
           dt.source_platform, dt.status, dt.raw_content
    FROM detected_triggers dt
    JOIN properties p ON dt.property_id = p.id
    JOIN current_properties cp ON p.property_key = cp.property_key
    WHERE dt.trigger_type = 'checkin_issue'
      AND cp.name = 'Mountain Cabin A'
)
SELECT 'TRIGGER' AS record_type, tt.detected_at AS event_time,
       tt.severity, tt.source_platform AS platform, NULL AS recipient,
       SUBSTR(tt.raw_content, 1, 70) AS content, tt.status
FROM target_trigger tt
UNION ALL
SELECT 'NOTIFICATION', n.queued_at, NULL, n.platform, n.recipient,
       SUBSTR(n.message_body, 1, 70), n.status
FROM outbound_notifications n
JOIN target_trigger tt ON n.trigger_id = tt.trigger_id
ORDER BY event_time;
```

**Results (3 rows):**
```
record_type   event_time           severity  platform  recipient     content                                                 status
------------  -------------------  --------  --------  ------------  ------------------------------------------------------  ---------
TRIGGER       2026-02-25 17:36:00  medium    whatsapp  —             One more thing on the keypad — we got it to work eve…  open
NOTIFICATION  2026-02-25 17:37:00  —         whatsapp  +17145558834  Thanks for flagging! You're likely right — we'll have…  delivered
NOTIFICATION  2026-02-25 17:37:15  —         discord   DC-003        ⚠️ OPEN ISSUE | Mountain Cabin A (R-1002): Front door…  delivered
```

---

### Query 9 — WhatsApp conversation log for a guest

> *"Show me Emily Rodriguez's full WhatsApp conversation during her Mountain Cabin A stay"*

```sql
SELECT wm.sent_at, wm.direction,
       CASE wm.direction
           WHEN 'inbound'  THEN cg.first_name || ' ' || cg.last_name
           WHEN 'outbound' THEN 'Property Ops (auto)'
       END AS from_party,
       wm.body, wm.status AS delivery_status
FROM whatsapp_messages wm
JOIN whatsapp_conversations wc ON wm.conversation_id = wc.id
JOIN guests g ON wc.guest_id = g.id
JOIN current_guests cg ON g.guest_key = cg.guest_key
WHERE cg.first_name = 'Emily' AND cg.last_name = 'Rodriguez'
ORDER BY wm.sent_at;
```

**Results (5 rows):**
```
sent_at              direction  from_party           delivery_status  body
-------------------  ---------  -------------------  ---------------  -------------------------------------------------------
2026-02-25 17:05:00  inbound    Emily Rodriguez      read             Hi! Just checked in to Mountain Cabin A — it's gorgeous! Quick thing: the hot tub seems to only be around 95°F…
2026-02-25 17:12:00  outbound   Property Ops (auto)  read             Hi Emily! So glad you love it! The hot tub typically needs 30-45 min to fully reheat after servicing. We've alerted our pool tech…
2026-02-25 17:35:00  inbound    Emily Rodriguez      read             Perfect, thanks! One more thing on the keypad — we got it to work eventually but it took like 5 tries. Might just need a battery change?
2026-02-25 17:38:00  outbound   Property Ops (auto)  read             Thanks for flagging! You're likely right — we'll have maintenance check the battery this week. If you have any trouble, backup code is 0000…
2026-02-25 19:30:00  inbound    Emily Rodriguez      read             Hot tub is perfect now — exactly 104°F. Thank you!! The stars out here are incredible too. Perfect stay so far!
```

---

### Query 10 — Monthly outbound notification stats

> *"What has the system auto-sent this month, broken down by platform and delivery status?"*

```sql
SELECT n.platform, n.status,
       COUNT(*) AS message_count,
       COUNT(DISTINCT n.trigger_id) AS distinct_triggers,
       GROUP_CONCAT(DISTINCT dt.trigger_type) AS trigger_types
FROM outbound_notifications n
LEFT JOIN detected_triggers dt ON n.trigger_id = dt.id
WHERE strftime('%Y-%m', n.queued_at) = strftime('%Y-%m', 'now')
  AND n.initiated_by = 'system'
GROUP BY n.platform, n.status
ORDER BY n.platform, n.status;
```

**Results (2 rows):**
```
platform  status     message_count  distinct_triggers  trigger_types
--------  ---------  -------------  -----------------  --------------------------------------------------
discord   delivered  5              5                  maintenance_issue,scheduling_problem,checkin_issue
whatsapp  delivered  2              2                  maintenance_issue,checkin_issue
```

---

### Query 11 — Webhook inbox processing queue

> *"What's in the webhook inbox right now — what needs processing and what has failed?"*

Shows the state of Ja's ingest pipeline. Unprocessed rows need first-attempt mapping; failed rows have an `error_message` and retry counter; processed rows show which final-table row was created.

```sql
SELECT
    wi.id, wi.source, wi.status, wi.attempts,
    wi.received_at, wi.processed_table, wi.processed_row_id,
    wi.error_message,
    json_extract(wi.raw_payload, '$.id')        AS webhook_sms_id,
    json_extract(wi.raw_payload, '$.from')      AS from_number,
    SUBSTR(json_extract(wi.raw_payload, '$.text'), 1, 65) AS message_preview
FROM webhook_inbox wi
ORDER BY
    CASE wi.status
        WHEN 'unprocessed' THEN 1
        WHEN 'failed'      THEN 2
        WHEN 'processing'  THEN 3
        WHEN 'processed'   THEN 4
    END,
    wi.received_at DESC;
```

**Results (3 rows):**
```
id  status       attempts  received_at          processed_table         processed_row_id  error_message                                                                 webhook_sms_id  from_number   message_preview
--  -----------  --------  -------------------  ----------------------  ----------------  ----------------------------------------------------------------------------  --------------  ------------  -----------------------------------------------------------------
2   unprocessed  0         2026-02-26 10:15:01                                                                                                                          SMS-030         +17145558834  Hi just wanted to say we had the most amazing stay! Left a 5-star
3   failed       2         2026-02-22 09:00:02                                            No matching guest found for phone +19995551234. Cannot resolve guest_id.       SMS-031         +19995551234  Hi, do you have availability for next weekend? Looking for someth
1   processed    1         2026-02-07 14:20:01  openphone_sms_messages  11                                                                                              SMS-013         +13105554392  Quick heads up — the garbage disposal isn't working. Not urgent.
```

---

## Design Decisions

### 1. Unified communications view as the AI query layer
Rather than forcing an AI assistant to know which table holds which type of message, a single `unified_communications` view flattens all six inbound sources (Hostaway, SMS, calls, Gmail, Discord, WhatsApp) into one timeline. The AI queries one surface; the schema handles the joins.

### 2. SCD Type 2 for guests and properties
Guest contact info and property details change over time. SCD Type 2 preserves every version with `valid_from`, `valid_to`, and `is_current` columns, plus a stable `guest_key` / `property_key` across versions.

- A partial unique index (`WHERE is_current = 1`) enforces the "only one active version" rule at the database level.
- Operational records (reservations, SMS, calls) reference the **surrogate** id — capturing which version was current at event time. Cross-version queries use `guest_key`.

### 3. Cascading deletes on operational child tables
Removing a parent automatically removes its dependents:

| Parent | Children (CASCADE) |
|--------|-------------------|
| `openphone_calls` | `openphone_call_transcripts`, `openphone_voicemails` |
| `hostaway_conversations` | `hostaway_messages` |
| `gmail_threads` | `gmail_emails` |
| `discord_channels` | `discord_messages` |
| `whatsapp_conversations` | `whatsapp_messages` |

Dimension FKs on `reservations` (`guest_id`, `property_id`) are `RESTRICT` — prevents orphaning reservation history when expiring SCD versions.

### 4. hostaway_listings separate from the properties dimension
`properties` tracks business-level SCD history (address corrections, renames). `hostaway_listings` is a mutable API sync snapshot — full pricing, capacity, check-in windows, and policies refreshed on each sync. They cross-reference via `hostaway_property_id` but are not FK-linked, since listings are mutable and the dimension is append-only.

### 5. Bidirectional tracking: detected_triggers + outbound_notifications
`detected_triggers` is the LLM's event log — every inbound message analyzed and found actionable gets a row here, with `llm_reasoning`, `llm_model`, and `llm_confidence` preserved. `outbound_notifications` is the send log — every alert or message pushed back out, with delivery status from the destination platform. The FK between them makes the full chain queryable: *what was detected → what did we do → was it delivered.*

### 6. Polymorphic source pointer on detected_triggers
A trigger can come from any of six inbound tables. Instead of six nullable FK columns, `source_table` (string) + `source_row_id` (integer PK) gives a compact polymorphic pointer. `source_platform` is CHECK-constrained to the valid set.

### 7. openphone_phone_numbers as a routing table
`openphone_phone_numbers` maps each Quo number (keyed by `PN…` ID) to a property and label. Calls and SMS reference `openphone_phone_number_id` so the ingestion layer can automatically resolve property context from the dialed number without a lookup per event.

### 8. Discord as property-level, not guest-level
Discord is an internal ops channel. Messages link to a **property** (via `discord_channels.property_id`), not a guest. `reservation_id` is nullable for optional per-booking tagging.

### 9. Webhook inbox as a decoupling layer
`webhook_inbox` separates receiving from processing. The receiver writes the raw JSON and returns HTTP 200 immediately — no guest lookups, no FK resolution, no risk of a slow DB write blocking the acknowledgment. A separate processing job reads `status='unprocessed'` rows, maps them to `openphone_sms_messages`, and updates `status`, `processed_table`, and `processed_row_id` on success. Failures set `status='failed'` and populate `error_message`, making them visible for retry or manual review without losing the original payload.

### 10. SQLite for the prototype
SQLite requires zero infrastructure and supports CTEs, views, partial indexes, and foreign key cascading — everything needed here. The schema is written to be largely portable to PostgreSQL if the system scales.

---

## Write-Up

### AI Tools Used
Built using **Claude Code** (Anthropic's CLI, powered by Claude Sonnet 4.6). Claude designed the schema, wrote all SQL, fetched and interpreted the Hostaway and OpenPhone/Quo API docs directly, generated all mock data, ran and validated every query against the live database, and wrote this documentation — working interactively across multiple sessions.

- Session 1: v1 schema design (SCD Type 2, cascading FKs, views), mock data, 6 initial queries, documentation
- Session 2: v2 expansion — API field research, bidirectional schema (WhatsApp, trigger detection, outbound notifications, voicemails, listings), migration script, updated seed data, 4 new queries, README
- Session 3: v2.1 — `webhook_inbox` table for OpenPhone SMS ingest pipeline (raw buffer → processing job → `openphone_sms_messages`), migration script, seed data, Q11, README
