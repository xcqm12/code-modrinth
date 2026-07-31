#!/usr/bin/env python3
"""
8h8g 数据同步工具
从 api.modrinth.com 获取项目/版本元数据，同步到本地自建实例。

用法:
  # 下载数据
  python sync.py --limit 100
  python sync.py --project-type mod --loaders fabric --limit 50
  python sync.py --limit 200 --metadata-only
  python sync.py --ids sodium iris lithium

  # 导入到本地实例（需设置 TARGET_AUTH_TOKEN）
  python sync.py --import
  python sync.py --import --limit 50

  # 创建本地管理员用户（需设置 POSTGRES_* 环境变量）
  python sync.py --create-admin --username admin --password mypass
"""

import argparse
import json
import logging
import os
import sqlite3
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

import httpx

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("sync")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SOURCE_API = os.getenv("SOURCE_API", "https://api.modrinth.com/v2")
TARGET_API = os.getenv("TARGET_API", "http://labrinth:8000/v2")
TARGET_ADMIN_KEY = os.getenv("TARGET_ADMIN_KEY", "")
TARGET_AUTH_TOKEN = os.getenv("TARGET_AUTH_TOKEN", "")
SYNC_DIR = Path(os.getenv("SYNC_DIR", "/data/sync"))

# Cache and storage limits
# CACHE_TTL: seconds before re-fetching cached data (default 3 days)
# MAX_STORAGE: max bytes for downloaded files (default 500MB)
CACHE_TTL = int(os.getenv("CACHE_TTL", str(3 * 24 * 3600)))
MAX_STORAGE = int(os.getenv("MAX_STORAGE", str(500 * 1024 * 1024)))

# PostgreSQL connection for admin user creation
PG_HOST = os.getenv("PG_HOST", "postgres")
PG_PORT = os.getenv("PG_PORT", "5432")
PG_USER = os.getenv("PG_USER", "8h8g")
PG_PASSWORD = os.getenv("PG_PASSWORD", "")
PG_DB = os.getenv("PG_DB", "8h8g")

HEADERS_SOURCE = {"User-Agent": "8h8g-syncer/1.0"}
HEADERS_TARGET = {"User-Agent": "8h8g-syncer/1.0"}
if TARGET_ADMIN_KEY:
    HEADERS_TARGET["Modrinth-Admin"] = TARGET_ADMIN_KEY
if TARGET_AUTH_TOKEN:
    HEADERS_TARGET["Authorization"] = f"Bearer {TARGET_AUTH_TOKEN}"

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------


def fetch_json(client: httpx.Client, url: str, headers: dict,
               params: dict | None = None, retries=3) -> dict | list | None:
    for attempt in range(retries):
        try:
            resp = client.get(url, headers=headers, params=params, timeout=30)
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                wait = int(e.response.headers.get("Retry-After", 5))
                log.warning("rate limited, waiting %ds...", wait)
                time.sleep(wait)
                continue
            log.warning("HTTP %d fetching %s: %s",
                        e.response.status_code, url, e)
            return None
        except httpx.RequestError as e:
            log.warning("request failed (attempt %d/%d): %s",
                        attempt + 1, retries, e)
            if attempt < retries - 1:
                time.sleep(2 ** attempt)
            else:
                return None
    return None


def post_json(client: httpx.Client, url: str, data: dict,
              headers: dict) -> tuple[bool, dict | None]:
    try:
        resp = client.post(url, json=data, headers=headers, timeout=60)
        if resp.status_code in (200, 201):
            return True, resp.json()
        log.warning("POST %s -> %d: %s", url, resp.status_code, resp.text[:300])
        return False, None
    except httpx.RequestError as e:
        log.error("POST %s failed: %s", url, e)
        return False, None


# ---------------------------------------------------------------------------
# Modrinth API
# ---------------------------------------------------------------------------


def search_projects(client: httpx.Client, limit=100,
                    project_type="", loaders="", offset=0) -> list[dict]:
    params = {"limit": min(limit, 100), "offset": offset, "index": "downloads"}
    if project_type:
        params["facets"] = json.dumps([["project_type:" + project_type]])
    url = f"{SOURCE_API}/search"
    data = fetch_json(client, url, HEADERS_SOURCE, params=params)
    if not data or "hits" not in data:
        return []
    return data["hits"]


def get_project(client: httpx.Client, project_id: str) -> dict | None:
    return fetch_json(client, f"{SOURCE_API}/project/{project_id}", HEADERS_SOURCE)


