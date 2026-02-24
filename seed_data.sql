-- =============================================================================
-- Mock Seed Data  v2
-- Hostaway · OpenPhone (Quo) · Gmail · Discord · WhatsApp
-- + Trigger Detection · Outbound Notifications
-- Reference date: 2026-02-25
--
-- SCD Type 2 examples:
--   guests.G-001 (Sarah Chen) — email changed 2026-02-15, two versions exist.
--     Reservation R-1003 (created Feb 1) references surrogate id=1 (v1, the
--     version active at booking time). Post-Feb-15 SMS and calls reference id=5.
--
--   properties.PROP-002 (Beach House 1) — address corrected 2026-01-01.
--     Historical reservations from 2025 reference surrogate id=2 (v1).
--     All 2026 reservations reference id=5 (v2, the corrected listing).
--
-- v2 additions over v1 seed:
--   · properties: city, state, lat/lng, capacity, bedrooms, bathrooms
--   · reservations: adults, children, infants, pets, base_rate, cleaning_fee,
--                   platform_fee, total_price, hostaway_listing_id
--   · openphone_calls: status, answered_at, call_route, phone_number_id
--                      + call 3: Emily missed call → voicemail
--   · openphone_sms_messages: status (delivery), phone_number_id
--   · NEW: hostaway_listings, openphone_phone_numbers, openphone_voicemails
--   · NEW: whatsapp_conversations + whatsapp_messages (Emily, Mountain Cabin A stay)
--   · NEW: detected_triggers (5 LLM-detected events)
--   · NEW: outbound_notifications (7 automated responses)
-- =============================================================================

PRAGMA foreign_keys = ON;

-- -----------------------------------------------------------------------------
-- PROPERTIES (SCD Type 2) — v2: includes location and capacity fields
-- -----------------------------------------------------------------------------
INSERT INTO properties (
    id, property_key, name, address,
    city, state, country, zipcode, lat, lng,
    person_capacity, bedrooms_number, bathrooms_number,
    hostaway_property_id, valid_from, valid_to, is_current
) VALUES
    (1, 'PROP-001', 'Cottage 3',
        '789 Lakeview Dr, Big Bear Lake, CA 92315',
        'Big Bear Lake', 'CA', 'USA', '92315', 34.2439, -116.9114,
        6, 3, 2.0,
        'HA-001', '2025-06-01', NULL, 1),

    -- Beach House 1 v1: original address (typo in street number), expired 2026-01-01
    (2, 'PROP-002', 'Beach House 1',
        '123 Ocean Ave, Malibu, CA 90265',
        'Malibu', 'CA', 'USA', '90265', 34.0259, -118.7798,
        8, 4, 3.0,
        'HA-002', '2025-03-01', '2026-01-01', 0),

    (3, 'PROP-003', 'Mountain Cabin A',
        '456 Pine Ridge Rd, South Lake Tahoe, CA 96150',
        'South Lake Tahoe', 'CA', 'USA', '96150', 38.9399, -119.9772,
        6, 3, 2.0,
        'HA-003', '2025-09-01', NULL, 1),

    -- Beach House 1 v2: corrected address — active 2026-01-01 onward (current)
    (5, 'PROP-002', 'Beach House 1',
        '125 Pacific Coast Hwy, Malibu, CA 90265',
        'Malibu', 'CA', 'USA', '90265', 34.0259, -118.7798,
        8, 4, 3.0,
        'HA-002', '2026-01-01', NULL, 1);

-- -----------------------------------------------------------------------------
-- GUESTS (SCD Type 2)
-- -----------------------------------------------------------------------------
INSERT INTO guests (
    id, guest_key, first_name, last_name,
    primary_email, primary_phone,
    valid_from, valid_to, is_current
) VALUES
    -- Sarah Chen v1: Gmail; expires when she updates to ProtonMail Feb 15
    (1, 'G-001', 'Sarah', 'Chen',
        'sarah.chen@gmail.com', '+14155557821',
        '2026-01-01', '2026-02-15 10:00:00', 0),

    (2, 'G-002', 'Marcus', 'Johnson',
        'marcus.j@outlook.com', '+13105554392',
        '2025-12-01', NULL, 1),

    (3, 'G-003', 'Emily', 'Rodriguez',
        'emily.r@yahoo.com', '+17145558834',
        '2026-01-01', NULL, 1),

    (4, 'G-004', 'David', 'Park',
        'dpark@gmail.com', '+14085559121',
        '2025-06-01', NULL, 1),

    -- Sarah Chen v2: switched to ProtonMail — current version
    (5, 'G-001', 'Sarah', 'Chen',
        's.chen@protonmail.com', '+14155557821',
        '2026-02-15 10:00:00', NULL, 1);

-- -----------------------------------------------------------------------------
-- HOSTAWAY LISTINGS
-- Full API snapshot — pricing, capacity, policies, check-in windows.
-- One per active property.
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_listings (
    hostaway_listing_id, property_key, name, internal_listing_name,
    address, city, state, country, country_code, zipcode, lat, lng,
    person_capacity, bedrooms_number, beds_number, bathrooms_number, guest_bathrooms_number,
    price, cleaning_fee, price_for_extra_person, min_nights, max_nights,
    cancellation_policy, check_in_time_start, check_in_time_end, check_out_time,
    instant_bookable, allow_same_day_booking,
    amenities_json, last_synced_at
) VALUES
    -- Cottage 3: $200/night, sleeps 6, 3 bed / 2 bath, Big Bear Lake
    ('HA-001', 'PROP-001', 'Cottage 3', 'Cottage 3 — Big Bear Lake',
     '789 Lakeview Dr, Big Bear Lake, CA 92315',
     'Big Bear Lake', 'CA', 'USA', 'US', '92315', 34.2439, -116.9114,
     6, 3, 4, 2.0, 1.0,
     200.00, 150.00, 25.00, 2, 30,
     'moderate', 15, 20, 11,
     1, 0,
     '["WiFi","Hot Tub","BBQ Grill","Fire Pit","Lake View","Free Parking","Washer/Dryer","Full Kitchen","Pet Friendly"]',
     '2026-02-22 00:00:00'),

    -- Beach House 1: $220/night, sleeps 8, 4 bed / 3 bath, Malibu
    ('HA-002', 'PROP-002', 'Beach House 1', 'Beach House 1 — Malibu',
     '125 Pacific Coast Hwy, Malibu, CA 90265',
     'Malibu', 'CA', 'USA', 'US', '90265', 34.0259, -118.7798,
     8, 4, 6, 3.0, 2.0,
     220.00, 175.00, 30.00, 3, 14,
     'strict', 15, 18, 10,
     0, 0,
     '["WiFi","Ocean View","Private Beach Access","Kayak","BBQ Grill","Pet Friendly","Hot Tub","Outdoor Shower","Free Parking"]',
     '2026-02-22 00:00:00'),

    -- Mountain Cabin A: $195/night, sleeps 6, 3 bed / 2 bath, South Lake Tahoe
    ('HA-003', 'PROP-003', 'Mountain Cabin A', 'Mountain Cabin A — South Lake Tahoe',
     '456 Pine Ridge Rd, South Lake Tahoe, CA 96150',
     'South Lake Tahoe', 'CA', 'USA', 'US', '96150', 38.9399, -119.9772,
     6, 3, 4, 2.0, 1.0,
     195.00, 150.00, 25.00, 2, 21,
     'moderate', 16, 20, 10,
     1, 0,
     '["WiFi","Hot Tub","Fireplace","Snowshoe Equipment","Sleds","Star Gazing Deck","Free Parking","Full Kitchen"]',
     '2026-02-22 00:00:00');

-- -----------------------------------------------------------------------------
-- OPENPHONE PHONE NUMBERS
-- Maps our Quo numbers (PN... IDs) to labels / properties.
-- -----------------------------------------------------------------------------
INSERT INTO openphone_phone_numbers (openphone_number_id, phone_number, label, property_id)
VALUES ('PN-001', '+18185550001', 'Main Ops Line', NULL);

