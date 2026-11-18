-- Older provider errors could contain request URLs or provider response text.
-- Keep ticket delivery_status while removing potentially sensitive diagnostics.
UPDATE support_tickets
SET delivery_error = NULL
WHERE delivery_error IS NOT NULL;
