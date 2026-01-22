# Browser Verify Skill

Verify that a web page loads correctly using real browser automation (Playwright).

## Purpose

This skill launches a real Chromium browser to verify pages work correctly. Unlike asking Claude to "imagine" what a page looks like, this actually:

- Loads the page in a real browser
- Detects JavaScript console errors
- Detects failed network requests
- Checks for error messages on the page ("Oops!", "Something went wrong")
- Verifies required elements exist
- Takes screenshots for evidence
- Tests mobile viewport

## When to Use

Use this skill for **frontend story verification**:
- After implementing a UI feature
- To verify a page loads without errors
- To check that required elements render
- To test mobile responsiveness

## Usage

```bash
npx tsx ralph/browser-verify/verify.ts <url> [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--selectors '["#app", ".btn"]'` | Required elements (JSON array) | `[]` |
| `--screenshot <path>` | Save screenshot to path | none |
| `--timeout <ms>` | Page load timeout | 30000 |
| `--headless` | Run without visible browser | true |
| `--no-headless` | Show browser window | false |
| `--check-console` | Fail on console errors | true |
| `--no-check-console` | Ignore console errors | false |
| `--mobile` | Use mobile viewport (375x667) | false |
| `--viewport <W>x<H>` | Custom viewport size | 1280x720 |

### Examples

**Basic page check:**
```bash
npx tsx ralph/browser-verify/verify.ts http://localhost:3000/dashboard
```

**Check specific elements exist:**
```bash
npx tsx ralph/browser-verify/verify.ts http://localhost:3000/login \
  --selectors '["#email", "#password", "button[type=submit]"]'
```

**Take screenshot and check mobile:**
```bash
npx tsx ralph/browser-verify/verify.ts http://localhost:3000/dashboard \
  --screenshot .ralph/screenshots/dashboard.png \
  --mobile
```

**Debug mode (visible browser):**
```bash
npx tsx ralph/browser-verify/verify.ts http://localhost:3000/dashboard \
  --no-headless
```

## Output

Returns JSON to stdout:

```json
{
  "pass": true,
  "errors": [],
  "warnings": ["Page loaded slowly (3500ms)"],
  "screenshot": ".ralph/screenshots/dashboard.png",
  "title": "Dashboard - MyApp",
  "elementsFound": ["#app", ".header", ".sidebar"],
  "elementsMissing": [],
  "consoleErrors": [],
  "networkErrors": [],
  "loadTime": 1234
}
```

### Exit Codes

- `0` - Verification passed
- `1` - Verification failed (check `errors` array)

## What It Catches

| Issue | How It's Detected |
|-------|-------------------|
| Page won't load | Connection refused, timeout |
| JavaScript errors | Console error messages |
| Failed API calls | Network request failures, 4xx/5xx responses |
| Error pages | Text matching "Oops!", "Something went wrong", etc. |
| Missing elements | Selector not found in DOM |
| Slow pages | Load time > 5 seconds (warning) |

## Integration with Ralph

Ralph automatically uses this skill for frontend story verification:

1. Story has `testUrl` defined
2. Ralph calls `verify.ts` with the URL
3. Optionally checks `selectors` from story config
4. Takes screenshot for evidence
5. Fails verification if errors detected

## Requirements

- Node.js 18+
- Playwright (`npx playwright install chromium`)

## Troubleshooting

**"Cannot find module 'playwright'"**
```bash
npm install playwright
npx playwright install chromium
```

**"Browser closed unexpectedly"**
- Try with `--no-headless` to see what's happening
- Check if the URL is accessible

**"Timeout waiting for page"**
- Increase timeout: `--timeout 60000`
- Check if dev server is running
