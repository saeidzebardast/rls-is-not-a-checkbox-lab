insert into clients values (1, 'Jana', 'jana@example.com');
insert into bookings values (1, 1, gen_random_uuid(), now());
insert into plans values (1, 'Monthly', 49);
insert into audit_log values (1, 'x');
insert into client_notes values (1, 1, 'knee injury, no squats');
-- waitlist stays empty on purpose (empty-table probe rule)
