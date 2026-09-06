INSERT INTO project_members (project_id, user_id, role)
SELECT p.id, p.owner_id, 'owner'
FROM projects p
WHERE p.deleted_at IS NULL
  AND p.owner_id IS NOT NULL
ON CONFLICT (project_id, user_id) DO UPDATE
SET role = 'owner'
WHERE project_members.role <> 'owner';
