-- Phone numbers are now always stored as "+<digits>" (see internal/phone).
-- Earlier releases accepted "996..." and "+996..." as different accounts.
-- Convert only rows whose canonical form is unambiguous. When several
-- accounts collapse to the same number, leave all of them untouched:
-- merging accounts needs a manual decision. List such groups with:
--   SELECT '+' || regexp_replace(phone, '[^0-9]', '', 'g') AS canonical,
--          array_agg(id) FROM users WHERE phone IS NOT NULL
--   GROUP BY 1 HAVING count(*) > 1;

WITH candidates AS (
    SELECT id,
           phone,
           '+' || regexp_replace(phone, '[[:space:]().+-]', '', 'g') AS canonical
    FROM users
    WHERE phone IS NOT NULL
      AND phone ~ '^[[:space:]().+0-9-]+$'
      AND phone !~ '\+.*\+'
      AND regexp_replace(phone, '[[:space:]().+-]', '', 'g') ~ '^[0-9]{9,15}$'
),
groups AS (
    SELECT canonical, count(*) AS accounts
    FROM candidates
    GROUP BY canonical
)
UPDATE users AS u
SET phone = c.canonical,
    updated_at = now()
FROM candidates c
JOIN groups g ON g.canonical = c.canonical
WHERE u.id = c.id
  AND g.accounts = 1
  AND u.phone <> c.canonical;

UPDATE project_invites
SET phone = '+' || regexp_replace(phone, '[[:space:]().+-]', '', 'g')
WHERE phone ~ '^[[:space:]().+0-9-]+$'
  AND phone !~ '\+.*\+'
  AND regexp_replace(phone, '[[:space:]().+-]', '', 'g') ~ '^[0-9]{9,15}$'
  AND phone <> '+' || regexp_replace(phone, '[[:space:]().+-]', '', 'g');
