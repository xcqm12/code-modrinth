-- Seed all missing loaders with their relationships to project types and games
-- This fixes the issue where "Mod loader" dropdown is empty in the frontend

-- 1. Insert all missing loaders
INSERT INTO loaders (loader) VALUES
  ('forge'),
  ('fabric'),
  ('quilt'),
  ('neoforge'),
  ('liteloader'),
  ('rift'),
  ('minecraft'),
  ('optifine'),
  ('iris'),
  ('canvas'),
  ('vanilla'),
  ('datapack'),
  ('bukkit'),
  ('spigot'),
  ('paper'),
  ('purpur'),
  ('folia'),
  ('bungeecord'),
  ('waterfall'),
  ('velocity'),
  ('sponge')
ON CONFLICT (loader) DO NOTHING;

-- 2. Link mod loaders to their loader_fields (game_versions, client_side, server_side)
INSERT INTO loader_fields_loaders (loader_id, loader_field_id)
SELECT l.id, lf.id FROM loaders l CROSS JOIN loader_fields lf
WHERE l.loader = ANY(ARRAY['forge','fabric','quilt','neoforge','liteloader','rift'])
  AND lf.field = ANY(ARRAY['game_versions','client_side','server_side'])
ON CONFLICT DO NOTHING;

-- 3. Link resourcepack loader (minecraft) to game_versions
INSERT INTO loader_fields_loaders (loader_id, loader_field_id)
SELECT l.id, lf.id FROM loaders l CROSS JOIN loader_fields lf
WHERE l.loader = 'minecraft' AND lf.field = 'game_versions'
ON CONFLICT DO NOTHING;

-- 4. Link shader loaders to game_versions
INSERT INTO loader_fields_loaders (loader_id, loader_field_id)
SELECT l.id, lf.id FROM loaders l CROSS JOIN loader_fields lf
WHERE l.loader = ANY(ARRAY['optifine','iris','canvas','vanilla'])
  AND lf.field = 'game_versions'
ON CONFLICT DO NOTHING;

-- 5. Link datapack loader to game_versions
INSERT INTO loader_fields_loaders (loader_id, loader_field_id)
SELECT l.id, lf.id FROM loaders l CROSS JOIN loader_fields lf
WHERE l.loader = 'datapack' AND lf.field = 'game_versions'
ON CONFLICT DO NOTHING;

-- 6. Link plugin loaders to game_versions and side fields
INSERT INTO loader_fields_loaders (loader_id, loader_field_id)
SELECT l.id, lf.id FROM loaders l CROSS JOIN loader_fields lf
WHERE l.loader = ANY(ARRAY['bukkit','spigot','paper','purpur','folia','bungeecord','waterfall','velocity','sponge'])
  AND lf.field = ANY(ARRAY['game_versions','client_side','server_side'])
ON CONFLICT DO NOTHING;

-- 7. Link mod loaders to project types (mod + modpack)
INSERT INTO loaders_project_types (joining_loader_id, joining_project_type_id)
SELECT l.id, pt.id FROM loaders l CROSS JOIN project_types pt
WHERE l.loader = ANY(ARRAY['forge','fabric','quilt','neoforge','liteloader','rift'])
  AND pt.name = ANY(ARRAY['mod','modpack'])
ON CONFLICT DO NOTHING;

-- 8. Link mrpack to modpack project type
INSERT INTO loaders_project_types (joining_loader_id, joining_project_type_id)
SELECT l.id, pt.id FROM loaders l CROSS JOIN project_types pt
WHERE l.loader = 'mrpack' AND pt.name = 'modpack'
ON CONFLICT DO NOTHING;

-- 9. Link resourcepack loader to resourcepack project type
INSERT INTO loaders_project_types (joining_loader_id, joining_project_type_id)
SELECT l.id, pt.id FROM loaders l CROSS JOIN project_types pt
WHERE l.loader = 'minecraft' AND pt.name = 'resourcepack'
ON CONFLICT DO NOTHING;

-- 10. Link shader loaders to shader project type
INSERT INTO loaders_project_types (joining_loader_id, joining_project_type_id)
SELECT l.id, pt.id FROM loaders l CROSS JOIN project_types pt
WHERE l.loader = ANY(ARRAY['optifine','iris','canvas','vanilla'])
  AND pt.name = 'shader'
ON CONFLICT DO NOTHING;

-- 11. Link datapack loader to datapack project type
INSERT INTO loaders_project_types (joining_loader_id, joining_project_type_id)
SELECT l.id, pt.id FROM loaders l CROSS JOIN project_types pt
WHERE l.loader = 'datapack' AND pt.name = 'datapack'
ON CONFLICT DO NOTHING;

-- 12. Link plugin loaders to plugin project type
INSERT INTO loaders_project_types (joining_loader_id, joining_project_type_id)
SELECT l.id, pt.id FROM loaders l CROSS JOIN project_types pt
WHERE l.loader = ANY(ARRAY['bukkit','spigot','paper','purpur','folia','bungeecord','waterfall','velocity','sponge'])
  AND pt.name = 'plugin'
ON CONFLICT DO NOTHING;

-- 13. Link all loader+project_type combos to minecraft-java game
INSERT INTO loaders_project_types_games (loader_id, project_type_id, game_id)
SELECT lpt.joining_loader_id, lpt.joining_project_type_id, g.id
FROM loaders_project_types lpt CROSS JOIN games g
WHERE g.name = 'minecraft-java'
ON CONFLICT DO NOTHING;

-- 14. Also link mod loaders with modpack to minecraft-java via mrpack_loaders field
INSERT INTO loader_fields_loaders (loader_id, loader_field_id)
SELECT l.id, lf.id FROM loaders l CROSS JOIN loader_fields lf
WHERE l.loader = 'mrpack' AND lf.field = 'mrpack_loaders'
ON CONFLICT DO NOTHING;