-- -----------------------------------------------------------------------------
-- RESERVATIONS — v2: includes guest counts, financials, hostaway_listing_id
-- guest_id and property_id reference the surrogate active at booking time.
-- -----------------------------------------------------------------------------
INSERT INTO reservations (
    id, hostaway_reservation_id, guest_id, property_id, hostaway_listing_id,
    check_in, check_out, status, channel,
    adults, children, infants, pets,
    base_rate, cleaning_fee, platform_fee, total_price, remaining_balance,
    total_amount
) VALUES
    -- Marcus Johnson / Beach House 1 v2
    -- 7 nights × $185/night = $1,295 + $150 cleaning + $95 Airbnb fee = $1,540
    (1, 'R-1001', 2, 5, 'HA-002',
     '2026-02-01', '2026-02-08', 'checked_out', 'airbnb',
     3, 0, 0, 1,
     1295.00, 150.00, 95.00, 1540.00, 0.00,
     1540.00),

    -- Emily Rodriguez / Mountain Cabin A
    -- 4 nights × $175/night = $700 + $150 cleaning + $70 direct booking = $920
    (2, 'R-1002', 3, 3, 'HA-003',
     '2026-02-25', '2026-03-01', 'confirmed', 'direct',
     4, 0, 0, 0,
     700.00, 150.00, 70.00, 920.00, 920.00,
     920.00),

    -- Sarah Chen v1 / Cottage 3 — guest_id=1 (v1 was active Feb 1 at booking time)
    -- 5 nights × $200/night = $1,000 + $150 cleaning + $100 VRBO fee = $1,250
    (3, 'R-1003', 1, 1, 'HA-001',
     '2026-03-05', '2026-03-10', 'confirmed', 'vrbo',
     2, 0, 0, 0,
     1000.00, 150.00, 100.00, 1250.00, 1250.00,
     1250.00),

    -- David Park / Beach House 1 v2 (Jan 2026 stay, v2 active since Jan 1)
    -- 5 nights × $176/night = $880 + $150 cleaning + $70 Airbnb = $1,100
    (4, 'R-1004', 4, 5, 'HA-002',
     '2026-01-10', '2026-01-15', 'checked_out', 'airbnb',
     2, 0, 0, 0,
     880.00, 150.00, 70.00, 1100.00, 0.00,
     1100.00);

-- -----------------------------------------------------------------------------
-- HOSTAWAY CONVERSATIONS & MESSAGES
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_conversations (id, hostaway_conversation_id, reservation_id, channel) VALUES
    (1, 'HC-1001', 1, 'airbnb'),
    (2, 'HC-1002', 2, 'direct'),
    (3, 'HC-1003', 3, 'vrbo'),
    (4, 'HC-1004', 4, 'airbnb');

-- Marcus Johnson ↔ Beach House 1
INSERT INTO hostaway_messages (conversation_id, sender_type, body, sent_at) VALUES
    (1, 'guest', 'Hey, just confirmed my booking. Will I receive check-in instructions soon?',                                    '2026-01-28 09:12:00'),
    (1, 'host',  'Hi Marcus! Full check-in instructions arrive 48 hours before arrival, including the digital lock code.',        '2026-01-28 10:05:00'),
    (1, 'guest', 'Perfect. Also — is the kayak still available for guests?',                                                      '2026-01-28 10:22:00'),
    (1, 'host',  'Yes! Kayak is in the shed by the dock; life vests on the wall hooks. Enjoy!',                                  '2026-01-28 10:45:00'),
    (1, 'guest', 'Awesome! See you February 1st.',                                                                                '2026-01-28 10:48:00'),
    (1, 'guest', 'Just a note — garbage disposal isn''t working. Not urgent at all.',                                             '2026-02-07 14:30:00'),
    (1, 'host',  'Thanks for letting us know Marcus! We''ll service it during turnover. Sorry for the trouble.',                  '2026-02-07 14:55:00');

-- Emily Rodriguez ↔ Mountain Cabin A
INSERT INTO hostaway_messages (conversation_id, sender_type, body, sent_at) VALUES
    (2, 'guest', 'Hi! Booked Mountain Cabin A for Feb 25 - Mar 1. Any local activity recommendations?',                          '2026-02-14 11:00:00'),
    (2, 'host',  'Hi Emily! Late February is magical up there. Ski resorts are 20 min away, snowshoeing trails are on property, and the hot tub runs 24/7.', '2026-02-14 11:45:00'),
    (2, 'guest', 'Perfect! We''ll have 4 adults. Is there enough bedding?',                                                       '2026-02-14 12:10:00'),
    (2, 'host',  'Absolutely — two king bedrooms plus a queen loft. Sleeps 6 comfortably!',                                      '2026-02-14 12:30:00');

-- Sarah Chen ↔ Cottage 3
INSERT INTO hostaway_messages (conversation_id, sender_type, body, sent_at) VALUES
    (3, 'guest', 'Hi! Just booked Cottage 3 for March 5-10. So excited for our stay!',                                           '2026-02-01 08:30:00'),
    (3, 'host',  'Welcome Sarah! We''re thrilled to have you. Cottage 3 is stunning in early March.',                            '2026-02-01 09:00:00'),
    (3, 'guest', 'Quick question — is there parking for two cars? We''re each driving.',                                         '2026-02-03 14:15:00'),
    (3, 'host',  'Absolutely! Two-car garage plus overflow in the driveway. No problem.',                                        '2026-02-03 14:45:00'),
    (3, 'guest', 'Wonderful. One more thing — could we do an early check-in around 1pm if possible?',                            '2026-02-18 16:00:00'),
    (3, 'host',  'Let me check with housekeeping. I''ll confirm by end of day!',                                                 '2026-02-18 16:30:00');

-- David Park ↔ Beach House 1
INSERT INTO hostaway_messages (conversation_id, sender_type, body, sent_at) VALUES
    (4, 'guest', 'Hello! Looking forward to our stay at Beach House 1 next week.',                      '2026-01-08 10:00:00'),
    (4, 'host',  'Hi David! Great to have you back. Anything you need before arrival?',                 '2026-01-08 10:30:00'),
    (4, 'guest', 'Just making sure the WiFi password hasn''t changed.',                                 '2026-01-08 10:45:00'),
    (4, 'host',  'Same password as last time: BeachWave2024. See you on the 10th!',                    '2026-01-08 11:00:00');

-- -----------------------------------------------------------------------------
-- OPENPHONE CALLS — v2: status, answered_at, call_route, phone_number_id
-- Call 3: Emily's missed call on check-in day → triggers voicemail
-- -----------------------------------------------------------------------------
INSERT INTO openphone_calls (
    id, openphone_call_id,
    openphone_phone_number_id, guest_id,
    guest_phone, our_phone, direction,
    status, duration_seconds,
    started_at, answered_at, ended_at,
    call_route, summary
) VALUES
    -- Marcus Johnson (inbound, answered, parking + pet policy)
    (1, 'OP-CALL-001', 'PN-001', 2,
     '+13105554392', '+18185550001', 'inbound',
     'completed', 262,
     '2026-01-30 15:30:00', '2026-01-30 15:30:08', '2026-01-30 15:34:22',
     'phone-number',
     'Marcus called to confirm parking and ask about pet policy. Confirmed pet-friendly with $50 deposit — added to reservation.'),

    -- Sarah Chen v2 (guest_id=5: post-email-change version was current on Feb 19)
    (2, 'OP-CALL-002', 'PN-001', 5,
     '+14155557821', '+18185550001', 'inbound',
     'completed', 185,
     '2026-02-19 10:15:00', '2026-02-19 10:15:06', '2026-02-19 10:18:05',
     'phone-number',
     'Sarah called to confirm 1pm early check-in and asked about the fire pit. Both confirmed.'),

    -- Emily Rodriguez: missed call on check-in day → goes to voicemail
    (3, 'OP-CALL-003', 'PN-001', 3,
     '+17145558834', '+18185550001', 'inbound',
     'missed', 0,
     '2026-02-25 16:47:00', NULL, '2026-02-25 16:47:22',
     'phone-number',
     NULL);

-- Marcus Johnson call transcript
INSERT INTO openphone_call_transcripts (
    call_id, transcript_status, speaker, speaker_phone,
    text, start_seconds, end_seconds, timestamp_offset_seconds
) VALUES
    (1, 'completed', 'host',  '+18185550001', 'Good afternoon, property management, how can I help?',                                       0,   4,  0),
    (1, 'completed', 'guest', '+13105554392', 'Hi, this is Marcus Johnson. I have a reservation at Beach House 1 starting February 1st.',    5,  12,  5),
    (1, 'completed', 'host',  '+18185550001', 'Of course, hi Marcus! Looking forward to your stay. What can I help with?',                  13,  19, 13),
    (1, 'completed', 'guest', '+13105554392', 'I wanted to confirm parking — I''m driving up from San Diego with my truck.',                 20,  31, 20),
    (1, 'completed', 'host',  '+18185550001', 'No problem. The driveway fits two to three vehicles comfortably.',                           32,  43, 32),
    (1, 'completed', 'guest', '+13105554392', 'Great. Also — can we bring our dog? Golden retriever, very well-behaved.',                   44,  55, 44),
    (1, 'completed', 'host',  '+18185550001', 'Good news — Beach House 1 is pet-friendly. There''s a $50 pet deposit I can add now.',       56,  73, 56),
    (1, 'completed', 'guest', '+13105554392', 'Perfect, let''s do it. Thank you!',                                                          74,  81, 74),
    (1, 'completed', 'host',  '+18185550001', 'Done! Reservation updated. Looking forward to hosting you February 1st, Marcus.',            82,  92, 82),
    (1, 'completed', 'guest', '+13105554392', 'Appreciate it. See you then. Bye!',                                                          93, 103, 93);