def get_project_versions(client: httpx.Client, project_id: str) -> list[dict]:
    data = fetch_json(client, f"{SOURCE_API}/project/{project_id}/version",
                      HEADERS_SOURCE)
    return data if isinstance(data, list) else []


# ---------------------------------------------------------------------------
# Local API
# ---------------------------------------------------------------------------


def target_get(client: httpx.Client, path: str) -> dict | list | None:
    return fetch_json(client, urljoin(TARGET_API, path), HEADERS_TARGET)


def target_post(client: httpx.Client, path: str, data: dict) -> tuple[bool, dict | None]:
    return post_json(client, urljoin(TARGET_API, path), data, HEADERS_TARGET)


# ---------------------------------------------------------------------------
# Syncer (download)
# ---------------------------------------------------------------------------


class Syncer:
    def __init__(self, metadata_only: bool = False, force: bool = False):
        self.client_source = httpx.Client()
        self.client_target = httpx.Client()
        self.metadata_only = metadata_only
        self.force = force
        self.dirs = {
            "projects": SYNC_DIR / "projects",
            "versions": SYNC_DIR / "versions",
            "files": SYNC_DIR / "files",
        }
        for d in self.dirs.values():
            d.mkdir(parents=True, exist_ok=True)
        self.stats = {"projects": 0, "versions": 0, "files": 0,
                      "skipped": 0, "errors": 0}

    # ---- Cache helpers ----

    def _is_fresh(self, path: Path) -> bool:
        """Check if cached file is newer than CACHE_TTL."""
        if not path.exists():
            return False
        age = time.time() - path.stat().st_mtime
        return age < CACHE_TTL

    def _check_storage(self):
        """Remove oldest downloaded files if total exceeds MAX_STORAGE."""
        files_dir = self.dirs["files"]
        files = sorted(files_dir.iterdir(), key=lambda p: p.stat().st_mtime)
        total = sum(f.stat().st_size for f in files_dir.iterdir() if f.is_file())
        removed = 0
        while total > MAX_STORAGE and files:
            oldest = files.pop(0)
            total -= oldest.stat().st_size
            oldest.unlink()
            removed += 1
        if removed:
            log.info("  cleaned up %d old file(s), current size: %.1f MB",
                     removed, total / 1024 / 1024)

    def save_json(self, directory: Path, name: str, data: dict | list):
        path = directory / f"{name}.json"
        path.write_text(json.dumps(data, indent=2, default=str))

    def load_json(self, directory: Path, name: str) -> dict | None:
        path = directory / f"{name}.json"
        if path.exists():
            return json.loads(path.read_text())
        return None

    def sync_search_index(self, project_type="", loaders="", limit=100):
        index_path = SYNC_DIR / "search_index.json"
        if not self.force and self._is_fresh(index_path):
            cached = json.loads(index_path.read_text())[:limit]
            log.info("Using cached search index (%d projects, %.1fh old)",
                     len(cached), (time.time() - index_path.stat().st_mtime) / 3600)
            return cached

        log.info("Fetching search results (type=%s, limit=%d)",
                 project_type or "*", limit)
        offset = 0
        all_hits = []
        while len(all_hits) < limit:
            hits = search_projects(self.client_source, limit=100,
                                   project_type=project_type, offset=offset)
            if not hits:
                break
            all_hits.extend(hits)
            offset += 100
            log.info("  fetched %d/%d projects...", min(offset, limit), limit)
        all_hits = all_hits[:limit]
        self.save_json(SYNC_DIR, "search_index", all_hits)
        log.info("Search index saved: %d projects", len(all_hits))
        return all_hits

    def sync_project(self, project_id: str) -> dict | None:
        # Check project cache
        proj_path = self.dirs["projects"] / f"{project_id}.json"
        if not self.force and self._is_fresh(proj_path):
            log.info("  %s: cache fresh (%d projects cached)", project_id,
                     self.stats["projects"])
            self.stats["skipped"] += 1
            return json.loads(proj_path.read_text())

        project = get_project(self.client_source, project_id)
        if not project:
            log.warning("  project %s not found", project_id)
            self.stats["errors"] += 1
            return None

        slug = project.get("slug", project_id)
        self.save_json(self.dirs["projects"], slug, project)
        self.stats["projects"] += 1
        log.info("  synced project: %s (%s)", slug, project.get("title", ""))

        versions = get_project_versions(self.client_source, project_id)
        if versions:
            self.save_json(self.dirs["versions"], slug, versions)
            self.stats["versions"] += len(versions)
            log.info("  versions: %d", len(versions))

            if not self.metadata_only:
                for ver in versions:
                    for file_info in ver.get("files", []):
                        url = file_info.get("url", "")
                        if not url:
                            continue
                        filename = file_info.get("filename", "unknown")
                        filepath = self.dirs["files"] / f"{ver['id']}_{filename}"
                        if filepath.exists():
                            continue
                        # Check storage before downloading each file
                        self._check_storage()
                        try:
                            resp = self.client_source.get(url, headers=HEADERS_SOURCE, timeout=120)
                            if resp.status_code == 200:
                                filepath.write_bytes(resp.content)
                                self.stats["files"] += 1
                            else:
                                log.warning("  failed to download %s: HTTP %d",
                                            filename, resp.status_code)
                        except Exception as e:
                            log.warning("  download error %s: %s", filename, e)
        return project

    def report(self):
        # Final storage check
        self._check_storage()
        log.info("=" * 50)
        log.info("Sync complete!")
        log.info("  Projects: %d", self.stats["projects"])
        log.info("  Versions: %d", self.stats["versions"])
        log.info("  Files:    %d", self.stats["files"])
        log.info("  Skipped:  %d", self.stats["skipped"])
        log.info("  Errors:   %d", self.stats["errors"])
        log.info("  Data dir: %s", SYNC_DIR)
        log.info("=" * 50)

    def close(self):
        self.client_source.close()
        self.client_target.close()


