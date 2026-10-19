"""Browser smoke test: drives the real web console like a user (Flutter accessibility tree).

    pip install -r backend/requirements-dev.txt && python -m playwright install chromium
    python scripts/browser_smoke.py --base http://localhost:8000 --out smoke-shots

Flow: every console route loads without page/console/HTTP errors -> Run sample inspection ->
live view -> workspace -> review an UNCERTAIN finding -> export PDF -> reinspect with fixture v2 ->
compare -> New Inspection wizard with real file uploads -> run. Exits non-zero on any failure.
Creates inspections in the target database (use a scratch instance).
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parents[1]
ROUTES = ["/console", "/welcome", "/console/new", "/console/live", "/console/workspace", "/console/review",
          "/console/history", "/console/analytics", "/console/reports", "/console/evidence", "/console/models",
          "/console/health", "/console/settings", "/console/does-not-exist"]


class Smoke:
    def __init__(self, base: str, out: Path):
        self.base, self.out, self.problems, self.n = base.rstrip("/"), out, [], 0

    def api(self, path: str):
        with urllib.request.urlopen(f"{self.base}/api/v1{path}") as r:
            return json.loads(r.read())

    def watch(self, page):
        page.on("console", lambda m: self.problems.append(f"console.error: {m.text[:200]}") if m.type == "error" else None)
        page.on("pageerror", lambda e: self.problems.append(f"pageerror: {str(e)[:200]}"))
        page.on("response", lambda r: self.problems.append(f"HTTP {r.status} {r.request.method} {r.url}") if r.status >= 400 else None)

    async def shot(self, page, name: str):
        self.n += 1
        await page.screenshot(path=str(self.out / f"{self.n:02d}_{name}.png"))

    async def open(self, page, path: str, wait_ms: int = 5000):
        await page.goto(self.base + path)
        await page.wait_for_timeout(wait_ms)
        await page.evaluate("() => document.querySelector('flt-semantics-placeholder')?.click()")  # enable semantics
        await page.wait_for_timeout(700)

    async def press(self, page, pattern: str, timeout_s: float = 20):
        loc = page.get_by_role("button", name=re.compile(pattern))
        t0 = time.time()
        while time.time() - t0 < timeout_s:
            for i in range(await loc.count()):
                el = loc.nth(i)
                if await el.is_visible() and await el.get_attribute("aria-disabled") != "true":
                    await el.click(force=True)  # overlapping semantics nodes can intercept a normal click
                    print(f"   clicked /{pattern}/")
                    return el
            await page.wait_for_timeout(500)
        raise AssertionError(f"no enabled button matching /{pattern}/")

    async def wait_url(self, page, fragment: str, timeout_s: float) -> float:
        t0 = time.time()
        while fragment not in page.url:
            if time.time() - t0 > timeout_s:
                raise AssertionError(f"URL never contained {fragment!r} (at {page.url})")
            await page.wait_for_timeout(1000)
        return time.time() - t0

    async def routes(self, page):
        print("1. every route renders")
        await self.open(page, "/", 7000)
        assert page.url.rstrip("/").endswith("/console"), f"/ should open the console, got {page.url}"
        for path in ROUTES:
            await self.open(page, path, 3500)
            await self.shot(page, "route" + path.replace("/", "_"))

    async def journey(self, page) -> str:
        print("2. sample inspection -> live -> workspace")
        await self.open(page, "/console")
        await self.press(page, r"^Run sample inspection$")
        await self.wait_url(page, "/console/live?job=", 60)
        dt = await self.wait_url(page, "/console/workspace", 900)
        print(f"   workspace opened after {dt:.0f}s")
        insp = page.url.split("i=")[1].split("&")[0]
        ver = self.api(f"/inspections/{insp}")["latest_version"]
        assert ver["status"] == "completed", ver["status"]
        print("   summary", {k: ver["summary"][k] for k in ("total", "pass", "fail", "uncertain")})

        print("3. review an UNCERTAIN finding")
        target = next(f for f in self.api(f"/versions/{ver['id']}/findings?verdict=UNCERTAIN")["items"] if f["verdict"] == "UNCERTAIN")
        await self.open(page, f"/console/workspace?i={insp}&v={ver['version_no']}&f={target['id']}", 6000)
        btns = page.get_by_role("button", name="Evidence & review")
        boxes = [(i, await btns.nth(i).bounding_box()) for i in range(await btns.count())]
        width = page.viewport_size["width"]
        i, _ = max(((i, b) for i, b in boxes if b and b["x"] < width * 0.72), key=lambda t: t[1]["y"])  # the selected-finding card
        await btns.nth(i).click(force=True)
        await page.wait_for_timeout(2500)
        await self.press(page, r"^Resolve as PASS$")
        await page.wait_for_timeout(800)
        await self.press(page, r"^Save review$")
        await page.wait_for_timeout(2500)
        await self.shot(page, "after_review")
        f = self.api(f"/findings/{target['id']}")
        assert f["effective_verdict"] == "PASS" and f["verdict"] == "UNCERTAIN", (f["verdict"], f["effective_verdict"])

        print("4. export PDF")
        await self.open(page, f"/console/workspace?i={insp}", 6000)
        async with page.expect_download(timeout=180000) as dl:
            await self.press(page, r"^Export PDF$")
        pdf = self.out / (await dl.value).suggested_filename
        await (await dl.value).save_as(pdf)
        assert pdf.read_bytes()[:5] == b"%PDF-", "download is not a PDF"
        print(f"   saved {pdf.name}")

        print("5. reinspect with fixture v2 and compare")
        await self.open(page, f"/console/history?i={insp}", 6000)
        await self.press(page, r"^Reinspect$")
        await page.wait_for_timeout(1000)
        await self.press(page, r"^Use fixture v2$")
        await self.wait_url(page, "/console/live?job=", 120)
        dt = await self.wait_url(page, "/console/workspace", 900)
        print(f"   v2 finished after {dt:.0f}s")
        counts = self.api(f"/inspections/{insp}/compare")["summary"]["counts"]
        print("   comparison", counts)
        assert counts.get("resolved", 0) >= 2 and counts.get("new_discrepancy", 0) == 0, counts
        await self.open(page, f"/console/history?i={insp}", 6000)
        await self.shot(page, "history")
        return insp

    async def wizard(self, page):
        print("6. New Inspection wizard with real uploads")
        demo = ROOT / "data" / "demo"
        await self.open(page, "/console/new", 6000)
        for label, text in (("Inspection title *", "Browser smoke upload"), ("Cabinet identifier *", "CAB-07")):
            await page.get_by_label(label, exact=True).click(force=True)
            await page.wait_for_timeout(200)
            await page.keyboard.type(text)
        await self.press(page, r"^Create case & continue$")
        for zone, file in (("Drop the cabinet photograph", "CAB-07_cabinet_photo_v1_SYNTHETIC.jpg"),
                           ("Drop the GA drawing", "CAB-07_GA_drawing_SYNTHETIC.pdf"),
                           ("Drop the expected component", "CAB-07_expected_list_SYNTHETIC.xlsx")):
            await page.wait_for_timeout(2000)
            async with page.expect_file_chooser(timeout=20000) as fc:
                await self.press(page, zone)
            await (await fc.value).set_files(str(demo / file))
            await page.wait_for_timeout(6000)
            await self.press(page, r"^(Save mapping & continue|Continue)$")
        await page.wait_for_timeout(2000)
        await self.press(page, r"^Save configuration & continue$")
        await page.wait_for_timeout(4000)
        await self.press(page, r"^Continue$", 60)
        await page.wait_for_timeout(2000)
        await self.press(page, r"^Run Inspection$", 60)
        dt = await self.wait_url(page, "/console/workspace", 900)
        insp = page.url.split("i=")[1].split("&")[0]
        ver = self.api(f"/inspections/{insp}")["latest_version"]
        print(f"   uploaded inspection finished after {dt:.0f}s:", {k: ver["summary"][k] for k in ("total", "pass", "fail", "uncertain")})
        assert ver["status"] == "completed"


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://localhost:8000")
    ap.add_argument("--out", default="smoke-shots")
    ap.add_argument("--width", type=int, default=1600)
    ap.add_argument("--height", type=int, default=1000)
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    s = Smoke(a.base, out)
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            executable_path=os.environ.get("EAGLEEYE_CHROMIUM") or None,
            args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
        )
        page = await (await browser.new_context(viewport={"width": a.width, "height": a.height}, accept_downloads=True)).new_page()
        s.watch(page)
        try:
            await s.routes(page)
            await s.journey(page)
            await s.wizard(page)
        except Exception as e:  # noqa: BLE001
            await s.shot(page, "failure")
            print(f"FAILED: {e}")
            return 1
        finally:
            await browser.close()
    if s.problems:
        print("Browser problems:\n  " + "\n  ".join(s.problems))
        return 1
    print(f"OK - screenshots in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