-- Sarah Chen call transcript
INSERT INTO openphone_call_transcripts (
    call_id, transcript_status, speaker, speaker_phone,
    text, start_seconds, end_seconds, timestamp_offset_seconds
) VALUES
    (2, 'completed', 'host',  '+18185550001', 'Hello, property management, how can I help?',                                                  0,   3,  0),
    (2, 'completed', 'guest', '+14155557821', 'Hi, this is Sarah Chen. I have an upcoming stay at Cottage 3 on March 5th.',                   4,  10,  4),
    (2, 'completed', 'host',  '+18185550001', 'Hi Sarah! I have your reservation right here. How can I help?',                               11,  17, 11),
    (2, 'completed', 'guest', '+14155557821', 'Wanted to confirm the 1pm early check-in we texted about — is that locked in?',               18,  26, 18),
    (2, 'completed', 'host',  '+18185550001', 'Yes! Housekeeping confirmed. You''re all set for a 1pm arrival on March 5th.',                27,  39, 27),
    (2, 'completed', 'guest', '+14155557821', 'Perfect. Also — does the property have a fire pit? My husband is really hoping.',              40,  50, 40),
    (2, 'completed', 'host',  '+18185550001', 'Yes! There''s a beautiful stone fire pit in the backyard, and we provide firewood.',           51,  64, 51),
    (2, 'completed', 'guest', '+14155557821', 'That''s amazing. We are going to love it. Thank you!',                                        65,  72, 65),
    (2, 'completed', 'host',  '+18185550001', 'We''re so excited for you. See you on March 5th, Sarah!',                                     73,  80, 73);

-- No transcript for call 3 (Emily): call was missed → went to voicemail

-- -----------------------------------------------------------------------------
-- OPENPHONE VOICEMAILS — v2: new table
-- Emily left a voicemail after her missed call on check-in day.
-- call_id=3 (the missed call)
-- -----------------------------------------------------------------------------
INSERT INTO openphone_voicemails (
    call_id, voicemail_status, transcript, duration_seconds,
    recording_url, created_at, processed_at
) VALUES (
    3, 'completed',
    'Hi this is Emily Rodriguez, I just checked into Mountain Cabin A. The hot tub seems like it is only around 95 degrees — not sure if it needs more time to heat up. Also the front door keypad took a few tries on the first attempt, might want to check that. Otherwise the place is absolutely beautiful, we love it. Thanks so much!',
    38,
    'https://recordings.openphone.co/OP-CALL-003/voicemail.mp3',
    '2026-02-25 16:47:30',
    '2026-02-25 16:48:15'
);

-- -----------------------------------------------------------------------------
-- OPENPHONE SMS — v2: includes status (delivery) and openphone_phone_number_id
-- Inbound messages have no delivery status (they arrive; no tracking needed).
-- Outbound messages carry Quo's delivery status.
-- -----------------------------------------------------------------------------

-- Sarah Chen v1 (guest_id=1) — Jan 15, initial inquiry before email change
INSERT INTO openphone_sms_messages (
    openphone_sms_id, openphone_phone_number_id, guest_id,
    guest_phone, our_phone, direction, body, status, sent_at
) VALUES
    ('SMS-001', 'PN-001', 1, '+14155557821', '+18185550001', 'inbound',
     'Hi, this is Sarah. Interested in Cottage 3 for early March — is it still available?',
     NULL, '2026-01-15 13:05:00'),
    ('SMS-002', 'PN-001', 1, '+14155557821', '+18185550001', 'outbound',
     'Hi Sarah! Yes, Cottage 3 is open March 5-10. Sending the booking link now.',
     'delivered', '2026-01-15 13:12:00'),
    ('SMS-003', 'PN-001', 1, '+14155557821', '+18185550001', 'inbound',
     'Booked! So excited. Quick question — is the hot tub working?',
     NULL, '2026-01-15 13:30:00'),
    ('SMS-004', 'PN-001', 1, '+14155557821', '+18185550001', 'outbound',
     'Yes! Hot tub is fully operational and seats 6. You''ll love it.',
     'delivered', '2026-01-15 13:38:00');

-- Sarah Chen v2 (guest_id=5) — Feb 18-19, after she updated her email on Feb 15
INSERT INTO openphone_sms_messages (
    openphone_sms_id, openphone_phone_number_id, guest_id,
    guest_phone, our_phone, direction, body, status, sent_at
) VALUES
    ('SMS-005', 'PN-001', 5, '+14155557821', '+18185550001', 'outbound',
     'Hi Sarah! Check-in is March 5th. Gate: 4821 · Door: 7392. Any questions, just text!',
     'delivered', '2026-02-18 09:00:00'),
    ('SMS-006', 'PN-001', 5, '+14155557821', '+18185550001', 'inbound',
     'Thank you! Any chance we could do a 1pm early check-in instead of 3pm?',
     NULL, '2026-02-18 09:45:00'),
    ('SMS-007', 'PN-001', 5, '+14155557821', '+18185550001', 'outbound',
     'Let me check with housekeeping and get back to you by end of day!',
     'delivered', '2026-02-18 09:50:00');

-- Marcus Johnson (guest_id=2)
INSERT INTO openphone_sms_messages (
    openphone_sms_id, openphone_phone_number_id, guest_id,
    guest_phone, our_phone, direction, body, status, sent_at
) VALUES
    ('SMS-010', 'PN-001', 2, '+13105554392', '+18185550001', 'inbound',
     'Hi! Marcus here. Just confirmed Beach House 1. Really looking forward to it.',
     NULL, '2026-01-28 08:55:00'),
    ('SMS-011', 'PN-001', 2, '+13105554392', '+18185550001', 'outbound',
     'Great to hear from you Marcus! Excited to host you. Anything I can help with?',
     'delivered', '2026-01-28 09:10:00'),
    ('SMS-012', 'PN-001', 2, '+13105554392', '+18185550001', 'outbound',
     'Marcus — check-in day! Lock code is #2249. Text if anything comes up. Enjoy!',
     'delivered', '2026-02-01 08:00:00'),
    ('SMS-013', 'PN-001', 2, '+13105554392', '+18185550001', 'inbound',
     'Quick heads up — the garbage disposal isn''t working. Not urgent.',
     NULL, '2026-02-07 14:20:00'),
    ('SMS-014', 'PN-001', 2, '+13105554392', '+18185550001', 'outbound',
     'So sorry! We''ll fix it during turnover. Do you need it working before checkout tomorrow?',
     'delivered', '2026-02-07 14:35:00'),
    ('SMS-015', 'PN-001', 2, '+13105554392', '+18185550001', 'inbound',
     'No worries, we managed fine. Thanks for the quick reply!',
     NULL, '2026-02-07 14:50:00'),
    ('SMS-016', 'PN-001', 2, '+13105554392', '+18185550001', 'outbound',
     'Hope checkout was smooth! Thanks for taking great care of the place. A review would mean the world!',
     'delivered', '2026-02-08 12:00:00');

-- Emily Rodriguez (guest_id=3)
INSERT INTO openphone_sms_messages (
    openphone_sms_id, openphone_phone_number_id, guest_id,
    guest_phone, our_phone, direction, body, status, sent_at
) VALUES
    ('SMS-020', 'PN-001', 3, '+17145558834', '+18185550001', 'inbound',
     'Hi! Emily here. Looking forward to Mountain Cabin A! Is snowshoeing gear available?',
     NULL, '2026-02-10 10:30:00'),
    ('SMS-021', 'PN-001', 3, '+17145558834', '+18185550001', 'outbound',
     'Hi Emily! Two pairs of snowshoes in the garage + sleds for the hills. Super fun!',
     'delivered', '2026-02-10 10:42:00'),
    ('SMS-022', 'PN-001', 3, '+17145558834', '+18185550001', 'outbound',
     'Emily — confirming Feb 25 arrival at Mountain Cabin A. Door code: 6614. Can''t wait!',
     'delivered', '2026-02-18 09:00:00'),
    ('SMS-023', 'PN-001', 3, '+17145558834', '+18185550001', 'inbound',
     'Perfect! We are so excited. Will the hot tub be cleaned and ready?',
     NULL, '2026-02-18 09:30:00'),
    ('SMS-024', 'PN-001', 3, '+17145558834', '+18185550001', 'outbound',
     'Absolutely — hot tub will be fresh and set to 104°F for your arrival.',
     'delivered', '2026-02-18 09:45:00');

