#!/usr/bin/env python3
"""
Modrinth → 8h8g 数据同步工具
从 api.modrinth.com 获取项目/版本元数据，同步到本地自建实例。

用法:
  # 同步前 100 个热门项目
  python sync.py --limit 100

  # 按项目类型和加载器筛选
  python sync.py --project-type mod --loaders fabric --limit 50

  # 仅同步元数据（不下载文件）
  python sync.py --limit 200 --metadata-only

  # 使用 Docker 运行（见下）
"""

import argparse
import json
import logging
import os
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
# Config (can override via env vars)
# ---------------------------------------------------------------------------

SOURCE_API = os.getenv("SOURCE_API", "https://api.modrinth.com/v2")
TARGET_API = os.getenv("TARGET_API", "http://labrinth:8000/v2")
TARGET_ADMIN_KEY = os.getenv("TARGET_ADMIN_KEY", "")
TARGET_AUTH_TOKEN = os.getenv("TARGET_AUTH_TOKEN", "")
SYNC_DIR = Path(os.getenv("SYNC_DIR", "/data/sync"))

HEADERS_SOURCE = {"User-Agent": "8h8g-syncer/1.0"}
HEADERS_TARGET = {"User-Agent": "8h8g-syncer/1.0"}
if TARGET_ADMIN_KEY:
    HEADERS_TARGET["Modrinth-Admin"] = TARGET_ADMIN_KEY
if TARGET_AUTH_TOKEN:
    HEADERS_TARGET["Authorization"] = f"Bearer {TARGET_AUTH_TOKEN}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def fetch_json(client: httpx.Client, url: str, headers: dict, retries=3) -> dict | list | None:
    """带重试的 JSON GET 请求。"""
    for attempt in range(retries):
        try:
            resp = client.get(url, headers=headers, timeout=30)
            resp.raise_for_status()
            return resp.json()
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 429:
                wait = int(e.response.headers.get("Retry-After", 5))
                log.warning("rate limited, waiting %ds...", wait)
                time.sleep(wait)
                continue
            log.error("HTTP %d fetching %s: %s", e.response.status_code, url, e)
            return None
        except httpx.RequestError as e:
            log.warning("request failed (attempt %d/%d): %s", attempt + 1, retries, e)
            if attempt < retries - 1:
                time.sleep(2 ** attempt)
            else:
                return None
    return None


def post_json(client: httpx.Client, url: str, data: dict, headers: dict) -> bool:
    """POST JSON 到目标 API。"""
    try:
        resp = client.post(url, json=data, headers=headers, timeout=60)
        if resp.status_code in (200, 201):
            return True
        log.warning("POST %s -> %d: %s", url, resp.status_code, resp.text[:200])
        return False
    except httpx.RequestError as e:
        log.error("POST %s failed: %s", url, e)
        return False


# ---------------------------------------------------------------------------
# Modrinth API wrappers
# ---------------------------------------------------------------------------


def search_projects(client: httpx.Client, limit: int = 100,
                    project_type: str = "", loaders: str = "",
                    offset: int = 0) -> list[dict]:
    """从 api.modrinth.com 搜索项目。"""
    params = {"limit": min(limit, 100), "offset": offset, "index": "downloads"}
    if project_type:
        params["facets"] = f'[["project_type:{project_type}"]]'
    if loaders:
        facets = f'[["project_type:{project_type}"]]' if project_type else "[]"
        # TODO: proper facet combination
    url = f"{SOURCE_API}/search"
    data = fetch_json(client, url, HEADERS_SOURCE, params=params)
    if not data or "hits" not in data:
        return []
    return data["hits"]


def get_project(client: httpx.Client, project_id: str) -> dict | None:
    """获取单个项目的完整信息。"""
    return fetch_json(client, f"{SOURCE_API}/project/{project_id}", HEADERS_SOURCE)


def get_project_versions(client: httpx.Client, project_id: str) -> list[dict]:
    """获取项目的所有版本。"""
    data = fetch_json(client, f"{SOURCE_API}/project/{project_id}/version", HEADERS_SOURCE)
    return data if isinstance(data, list) else []


def get_version(client: httpx.Client, version_id: str) -> dict | None:
    """获取单个版本的详细信息。"""
    return fetch_json(client, f"{SOURCE_API}/version/{version_id}", HEADERS_SOURCE)


# ---------------------------------------------------------------------------
# Local API wrappers
# ---------------------------------------------------------------------------


def target_get(client: httpx.Client, path: str) -> dict | list | None:
    """GET 本地 API。"""
    return fetch_json(client, urljoin(TARGET_API, path), HEADERS_TARGET)


def target_post(client: httpx.Client, path: str, data: dict) -> bool:
    """POST 到本地 API。"""
    return post_json(client, urljoin(TARGET_API, path), data, HEADERS_TARGET)


