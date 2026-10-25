# Renders the README screenshots from the HTML mockups in docs/mockups: each phone screen in light
# and dark (name.png, name-dark.png) at 390x844 @1.5x, plus the always-dark Watch screen.
# Needs Playwright's WebKit, which uses the system fonts (SF Pro, SF Mono) like the app:
#   pip3 install playwright && python3 -m playwright install webkit
# Usage: python3 tools/render_mockups.py
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent.parent
SRC, OUT = ROOT / "docs/mockups", ROOT / "docs/screenshots"
PHONE = ["today", "coach", "plan", "active-set", "crew", "form-guide", "summary", "history", "week"]

def shot(browser, name, out, size, scale, dark=False):
    page = browser.new_page(viewport=dict(zip(("width", "height"), size)), device_scale_factor=scale)
    page.goto((SRC / f"{name}.html").as_uri())
    if dark:
        page.evaluate("document.documentElement.classList.add('dark')")
    page.wait_for_timeout(200)
    page.screenshot(path=OUT / out)
    page.close()

with sync_playwright() as p:
    browser = p.webkit.launch()
    for name in PHONE:
        shot(browser, name, f"{name}.png", (390, 844), 1.5)
        shot(browser, name, f"{name}-dark.png", (390, 844), 1.5, dark=True)
    shot(browser, "watch", "watch.png", (208, 248), 2)
    browser.close()