-- -----------------------------------------------------------------------------
-- GMAIL THREADS & EMAILS
-- -----------------------------------------------------------------------------
INSERT INTO gmail_threads (id, gmail_thread_id, subject, guest_id, reservation_id) VALUES
    (1, 'GT-001', 'Reservation Confirmation — Beach House 1, Feb 1-8 | Booking #R-1001', 2, 1),
    -- Thread 2: guest_id=1 (Sarah v1 was active on Feb 18 when this email was sent)
    (2, 'GT-002', 'Pre-Arrival Instructions — Cottage 3, March 5-10 | Booking #R-1003', 1, 3),
    (3, 'GT-003', 'Your Upcoming Stay — Mountain Cabin A, Feb 25-Mar 1 | Booking #R-1002', 3, 2);

INSERT INTO gmail_emails (gmail_message_id, thread_id, from_email, to_email, subject, body_text, sent_at, labels) VALUES
    ('GM-001', 1, 'host@propertymgmt.com', 'marcus.j@outlook.com',
     'Reservation Confirmation — Beach House 1, Feb 1-8 | Booking #R-1001',
     'Dear Marcus, Thank you for booking Beach House 1 for February 1-8. Booking #R-1001 confirmed. Total: $1,540. Check-in 3pm, check-out 11am. Full instructions 48 hours before arrival. Don''t hesitate to reach out. Warm regards, The Management Team',
     '2026-01-25 10:00:00', '["inbox","sent","reservation"]'),
    ('GM-002', 1, 'marcus.j@outlook.com', 'host@propertymgmt.com',
     'Re: Reservation Confirmation — Beach House 1, Feb 1-8 | Booking #R-1001',
     'Thanks for the confirmation! Two questions: is the kayak available for guests? And we''re hoping to bring our dog — is the property pet-friendly?',
     '2026-01-25 14:22:00', '["inbox","reservation"]'),
    ('GM-003', 1, 'host@propertymgmt.com', 'marcus.j@outlook.com',
     'Re: Reservation Confirmation — Beach House 1, Feb 1-8 | Booking #R-1001',
     'Hi Marcus! Kayak is available — stored in the dock shed with life vests. And yes, Beach House 1 is pet-friendly! Added a $50 pet deposit; you''ll see the updated total in the Airbnb app. Looking forward to hosting you and your pup! The Management Team',
     '2026-01-26 09:15:00', '["inbox","sent","reservation"]');

INSERT INTO gmail_emails (gmail_message_id, thread_id, from_email, to_email, subject, body_text, sent_at, labels) VALUES
    ('GM-010', 2, 'host@propertymgmt.com', 'sarah.chen@gmail.com',
     'Pre-Arrival Instructions — Cottage 3, March 5-10 | Booking #R-1003',
     'Dear Sarah, Your stay at Cottage 3 is almost here! Gate: 4821 · Door: 7392 · Check-in: 3pm (early may be possible — text us). Parking: 2-car garage + driveway. WiFi: CottageGuest / lake2024. Hot tub is heated. Firewood on back porch. We can''t wait to host you! The Management Team',
     '2026-02-18 09:00:00', '["inbox","sent","check-in"]'),
    ('GM-011', 2, 'sarah.chen@gmail.com', 'host@propertymgmt.com',
     'Re: Pre-Arrival Instructions — Cottage 3, March 5-10 | Booking #R-1003',
     'Thank you! This is so helpful. We texted about a 1pm arrival — has that been confirmed? Also, what''s the cell service like at the property?',
     '2026-02-18 10:30:00', '["inbox","check-in"]'),
    ('GM-012', 2, 'host@propertymgmt.com', 'sarah.chen@gmail.com',
     'Re: Pre-Arrival Instructions — Cottage 3, March 5-10 | Booking #R-1003',
     'Hi Sarah! Great news — 1pm early check-in confirmed, no extra charge. Cell service: 1-2 bars AT&T/T-Mobile in most areas; WiFi is very reliable at 500 Mbps. See you March 5th! The Management Team',
     '2026-02-19 11:00:00', '["inbox","sent","check-in"]');

INSERT INTO gmail_emails (gmail_message_id, thread_id, from_email, to_email, subject, body_text, sent_at, labels) VALUES
    ('GM-020', 3, 'host@propertymgmt.com', 'emily.r@yahoo.com',
     'Your Upcoming Stay — Mountain Cabin A, Feb 25-Mar 1 | Booking #R-1002',
     'Dear Emily, We''re so excited to welcome you to Mountain Cabin A! Door: 6614 · Check-in: 4pm. Two king bedrooms + queen loft (sleeps 6). Hot tub cleaned day-of. Two snowshoe pairs in garage. Ski resorts 20 min away. Pantry stocked with breakfast basics. See you soon! The Management Team',
     '2026-02-12 10:00:00', '["inbox","sent","reservation"]'),
    ('GM-021', 3, 'emily.r@yahoo.com', 'host@propertymgmt.com',
     'Re: Your Upcoming Stay — Mountain Cabin A, Feb 25-Mar 1 | Booking #R-1002',
     'This looks wonderful, thank you! We''ll have 4 adults, no children. Is there a grocery store within 15 minutes? Also — is there a good spot for stargazing?',
     '2026-02-14 09:45:00', '["inbox","reservation"]'),
    ('GM-022', 3, 'host@propertymgmt.com', 'emily.r@yahoo.com',
     'Re: Your Upcoming Stay — Mountain Cabin A, Feb 25-Mar 1 | Booking #R-1002',
     'Hi Emily! 4 adults is perfect. There''s a Safeway about 12 minutes away (address in your door-code text). Stargazing is INCREDIBLE from the back deck — zero light pollution. Hot tub + clear sky is our guests'' favorite combo. You are going to love it! The Management Team',
     '2026-02-14 14:00:00', '["inbox","sent","reservation"]');

-- -----------------------------------------------------------------------------
-- DISCORD CHANNELS
-- property_id references the current (long-lived) surrogate — channels are
-- created once and not version-specific.
-- -----------------------------------------------------------------------------
INSERT INTO discord_channels (id, discord_channel_id, channel_name, server_name, property_id) VALUES
    (1, 'DC-001', 'cottage-3-ops',        'Property Ops HQ', 1),
    (2, 'DC-002', 'beach-house-1-ops',    'Property Ops HQ', 5),
    (3, 'DC-003', 'mountain-cabin-a-ops', 'Property Ops HQ', 3),
    (4, 'DC-004', 'general',              'Property Ops HQ', NULL);

-- Cottage 3 ops channel — maintenance thread (February 2026)
INSERT INTO discord_messages (discord_message_id, channel_id, author_username, author_display_name, content, sent_at) VALUES
    ('DM-001', 1, 'mgr_tony',    'Tony (Manager)',
     'Heads up — guest in Cottage 3 reported the hot tub isn''t heating to temp. Came in about an hour ago.',
     '2026-02-03 11:15:00'),
    ('DM-002', 1, 'ops_rena',    'Rena (Ops)',
     'On it. Pool tech Marco is available tomorrow morning — scheduling him for 9am.',
     '2026-02-03 11:30:00'),
    ('DM-003', 1, 'vendor_marco','Marco (Pool Tech)',
     'Hot tub issue at Cottage 3 resolved. Replaced the faulty heating element. Running at 104°F.',
     '2026-02-04 10:45:00'),
    ('DM-004', 1, 'ops_rena',    'Rena (Ops)',
     'HVAC filter at Cottage 3 is overdue. Scheduling replacement for the Feb 15 turnover window.',
     '2026-02-12 14:00:00'),
    ('DM-005', 1, 'hskp_linda',  'Linda (Housekeeping)',
     'Cottage 3 turnover complete. HVAC filter replaced. Also caught a small leak under the kitchen sink — fixed on the spot. All clear.',
     '2026-02-15 16:20:00'),
    ('DM-006', 1, 'mgr_tony',    'Tony (Manager)',
     'New issue at Cottage 3: current guest reporting a broken window blind in the master bedroom. Adding to punch list for next turnover.',
     '2026-02-17 09:00:00'),
    ('DM-007', 1, 'hskp_linda',  'Linda (Housekeeping)',
     'Replaced the blind in Cottage 3 master bedroom during today''s inspection. Looks great. Marking resolved.',
     '2026-02-20 13:10:00');

INSERT INTO discord_messages (discord_message_id, channel_id, author_username, author_display_name, content, sent_at) VALUES
    ('DM-008', 1, 'ops_rena', 'Rena (Ops)',
     'Cottage 3 turnover confirmed for March 4 in prep for March 5-10 booking (Sarah Chen, VRBO).',
     '2026-02-20 09:00:00');