# ---------------------------------------------------------------------------
# Importer (import cached data to local API)
# ---------------------------------------------------------------------------


def import_to_local(limit: int = 0):
    """Import cached project data to the local API instance."""
    if not TARGET_AUTH_TOKEN and not TARGET_ADMIN_KEY:
        log.error("No auth token or admin key set.")
        log.error("Set TARGET_AUTH_TOKEN or TARGET_ADMIN_KEY env var.")
        log.error("")
        log.error("To get a token:")
        log.error("  1. Create an admin via: python sync.py --create-admin")
        log.error("  2. Or login on your instance and copy the Bearer token")
        sys.exit(1)

    client = httpx.Client()
    log.info("Importing cached data to %s ...", TARGET_API)

    # Read search index
    index_path = SYNC_DIR / "search_index.json"
    if not index_path.exists():
        log.error("No cached search index found. Run sync first: python sync.py --limit 50")
        client.close()
        return

    with open(index_path) as f:
        hits = json.load(f)

    if limit > 0:
        hits = hits[:limit]

    imported = 0
    skipped = 0
    errors = 0

    for i, hit in enumerate(hits, 1):
        slug = hit.get("slug") or hit.get("project_id", "")
        if not slug:
            continue

        log.info("[%d/%d] Checking %s ...", i, len(hits), slug)

        # Check if already exists locally
        existing = target_get(client, f"project/{slug}")
        if existing:
            log.info("  -> already exists, skipping")
            skipped += 1
            continue

        # Read cached project data
        proj_path = SYNC_DIR / "projects" / f"{slug}.json"
        if not proj_path.exists():
            log.warning("  -> cached data not found, skipping")
            errors += 1
            continue

        with open(proj_path) as f:
            project = json.load(f)

        # Build minimal create payload (v2 format)
        create_data = {
            "title": project.get("title", slug),
            "slug": slug,
            "description": (project.get("description", "") or "")[:255],
            "body": project.get("body") or project.get("description", ""),
            "project_type": project.get("project_type", "mod"),
            "license_id": project.get("license", {}).get("id", "MIT"),
            "initial_versions": [],
            "is_draft": False,
        }

        # Try to create the project
        success, result = target_post(client, "project", create_data)
        if success:
            imported += 1
            log.info("  -> project created: %s", slug)
        else:
            log.warning("  -> failed to create project")
            errors += 1

        time.sleep(0.3)

    log.info("=" * 50)
    log.info("Import complete!")
    log.info("  Imported: %d", imported)
    log.info("  Skipped:  %d", skipped)
    log.info("  Errors:   %d", errors)
    log.info("=" * 50)

    if imported > 0:
        log.info("Next steps:")
        log.info("  1. Rebuild search index:")
        log.info("     docker compose exec labrinth /labrinth/labrinth --run-background-task index-search")
        log.info("  2. Or wait for incremental indexer to pick up changes")

    client.close()


# ---------------------------------------------------------------------------
# Admin user creation (via direct psql)
# ---------------------------------------------------------------------------