# ---------------------------------------------------------------------------
# Syncer
# ---------------------------------------------------------------------------


class Syncer:
    def __init__(self, metadata_only: bool = False):
        self.client_source = httpx.Client()
        self.client_target = httpx.Client()
        self.metadata_only = metadata_only
        self.dirs = {
            "projects": SYNC_DIR / "projects",
            "versions": SYNC_DIR / "versions",
            "files": SYNC_DIR / "files",
        }
        for d in self.dirs.values():
            d.mkdir(parents=True, exist_ok=True)
        self.stats = {"projects": 0, "versions": 0, "files": 0, "skipped": 0, "errors": 0}

    def save_json(self, directory: Path, name: str, data: dict | list):
        """保存 JSON 到本地缓存。"""
        path = directory / f"{name}.json"
        path.write_text(json.dumps(data, indent=2, default=str))

    def load_json(self, directory: Path, name: str) -> dict | None:
        """从本地缓存加载 JSON。"""
        path = directory / f"{name}.json"
        if path.exists():
            return json.loads(path.read_text())
        return None

    def sync_search_index(self, project_type: str = "", loaders: str = "",
                          limit: int = 100):
        """同步热门项目列表。"""
        log.info("Fetching search results (type=%s, loaders=%s, limit=%d)",
                 project_type or "*", loaders or "*", limit)
        offset = 0
        all_hits = []
        while len(all_hits) < limit:
            hits = search_projects(self.client_source, limit=100,
                                   project_type=project_type, loaders=loaders,
                                   offset=offset)
            if not hits:
                break
            all_hits.extend(hits)
            offset += 100
            log.info("  fetched %d/%d projects...", min(offset, limit), limit)
        all_hits = all_hits[:limit]

        # Save search index
        self.save_json(SYNC_DIR, "search_index", all_hits)
        log.info("Search index saved: %d projects", len(all_hits))
        return all_hits

    def sync_project(self, project_id: str) -> dict | None:
        """同步单个项目的完整数据。"""
        # Fetch
        project = get_project(self.client_source, project_id)
        if not project:
            log.warning("  project %s not found on source", project_id)
            self.stats["errors"] += 1
            return None

        slug = project.get("slug", project_id)
        self.save_json(self.dirs["projects"], slug, project)
        self.stats["projects"] += 1
        log.info("  synced project: %s (%s)", slug, project.get("title", ""))

        # Versions
        versions = get_project_versions(self.client_source, project_id)
        if versions:
            self.save_json(self.dirs["versions"], slug, versions)
            self.stats["versions"] += len(versions)
            log.info("  versions: %d", len(versions))

            # Download version files if not metadata-only
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
        """输出同步统计。"""
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
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="Modrinth → 8h8g sync tool")
    parser.add_argument("--limit", type=int, default=50,
                        help="Number of projects to sync (default: 50)")
    parser.add_argument("--project-type", default="mod",
                        choices=["mod", "modpack", "shader", "resourcepack",
                                 "datapack", "plugin"],
                        help="Project type filter")
    parser.add_argument("--loaders", default="",
                        help="Loader filter (comma-separated, e.g. fabric,forge)")
    parser.add_argument("--metadata-only", action="store_true",
                        help="Only sync metadata, skip file downloads")
    parser.add_argument("--ids", nargs="+",
                        help="Specific project IDs/slugs to sync")
    parser.add_argument("--resume", action="store_true",
                        help="Resume from cached search index (skip re-fetch)")
    parser.add_argument("--skip-cache", action="store_true",
                        help="Force re-fetch all data")
    args = parser.parse_args()

    syncer = Syncer(metadata_only=args.metadata_only)

    # Determine which projects to sync
    if args.ids:
        project_ids = args.ids
    elif args.resume:
        cached = syncer.load_json(SYNC_DIR, "search_index")
        if cached:
            project_ids = [p.get("project_id", p.get("slug", "")) for p in cached
                           if p.get("project_id") or p.get("slug")]
            log.info("Resumed %d projects from cache", len(project_ids))
        else:
            log.warning("No cached search index found, fetching fresh...")
            hits = syncer.sync_search_index(project_type=args.project_type,
                                            loaders=args.loaders, limit=args.limit)
            project_ids = [p.get("project_id", "") for p in hits]
    else:
        hits = syncer.sync_search_index(project_type=args.project_type,
                                        loaders=args.loaders, limit=args.limit)
        project_ids = [p.get("project_id", "") for p in hits]

    # Sync each project
    for i, pid in enumerate(project_ids, 1):
        if not pid:
            continue
        log.info("[%d/%d] Syncing %s...", i, len(project_ids), pid)
        syncer.sync_project(pid)
        # Rate limiting: be nice to the source API
        if i < len(project_ids):
            time.sleep(0.5)

    syncer.report()
    syncer.close()


if __name__ == "__main__":
    main()