-- Beach House 1 ops
INSERT INTO discord_messages (discord_message_id, channel_id, author_username, author_display_name, content, sent_at, reservation_id) VALUES
    ('DM-010', 2, 'ops_rena',        'Rena (Ops)',
     'Marcus Johnson checked in at Beach House 1. Smooth arrival, no issues. Pet deposit collected.',
     '2026-02-01 15:30:00', 1),
    ('DM-011', 2, 'hskp_linda',      'Linda (Housekeeping)',
     'Marcus Johnson checked out of Beach House 1. Property in great shape. Left a thank-you card!',
     '2026-02-08 11:15:00', 1),
    ('DM-012', 2, 'mgr_tony',        'Tony (Manager)',
     'Garbage disposal at Beach House 1 needs repair before next guest. Scheduling maintenance for Feb 10.',
     '2026-02-08 12:00:00', NULL),
    ('DM-013', 2, 'vendor_handyman', 'Jake (Handyman)',
     'Beach House 1 garbage disposal replaced. Tightened a loose towel rack in main bath while there. All good.',
     '2026-02-10 14:30:00', NULL);

-- Mountain Cabin A pre-arrival + in-stay
INSERT INTO discord_messages (discord_message_id, channel_id, author_username, author_display_name, content, sent_at, reservation_id) VALUES
    ('DM-020', 3, 'ops_rena',  'Rena (Ops)',
     'Mountain Cabin A prep for Emily Rodriguez (Feb 25). Hot tub service booked Feb 24, housekeeping at 2pm. Stocking pantry basics.',
     '2026-02-18 10:00:00', 2),
    ('DM-021', 3, 'mgr_tony',  'Tony (Manager)',
     'Reminder: the Mountain Cabin A driveway had ice accumulation last week. Confirm salt/sand is stocked before Emily''s arrival.',
     '2026-02-19 09:30:00', 2);

-- General channel
INSERT INTO discord_messages (discord_message_id, channel_id, author_username, author_display_name, content, sent_at) VALUES
    ('DM-030', 4, 'mgr_tony', 'Tony (Manager)',
     'Team reminder: 3 properties active this weekend. Cottage 3 occupied, Beach House 1 turning over, Mountain Cabin A prepping. Stay sharp!',
     '2026-02-20 08:00:00');

-- -----------------------------------------------------------------------------
-- WHATSAPP CONVERSATIONS & MESSAGES — v2: new platform
-- Emily Rodriguez contacts us via WhatsApp on her check-in day (Feb 25).
-- Messages WM-002 and WM-004 are automated system responses (initiated_by='system').
-- They also appear in outbound_notifications below.
-- -----------------------------------------------------------------------------
INSERT INTO whatsapp_conversations (
    id, whatsapp_conversation_id, guest_id,
    guest_phone, our_phone,
    created_at, last_message_at
) VALUES (
    1, 'WC-001', 3,
    '+17145558834', '+18185550010',   -- +18185550010 = our WhatsApp Business number
    '2026-02-25 17:05:00', '2026-02-25 19:30:00'
);

INSERT INTO whatsapp_messages (
    whatsapp_msg_id, conversation_id, direction, body,
    status, sent_at, delivered_at, read_at
) VALUES
    -- Emily arrives, reports hot tub temp and keypad issue
    ('WM-001', 1, 'inbound',
     'Hi! Just checked in to Mountain Cabin A — it''s gorgeous! Quick thing: the hot tub seems to only be around 95°F, not 104°. Does it need more time to heat up? Also the front door keypad needed a few tries on the first attempt.',
     'read', '2026-02-25 17:05:00', NULL, NULL),

    -- Automated system response (LLM detected hot tub issue → auto-replied)
    ('WM-002', 1, 'outbound',
     'Hi Emily! So glad you love it! The hot tub typically needs 30-45 min to fully reheat after servicing. We''ve alerted our pool tech to do a remote check — you should hit 104°F within the hour. Enjoy your stay!',
     'read', '2026-02-25 17:12:00', '2026-02-25 17:12:05', '2026-02-25 17:13:22'),

    -- Emily follows up on keypad specifically
    ('WM-003', 1, 'inbound',
     'Perfect, thanks! One more thing on the keypad — we got it to work eventually but it took like 5 tries. Might just need a battery change?',
     'read', '2026-02-25 17:35:00', NULL, NULL),

    -- Automated system response (LLM detected keypad issue → auto-replied)
    ('WM-004', 1, 'outbound',
     'Thanks for flagging! You''re likely right — we''ll have maintenance check the battery this week. If you have any trouble, backup code is 0000. Enjoy the mountains!',
     'read', '2026-02-25 17:38:00', '2026-02-25 17:38:04', '2026-02-25 17:39:01'),

    -- Emily confirms hot tub is fixed
    ('WM-005', 1, 'inbound',
     'Hot tub is perfect now — exactly 104°F. Thank you!! The stars out here are incredible too. Perfect stay so far!',
     'read', '2026-02-25 19:30:00', NULL, NULL);

-- -----------------------------------------------------------------------------
-- DETECTED TRIGGERS — v2: new table
-- LLM detections from inbound messages across all platforms.
-- source_table + source_row_id = polymorphic pointer to the triggering message.
-- All five are resolved or acknowledged except DT-5 (keypad — still open).
-- -----------------------------------------------------------------------------

-- DT-1: Garbage disposal complaint — Marcus, Beach House 1, from SMS-013
INSERT INTO detected_triggers (
    detected_at, trigger_type, severity,
    source_platform, source_table, source_row_id,
    reservation_id, guest_id, property_id,
    raw_content, llm_reasoning, llm_model, llm_confidence,
    status, acknowledged_at, resolved_at, resolved_by
) VALUES (
    '2026-02-07 14:21:00', 'maintenance_issue', 'medium',
    'openphone_sms', 'openphone_sms_messages',
    (SELECT id FROM openphone_sms_messages WHERE openphone_sms_id = 'SMS-013'),
    1, 2, 5,
    'Quick heads up — the garbage disposal isn''t working. Not urgent.',
    'Guest explicitly reported a broken garbage disposal. Marked medium (guest noted non-urgent; checkout is tomorrow, so repair is needed before next guest arrives).',
    'claude-sonnet-4-6', 0.96,
    'resolved', '2026-02-07 14:21:45', '2026-02-10 14:30:00', 'system'
);

-- DT-2: Hot tub not heating — Cottage 3, from Discord DM-001 (no guest, property-level)
INSERT INTO detected_triggers (
    detected_at, trigger_type, severity,
    source_platform, source_table, source_row_id,
    reservation_id, guest_id, property_id,
    raw_content, llm_reasoning, llm_model, llm_confidence,
    status, acknowledged_at, resolved_at, resolved_by
) VALUES (
    '2026-02-03 11:16:00', 'maintenance_issue', 'high',
    'discord', 'discord_messages',
    (SELECT id FROM discord_messages WHERE discord_message_id = 'DM-001'),
    NULL, NULL, 1,
    'Heads up — guest in Cottage 3 reported the hot tub isn''t heating to temp. Came in about an hour ago.',
    'Manager reported guest complaint about hot tub temperature failure while guest is in-house. High severity: active guest impact, hot tub is a primary amenity. Immediate pool tech dispatch required.',
    'claude-sonnet-4-6', 0.98,
    'resolved', '2026-02-03 11:17:00', '2026-02-04 10:45:00', 'system'
);

-- DT-3: Early check-in scheduling request — Sarah Chen, Cottage 3, from SMS-006
INSERT INTO detected_triggers (
    detected_at, trigger_type, severity,
    source_platform, source_table, source_row_id,
    reservation_id, guest_id, property_id,
    raw_content, llm_reasoning, llm_model, llm_confidence,
    status, acknowledged_at, resolved_at, resolved_by
) VALUES (
    '2026-02-18 09:46:00', 'scheduling_problem', 'low',
    'openphone_sms', 'openphone_sms_messages',
    (SELECT id FROM openphone_sms_messages WHERE openphone_sms_id = 'SMS-006'),
    3, 5, 1,
    'Thank you! Any chance we could do a 1pm early check-in instead of 3pm?',
    'Guest is requesting a 2-hour early check-in on March 5. Low severity: no active conflict, just needs housekeeping schedule confirmation. Flagged for ops team to verify turnover window.',
    'claude-sonnet-4-6', 0.91,
    'resolved', '2026-02-18 09:47:00', '2026-02-19 11:00:00', 'system'
);