def create_admin_user(username: str, password: str):
    """Create an admin user directly in the PostgreSQL database."""
    log.info("Creating admin user '%s' ...", username)

    # Build psql command
    psql_cmd = [
        "psql",
        f"postgresql://{PG_USER}:{PG_PASSWORD}@{PG_HOST}:{PG_PORT}/{PG_DB}",
        "-c",
    ]

    # Check if psql is available
    try:
        subprocess.run(["psql", "--version"], capture_output=True)
    except FileNotFoundError:
        log.error("psql not found. Install it or run inside the postgres container:")
        log.error("  docker compose exec postgres psql -U 8h8g -d 8h8g")
        log.error("  Then run the SQL in --print-sql mode")
        return

    # First check if user exists
    check_sql = f"SELECT id FROM users WHERE username = '{username}';"
    result = subprocess.run(
        psql_cmd + [check_sql],
        capture_output=True, text=True, timeout=10
    )
    if result.returncode == 0 and username in result.stdout:
        log.info("User '%s' already exists", username)
        return

    # Create user with known token
    create_sql = f"""
    INSERT INTO users (id, username, name, email, password_hash, role, created)
    VALUES (
        nextval('users_id_seq'),
        '{username}',
        '{username}',
        '{username}@bbsmc.org.cn',
        '',  -- no password, use OAuth
        'admin',
        NOW()
    )
    ON CONFLICT (username) DO NOTHING;
    """
    result = subprocess.run(psql_cmd + [create_sql], capture_output=True, text=True, timeout=10)
    if result.returncode == 0:
        log.info("Admin user '%s' created", username)
        log.info("You can now login via OAuth or use the admin key")

        # Get the user ID
        id_result = subprocess.run(
            psql_cmd + [f"SELECT id FROM users WHERE username = '{username}';"],
            capture_output=True, text=True, timeout=10
        )
        log.info("User ID query output: %s", id_result.stdout)
    else:
        log.error("Failed to create user: %s", result.stderr)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="8h8g sync tool")
    parser.add_argument("--limit", type=int, default=25,
                        help="Number of projects to sync (default: 25)")
    parser.add_argument("--project-type", default="mod",
                        choices=["mod", "modpack", "shader", "resourcepack",
                                 "datapack", "plugin"],
                        help="Project type filter")
    parser.add_argument("--loaders", default="",
                        help="Loader filter (comma-separated)")
    parser.add_argument("--metadata-only", action="store_true",
                        help="Only sync metadata, skip file downloads")
    parser.add_argument("--ids", nargs="+",
                        help="Specific project IDs/slugs to sync")
    parser.add_argument("--resume", action="store_true",
                        help="Resume from cached search index")
    parser.add_argument("--force", action="store_true",
                        help="Force re-fetch even if cache is fresh")
    parser.add_argument("--import-data", action="store_true",
                        help="Import cached data to local API")
    parser.add_argument("--create-admin", action="store_true",
                        help="Create admin user in local database")
    parser.add_argument("--username", default="admin",
                        help="Admin username (for --create-admin)")
    parser.add_argument("--password", default="admin123",
                        help="Admin password (for --create-admin)")
    args = parser.parse_args()

    if args.create_admin:
        create_admin_user(args.username, args.password)
        return

    if args.import_data:
        import_to_local(limit=args.limit)
        return

    # Default: sync from source
    syncer = Syncer(metadata_only=args.metadata_only, force=args.force)

    if args.ids:
        project_ids = args.ids
    elif args.resume:
        cached = syncer.load_json(SYNC_DIR, "search_index")
        if cached:
            project_ids = [p.get("project_id", p.get("slug", "")) for p in cached
                           if p.get("project_id") or p.get("slug")]
            log.info("Resumed %d projects from cache", len(project_ids))
        else:
            log.warning("No cache found, fetching fresh...")
            hits = syncer.sync_search_index(project_type=args.project_type,
                                            limit=args.limit)
            project_ids = [p.get("project_id", "") for p in hits]
    else:
        hits = syncer.sync_search_index(project_type=args.project_type,
                                        limit=args.limit)
        project_ids = [p.get("project_id", "") for p in hits]

    for i, pid in enumerate(project_ids, 1):
        if not pid:
            continue
        log.info("[%d/%d] Syncing %s...", i, len(project_ids), pid)
        syncer.sync_project(pid)
        if i < len(project_ids):
            time.sleep(0.5)

    syncer.report()
    syncer.close()


if __name__ == "__main__":
    main()