-- DT-4: Hot tub temp on arrival — Emily Rodriguez, Mountain Cabin A, from WhatsApp WM-001
INSERT INTO detected_triggers (
    detected_at, trigger_type, severity,
    source_platform, source_table, source_row_id,
    reservation_id, guest_id, property_id,
    raw_content, llm_reasoning, llm_model, llm_confidence,
    status, acknowledged_at, resolved_at, resolved_by
) VALUES (
    '2026-02-25 17:06:00', 'maintenance_issue', 'medium',
    'whatsapp', 'whatsapp_messages',
    (SELECT id FROM whatsapp_messages WHERE whatsapp_msg_id = 'WM-001'),
    2, 3, 3,
    'Hi! Just checked in to Mountain Cabin A — it''s gorgeous! Quick thing: the hot tub seems to only be around 95°F, not 104°. Does it need more time to heat up?',
    'Guest reported hot tub at 95°F instead of expected 104°F on check-in day. Medium severity: likely a reheating lag after same-day service, but needs pool tech confirmation. Guest also mentioned keypad issue (handled separately as DT-5).',
    'claude-sonnet-4-6', 0.89,
    'resolved', '2026-02-25 17:07:00', '2026-02-25 19:31:00', 'system'
);

-- DT-5: Front door keypad intermittent — Emily Rodriguez, Mountain Cabin A, from WhatsApp WM-003
-- OPEN: physical maintenance check not yet scheduled
INSERT INTO detected_triggers (
    detected_at, trigger_type, severity,
    source_platform, source_table, source_row_id,
    reservation_id, guest_id, property_id,
    raw_content, llm_reasoning, llm_model, llm_confidence,
    status, acknowledged_at, resolved_at, resolved_by
) VALUES (
    '2026-02-25 17:36:00', 'checkin_issue', 'medium',
    'whatsapp', 'whatsapp_messages',
    (SELECT id FROM whatsapp_messages WHERE whatsapp_msg_id = 'WM-003'),
    2, 3, 3,
    'One more thing on the keypad — we got it to work eventually but it took like 5 tries. Might just need a battery change?',
    'Guest is reporting the front door keypad requires multiple attempts to accept the code. Medium severity: guest has access but reliability is poor. Likely low-battery condition. Backup code provided; physical battery check needed before next guest.',
    'claude-sonnet-4-6', 0.93,
    'open', '2026-02-25 17:37:00', NULL, NULL
);

-- -----------------------------------------------------------------------------
-- OUTBOUND NOTIFICATIONS — v2: new table
-- Automated messages sent by the LLM system in response to detected triggers.
-- Does NOT include human-sent SMS/emails (those stay in their source tables).
-- platform_message_id for Discord entries = discord_message_id of the auto-post.
-- platform_message_id for WhatsApp entries = whatsapp_msg_id of the auto-reply.
-- -----------------------------------------------------------------------------

-- N-1: Discord alert to beach-house-1-ops for DT-1 (garbage disposal)
INSERT INTO outbound_notifications (
    trigger_id, platform, recipient, message_body, initiated_by, status,
    platform_message_id,
    reservation_id, guest_id, property_id,
    queued_at, sent_at, delivered_at
) VALUES (
    1, 'discord', 'DC-002',
    '🔧 MAINTENANCE | Beach House 1 (R-1001 · Marcus Johnson): Guest reported garbage disposal not working. Non-urgent — repair needed before next guest. Adding to turnover list.',
    'system', 'delivered', 'DM-AUTO-001',
    1, 2, 5,
    '2026-02-07 14:21:30', '2026-02-07 14:21:32', '2026-02-07 14:21:32'
);

-- N-2: Discord alert to cottage-3-ops for DT-2 (hot tub not heating — HIGH)
INSERT INTO outbound_notifications (
    trigger_id, platform, recipient, message_body, initiated_by, status,
    platform_message_id,
    reservation_id, guest_id, property_id,
    queued_at, sent_at, delivered_at
) VALUES (
    2, 'discord', 'DC-001',
    '🔴 HIGH PRIORITY | Cottage 3: Guest reported hot tub not reaching temperature — currently in-house. Immediate pool tech dispatch required. Contact Marco.',
    'system', 'delivered', 'DM-AUTO-002',
    NULL, NULL, 1,
    '2026-02-03 11:16:15', '2026-02-03 11:16:17', '2026-02-03 11:16:17'
);

-- N-3: Discord alert to cottage-3-ops for DT-3 (early check-in request)
INSERT INTO outbound_notifications (
    trigger_id, platform, recipient, message_body, initiated_by, status,
    platform_message_id,
    reservation_id, guest_id, property_id,
    queued_at, sent_at, delivered_at
) VALUES (
    3, 'discord', 'DC-001',
    '📅 SCHEDULING | Cottage 3 (R-1003 · Sarah Chen · check-in Mar 5): Guest requesting 1pm early check-in instead of 3pm. Please confirm turnover availability with housekeeping.',
    'system', 'delivered', 'DM-AUTO-003',
    3, 5, 1,
    '2026-02-18 09:46:30', '2026-02-18 09:46:32', '2026-02-18 09:46:32'
);

-- N-4: WhatsApp auto-reply to Emily for DT-4 (hot tub) — same message as WM-002
INSERT INTO outbound_notifications (
    trigger_id, platform, recipient, message_body, initiated_by, status,
    platform_message_id,
    reservation_id, guest_id, property_id,
    queued_at, sent_at, delivered_at
) VALUES (
    4, 'whatsapp', '+17145558834',
    'Hi Emily! So glad you love it! The hot tub typically needs 30-45 min to fully reheat after servicing. We''ve alerted our pool tech to do a remote check — you should hit 104°F within the hour. Enjoy your stay!',
    'system', 'delivered', 'WM-002',
    2, 3, 3,
    '2026-02-25 17:07:00', '2026-02-25 17:12:00', '2026-02-25 17:12:05'
);

-- N-5: Discord alert to mountain-cabin-a-ops for DT-4 (hot tub ops alert)
INSERT INTO outbound_notifications (
    trigger_id, platform, recipient, message_body, initiated_by, status,
    platform_message_id,
    reservation_id, guest_id, property_id,
    queued_at, sent_at, delivered_at
) VALUES (
    4, 'discord', 'DC-003',
    '🔧 MAINTENANCE | Mountain Cabin A (R-1002 · Emily Rodriguez): Guest reports hot tub at ~95°F on arrival. Likely reheating lag. Pool tech please do remote diagnostics. Target 104°F within 45 min.',
    'system', 'delivered', 'DM-AUTO-004',
    2, 3, 3,
    '2026-02-25 17:07:15', '2026-02-25 17:07:17', '2026-02-25 17:07:17'
);

-- N-6: WhatsApp auto-reply to Emily for DT-5 (keypad) — same message as WM-004
INSERT INTO outbound_notifications (
    trigger_id, platform, recipient, message_body, initiated_by, status,
    platform_message_id,
    reservation_id, guest_id, property_id,
    queued_at, sent_at, delivered_at
) VALUES (
    5, 'whatsapp', '+17145558834',
    'Thanks for flagging! You''re likely right — we''ll have maintenance check the battery this week. If you have any trouble, backup code is 0000. Enjoy the mountains!',
    'system', 'delivered', 'WM-004',
    2, 3, 3,
    '2026-02-25 17:37:00', '2026-02-25 17:38:00', '2026-02-25 17:38:04'
);

-- N-7: Discord alert to mountain-cabin-a-ops for DT-5 (keypad — still open)
INSERT INTO outbound_notifications (
    trigger_id, platform, recipient, message_body, initiated_by, status,
    platform_message_id,
    reservation_id, guest_id, property_id,
    queued_at, sent_at, delivered_at
) VALUES (
    5, 'discord', 'DC-003',
    '⚠️ OPEN ISSUE | Mountain Cabin A (R-1002): Front door keypad intermittent — guest needed 5 attempts. Backup code 0000 provided. Schedule battery check before next turnover.',
    'system', 'delivered', 'DM-AUTO-005',
    2, 3, 3,
    '2026-02-25 17:37:15', '2026-02-25 17:37:17', '2026-02-25 17:37:17'
);

-- -----------------------------------------------------------------------------
-- WEBHOOK INBOX — v2.1: raw ingest buffer for OpenPhone SMS webhooks
--
-- Three representative states:
--   WI-1: processed  — SMS-013 (Marcus garbage disposal), already mapped
--   WI-2: unprocessed — Emily post-stay review SMS, arrived, not yet mapped
--   WI-3: failed     — unknown caller inquiry, no matching guest, 2 attempts
-- -----------------------------------------------------------------------------

-- WI-1: processed — corresponds to SMS-013 (Marcus / garbage disposal)
INSERT INTO webhook_inbox (
    source, event_type, raw_payload, received_at,
    status, attempts, last_attempted_at, processed_at,
    processed_table, processed_row_id
) VALUES (
    'openphone', 'sms',
    '{"id":"SMS-013","phoneNumberId":"PN-001","userId":null,"from":"+13105554392","to":"+18185550001","text":"Quick heads up — the garbage disposal isn''t working. Not urgent.","status":"received","direction":"inbound","createdAt":"2026-02-07T14:20:00Z","conversationId":"CONV-MJ-002"}',
    '2026-02-07 14:20:01',
    'processed', 1, '2026-02-07 14:20:02', '2026-02-07 14:20:02',
    'openphone_sms_messages',
    (SELECT CAST(id AS TEXT) FROM openphone_sms_messages WHERE openphone_sms_id = 'SMS-013')
);

-- WI-2: unprocessed — Emily post-stay review text, just arrived
INSERT INTO webhook_inbox (
    source, event_type, raw_payload, received_at,
    status, attempts
) VALUES (
    'openphone', 'sms',
    '{"id":"SMS-030","phoneNumberId":"PN-001","userId":null,"from":"+17145558834","to":"+18185550001","text":"Hi just wanted to say we had the most amazing stay! Left a 5-star review on Airbnb. Hope to book again soon!","status":"received","direction":"inbound","createdAt":"2026-02-26T10:15:00Z","conversationId":"CONV-ER-001"}',
    '2026-02-26 10:15:01',
    'unprocessed', 0
);

-- WI-3: failed — unknown number, no matching guest, 2 attempts
INSERT INTO webhook_inbox (
    source, event_type, raw_payload, received_at,
    status, attempts, last_attempted_at,
    error_message
) VALUES (
    'openphone', 'sms',
    '{"id":"SMS-031","phoneNumberId":"PN-001","userId":null,"from":"+19995551234","to":"+18185550001","text":"Hi, do you have availability for next weekend? Looking for something for 4 adults.","status":"received","direction":"inbound","createdAt":"2026-02-22T09:00:00Z","conversationId":"CONV-UNK-001"}',
    '2026-02-22 09:00:02',
    'failed', 2, '2026-02-22 09:05:00',
    'No matching guest found for phone +19999551234. Cannot resolve guest_id. Manual review required.'
);

-- =============================================================================
-- v3 SEED DATA — Hostaway Phase 1 tables
-- Reference date: 2026-02-24
--
-- All 19 v3 tables seeded:
--   hostaway_users, hostaway_groups, hostaway_group_listings,
--   hostaway_listing_units, hostaway_reviews, hostaway_coupon_codes,
--   hostaway_custom_fields, hostaway_reference_data,
--   hostaway_message_templates, hostaway_tasks, hostaway_seasonal_rules,
--   hostaway_tax_settings, hostaway_guest_charges, hostaway_auto_charges,
--   hostaway_financial_reports, hostaway_owner_statements, hostaway_expenses,
--   hostaway_calendar, hostaway_webhook_configs
-- =============================================================================

-- -----------------------------------------------------------------------------
-- HOSTAWAY USERS (team members)
-- Emails stored PII-scrubbed per Jan Marc's privacy layer.
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_users (hostaway_user_id, first_name, last_name, email, role, is_active)
VALUES
    ('HU-001', 'Noah',   'Santos',    '[REDACTED]', 'admin',        1),
    ('HU-002', 'Maria',  'Gutierrez', '[REDACTED]', 'housekeeper',  1),
    ('HU-003', 'Carlos', 'Reyes',     '[REDACTED]', 'maintenance',  1);

-- -----------------------------------------------------------------------------
-- HOSTAWAY GROUPS (property portfolios)
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_groups (hostaway_group_id, name, is_active)
VALUES
    ('HG-001', 'Beach Portfolio',    1),
    ('HG-002', 'Mountain Portfolio', 1);

-- Junction: listings per group
INSERT INTO hostaway_group_listings (group_id, hostaway_listing_id)
VALUES
    ((SELECT id FROM hostaway_groups WHERE hostaway_group_id = 'HG-001'), 'HA-002'),
    ((SELECT id FROM hostaway_groups WHERE hostaway_group_id = 'HG-002'), 'HA-001'),
    ((SELECT id FROM hostaway_groups WHERE hostaway_group_id = 'HG-002'), 'HA-003');

-- -----------------------------------------------------------------------------
-- HOSTAWAY LISTING UNITS
-- Beach House 1 has a main house + detached guest studio.
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_listing_units (hostaway_unit_id, hostaway_listing_id, name, unit_number, is_active)
VALUES
    ('HU-L002-A', 'HA-002', 'Main House',   '1A', 1),
    ('HU-L002-B', 'HA-002', 'Guest Studio', '1B', 1);

-- -----------------------------------------------------------------------------
-- HOSTAWAY REVIEWS
-- Covering R-1001 (Marcus, Beach House 1, checked_out) and
-- R-1004 (David, Beach House 1, checked_out).
-- Reviewer names PII-scrubbed.
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_reviews (
    hostaway_review_id, reservation_id, hostaway_listing_id,
    overall_rating, category_ratings_json,
    review_content, host_reply, reviewer_name, submitted_at
) VALUES
    ('HR-001',
     1, 'HA-002',
     5.0,
     '{"cleanliness":5,"communication":5,"location":5,"accuracy":5,"value":4}',
     'Incredible beach house! The ocean view from the deck made every morning magical. Host was super responsive when we had a question about parking.',
     'Thank you so much! We loved hosting you and your group. Come back anytime!',
     '[REDACTED]',
     '2026-02-09 11:00:00'),

    ('HR-002',
     4, 'HA-002',
     4.0,
     '{"cleanliness":4,"communication":5,"location":5,"accuracy":4,"value":4}',
     'Great location right on the coast. Beach access was amazing. Hot tub was a nice bonus. Would book again.',
     'Glad you enjoyed the beach access! Hope to have you back.',
     '[REDACTED]',
     '2026-01-17 09:30:00');

-- -----------------------------------------------------------------------------
-- HOSTAWAY COUPON CODES
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_coupon_codes (
    hostaway_coupon_id, code, hostaway_listing_id,
    discount_type, discount_percent, max_uses, times_used,
    valid_from, valid_to, is_active
) VALUES
    -- 10% off any listing, unlimited, all 2026
    ('HC-001', 'WELCOME10', NULL,
     'percent', 10.0, NULL, 3,
     '2026-01-01', '2026-12-31', 1),

    -- $50 fixed off Beach House 1, summer 2026, 5-use cap
    ('HC-002', 'BEACH50', 'HA-002',
     'fixed', 50.0, 5, 1,
     '2026-06-01', '2026-08-31', 1);

-- discount_value for HC-002 (fixed $50):
UPDATE hostaway_coupon_codes SET discount_value = 50.0 WHERE hostaway_coupon_id = 'HC-002';

-- -----------------------------------------------------------------------------
-- HOSTAWAY CUSTOM FIELDS
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_custom_fields (
    hostaway_field_id, name, field_type, description,
    is_required, applies_to, is_active
) VALUES
    ('HF-001', 'Gate Code',        'text',    'Shared gate access code for the community', 0, 'listing',      1),
    ('HF-002', 'Pet Deposit Paid', 'boolean', 'Whether the pet damage deposit was collected', 0, 'reservation', 1),
    ('HF-003', 'Guest Source',     'select',  'How the guest first heard about our properties', 0, 'guest',    1);

-- -----------------------------------------------------------------------------
-- HOSTAWAY REFERENCE DATA (amenities, bed types, property types)
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_reference_data (category, hostaway_id, name, last_synced_at)
VALUES
    ('amenity',             'AM-001', 'WiFi',             '2026-02-22 00:00:00'),
    ('amenity',             'AM-002', 'Hot Tub',          '2026-02-22 00:00:00'),
    ('amenity',             'AM-003', 'BBQ Grill',        '2026-02-22 00:00:00'),
    ('amenity',             'AM-004', 'Free Parking',     '2026-02-22 00:00:00'),
    ('amenity',             'AM-005', 'Pet Friendly',     '2026-02-22 00:00:00'),
    ('bed_type',            'BT-001', 'King',             '2026-02-22 00:00:00'),
    ('bed_type',            'BT-002', 'Queen',            '2026-02-22 00:00:00'),
    ('bed_type',            'BT-003', 'Twin',             '2026-02-22 00:00:00'),
    ('property_type',       'PT-001', 'House',            '2026-02-22 00:00:00'),
    ('property_type',       'PT-002', 'Cabin',            '2026-02-22 00:00:00'),
    ('cancellation_policy', 'CP-001', 'Moderate',         '2026-02-22 00:00:00'),
    ('cancellation_policy', 'CP-002', 'Strict',           '2026-02-22 00:00:00');

-- -----------------------------------------------------------------------------
-- HOSTAWAY MESSAGE TEMPLATES
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_message_templates (
    hostaway_template_id, name, subject, body,
    trigger, channel, language, is_active
) VALUES
    ('HMT-001',
     'Booking Confirmation',
     'Your reservation is confirmed!',
     'Hi {{guest_first_name}}, your booking at {{listing_name}} from {{check_in}} to {{check_out}} is confirmed. We look forward to hosting you!',
     'reservation_confirmed', 'email', 'en', 1),

    ('HMT-002',
     'Check-In Instructions',
     'Your check-in details for tomorrow',
     'Hi {{guest_first_name}}, tomorrow is the day! Check-in is between {{check_in_start}} and {{check_in_end}}. Door code: {{door_code}}. WiFi: {{wifi_name}} / {{wifi_password}}. Enjoy your stay!',
     'check_in_instructions', 'email', 'en', 1),

    ('HMT-003',
     'Checkout Reminder',
     'Checkout reminder — see you next time!',
     'Hi {{guest_first_name}}, just a reminder that checkout is tomorrow at {{check_out_time}}. Please leave the key in the lockbox. We hope you had a wonderful stay!',
     'checkout', 'sms', 'en', 1);

-- -----------------------------------------------------------------------------
-- HOSTAWAY TASKS
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_tasks (
    hostaway_task_id, hostaway_listing_id, reservation_id,
    assigned_user_id, task_type, status, title, description,
    due_date, completed_at
) VALUES
    -- Post-checkout cleaning after R-1001 (Marcus, Beach House 1, checked out Feb 8)
    ('HT-001', 'HA-002', 1,
     'HU-002', 'cleaning', 'completed',
     'Post-checkout clean — Beach House 1',
     'Full turnover after R-1001. Check hot tub chemicals, replace towels/linens, restock welcome kit.',
     '2026-02-08', '2026-02-08 14:30:00'),

    -- Maintenance: keypad battery Mountain Cabin A (from DT-5)
    ('HT-002', 'HA-003', NULL,
     'HU-003', 'maintenance', 'pending',
     'Replace front door keypad battery — Mountain Cabin A',
     'Guest R-1002 reported keypad intermittent (needed 5 attempts). Replace 9V battery before next arrival.',
     '2026-02-27', NULL),

    -- Pre-arrival inspection Cottage 3 for R-1003 (Sarah, check-in Mar 5)
    ('HT-003', 'HA-001', 3,
     'HU-002', 'inspection', 'pending',
     'Pre-arrival inspection — Cottage 3',
     'Full walk-through before Sarah Chen arrival Mar 5. Verify hot tub temp, test appliances, confirm welcome kit stocked.',
     '2026-03-04', NULL);

-- -----------------------------------------------------------------------------
-- HOSTAWAY SEASONAL PRICING RULES
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_seasonal_rules (
    hostaway_rule_id, name, hostaway_listing_id,
    date_ranges_json, nightly_price, min_nights, is_active
) VALUES
    ('HSR-001', 'Summer Premium', 'HA-002',
     '[{"start":"2026-06-01","end":"2026-08-31"}]',
     299.00, 4, 1),

    ('HSR-002', 'Ski Season Peak', 'HA-003',
     '[{"start":"2025-12-15","end":"2026-03-15"}]',
     245.00, 3, 1),

    ('HSR-003', 'Holiday Week', 'HA-001',
     '[{"start":"2026-12-24","end":"2027-01-01"}]',
     280.00, 5, 1);

-- -----------------------------------------------------------------------------
-- HOSTAWAY TAX SETTINGS
-- NULL hostaway_listing_id = account-level default (applies to all listings)
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_tax_settings (
    hostaway_listing_id, tax_name, tax_type, tax_value, applies_to, is_active
) VALUES
    (NULL,     'CA State Transient Occupancy Tax', 'percent', 10.0, 'total', 1),
    (NULL,     'Local Tourism Assessment',          'percent',  1.5, 'total', 1),
    ('HA-002', 'Malibu City TOT',                  'percent',  2.0, 'total', 1);

-- -----------------------------------------------------------------------------
-- HOSTAWAY GUEST CHARGES
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_guest_charges (
    hostaway_charge_id, reservation_id, hostaway_listing_id,
    amount, currency, status, charge_type, description, payment_method
) VALUES
    -- Damage deposit for Marcus (R-1001) — pre-authorized, voided after clean checkout
    ('HGC-001', 1, 'HA-002',
     500.00, 'USD', 'voided',
     'damage_deposit', 'Standard damage deposit — pre-authorized, voided after clean checkout.', 'card'),

    -- Pet fee for Marcus (R-1001, brought a dog)
    ('HGC-002', 1, 'HA-002',
     75.00, 'USD', 'captured',
     'extra_guest', 'Pet fee — 1 dog.', 'card');

-- -----------------------------------------------------------------------------
-- HOSTAWAY AUTO-CHARGE RULES
-- amount stores the fraction (0.30 = 30% of total_price); app layer resolves.
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_auto_charges (
    hostaway_auto_charge_id, hostaway_listing_id,
    amount, currency, trigger, days_offset, is_active
) VALUES
    ('HAC-001', 'HA-002', 0.30, 'USD', 'on_booking',     0,  1),
    ('HAC-002', 'HA-002', 0.70, 'USD', 'before_checkin', -7, 1),
    ('HAC-003', 'HA-003', 1.00, 'USD', 'on_booking',     0,  1);

-- -----------------------------------------------------------------------------
-- HOSTAWAY FINANCIAL REPORTS
-- Per-reservation income breakdown for the two checked-out reservations.
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_financial_reports (
    hostaway_report_id, reservation_id, hostaway_listing_id,
    channel, check_in, check_out,
    accommodation_fare, cleaning_fee, platform_commission, net_income,
    currency, report_date
) VALUES
    ('HFR-001', 1, 'HA-002',
     'airbnb', '2026-02-01', '2026-02-08',
     1295.00, 150.00, 95.00, 1350.00, 'USD', '2026-02-09'),

    ('HFR-002', 4, 'HA-002',
     'airbnb', '2026-01-10', '2026-01-15',
     880.00, 150.00, 70.00, 960.00,   'USD', '2026-01-16');

-- -----------------------------------------------------------------------------
-- HOSTAWAY OWNER STATEMENTS
-- Monthly income rollup for Beach House 1 (most active listing).
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_owner_statements (
    hostaway_statement_id, hostaway_listing_id,
    period_start, period_end,
    total_income, total_expenses, net_income, status
) VALUES
    ('HOS-001', 'HA-002', '2026-01-01', '2026-01-31',  960.00,  75.00,  885.00, 'sent'),
    ('HOS-002', 'HA-002', '2026-02-01', '2026-02-28', 1350.00, 125.00, 1225.00, 'draft');

-- -----------------------------------------------------------------------------
-- HOSTAWAY EXPENSES
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_expenses (
    hostaway_expense_id, hostaway_listing_id, reservation_id,
    category, amount, currency, description, expense_date
) VALUES
    -- Hot tub pool tech dispatch, Cottage 3, Feb 3 (triggered by DT-2)
    ('HE-001', 'HA-001', NULL,
     'maintenance', 125.00, 'USD',
     'Emergency pool tech dispatch — hot tub thermostat adjustment.', '2026-02-03'),

    -- Supplies restock Beach House 1 after Marcus checkout
    ('HE-002', 'HA-002', 1,
     'supplies', 48.50, 'USD',
     'Welcome kit restock: toiletries, coffee pods, laundry pods, paper goods.', '2026-02-08'),

    -- Monthly Starlink for Mountain Cabin A
    ('HE-003', 'HA-003', NULL,
     'utilities', 89.99, 'USD',
     'Monthly Starlink subscription — Mountain Cabin A.', '2026-02-01');

-- -----------------------------------------------------------------------------
-- HOSTAWAY CALENDAR
-- Two weeks of dates for Cottage 3 (HA-001).
-- R-1003 (Sarah Chen) is blocked Mar 5–9 (check-in Mar 5, check-out Mar 10).
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_calendar (
    hostaway_listing_id, date, is_available, price, min_nights, last_synced_at
) VALUES
    ('HA-001', '2026-02-28', 1, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-01', 1, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-02', 1, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-03', 1, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-04', 1, 200.00, 2, '2026-02-24 06:00:00'),
    -- R-1003 blocked
    ('HA-001', '2026-03-05', 0, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-06', 0, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-07', 0, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-08', 0, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-09', 0, 200.00, 2, '2026-02-24 06:00:00'),
    -- Available after checkout
    ('HA-001', '2026-03-10', 1, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-11', 1, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-12', 1, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-13', 1, 200.00, 2, '2026-02-24 06:00:00'),
    ('HA-001', '2026-03-14', 1, 200.00, 2, '2026-02-24 06:00:00');

-- -----------------------------------------------------------------------------
-- HOSTAWAY WEBHOOK CONFIGS
-- The endpoint configured in Hostaway to POST reservation + message events.
-- -----------------------------------------------------------------------------
INSERT INTO hostaway_webhook_configs (
    hostaway_webhook_id, url, events_json, is_active
) VALUES
    ('HWC-001',
     'https://mcp.internal/webhooks/hostaway',
     '["reservation_created","reservation_updated","reservation_cancelled","new_message"]',
     1);
