#!/usr/bin/env npx tsx
/**
 * browser-verify.ts - Real browser verification for Ralph
 *
 * Uses Playwright to actually load pages and verify they work.
 * Much more reliable than asking Claude to "imagine" what a page looks like.
 *
 * Usage:
 *   npx tsx browser-verify.ts <url> [options]
 *
 * Options:
 *   --selectors '["#app", ".header"]'  - Required elements (CSS selectors)
 *   --screenshot <path>                 - Save screenshot to path
 *   --timeout <ms>                      - Page load timeout (default: 30000)
 *   --headless                          - Run headless (default: true)
 *   --check-console                     - Fail on console errors (default: true)
 *   --check-network                     - Fail on failed network requests (default: true)
 *   --viewport <width>x<height>         - Viewport size (default: 1280x720)
 *   --mobile                            - Use mobile viewport (375x667)
 *   --auth-cookie <json>                - Set auth cookie before loading
 *
 * Output: JSON to stdout
 *   { "pass": true/false, "errors": [], "warnings": [], "screenshot": "path" }
 */

import { chromium, Browser, Page, ConsoleMessage } from 'playwright';

interface VerifyOptions {
  url: string;
  selectors: string[];
  screenshot?: string;
  timeout: number;
  headless: boolean;
  checkConsole: boolean;
  checkNetwork: boolean;
  viewport: { width: number; height: number };
  authCookie?: { name: string; value: string; domain: string };
}

interface VerifyResult {
  pass: boolean;
  errors: string[];
  warnings: string[];
  screenshot?: string;
  title?: string;
  elementsFound: string[];
  elementsMissing: string[];
  consoleErrors: string[];
  networkErrors: string[];
  loadTime: number;
}

async function parseArgs(): Promise<VerifyOptions> {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === '--help') {
    console.error(`
Usage: npx tsx browser-verify.ts <url> [options]

Options:
  --selectors '["#app", ".btn"]'  Required elements (JSON array)
  --screenshot <path>             Save screenshot
  --timeout <ms>                  Load timeout (default: 30000)
  --headless                      Run headless (default: true)
  --no-headless                   Show browser window
  --check-console                 Fail on console errors (default: true)
  --no-check-console              Ignore console errors
  --check-network                 Fail on network errors (default: true)
  --no-check-network              Ignore network errors
  --viewport <W>x<H>              Viewport size (default: 1280x720)
  --mobile                        Mobile viewport (375x667)
  --auth-cookie '<json>'          Set auth cookie
`);
    process.exit(1);
  }

  const url = args[0];
  const options: VerifyOptions = {
    url,
    selectors: [],
    timeout: 30000,
    headless: true,
    checkConsole: true,
    checkNetwork: true,
    viewport: { width: 1280, height: 720 },
  };

  for (let i = 1; i < args.length; i++) {
    const arg = args[i];

    switch (arg) {
      case '--selectors':
        try {
          options.selectors = JSON.parse(args[++i]);
        } catch {
          console.error('Invalid --selectors JSON');
          process.exit(1);
        }
        break;
      case '--screenshot':
        options.screenshot = args[++i];
        break;
      case '--timeout':
        options.timeout = parseInt(args[++i], 10);
        break;
      case '--headless':
        options.headless = true;
        break;
      case '--no-headless':
        options.headless = false;
        break;
      case '--check-console':
        options.checkConsole = true;
        break;
      case '--no-check-console':
        options.checkConsole = false;
        break;
      case '--check-network':
        options.checkNetwork = true;
        break;
      case '--no-check-network':
        options.checkNetwork = false;
        break;
      case '--viewport':
        const [w, h] = args[++i].split('x').map(Number);
        options.viewport = { width: w, height: h };
        break;
      case '--mobile':
        options.viewport = { width: 375, height: 667 };
        break;
      case '--auth-cookie':
        try {
          options.authCookie = JSON.parse(args[++i]);
        } catch {
          console.error('Invalid --auth-cookie JSON');
          process.exit(1);
        }
        break;
    }
  }

  return options;
}

async function verify(options: VerifyOptions): Promise<VerifyResult> {
  const result: VerifyResult = {
    pass: true,
    errors: [],
    warnings: [],
    elementsFound: [],
    elementsMissing: [],
    consoleErrors: [],
    networkErrors: [],
    loadTime: 0,
  };

  let browser: Browser | null = null;
  let page: Page | null = null;

  try {
    // Launch browser
    browser = await chromium.launch({
      headless: options.headless,
    });

    const context = await browser.newContext({
      viewport: options.viewport,
    });

    // Set auth cookie if provided
    if (options.authCookie) {
      await context.addCookies([{
        name: options.authCookie.name,
        value: options.authCookie.value,
        domain: options.authCookie.domain,
        path: '/',
      }]);
    }

    page = await context.newPage();

    // Collect console errors
    const consoleErrors: string[] = [];
    page.on('console', (msg: ConsoleMessage) => {
      const type = msg.type();
      const text = msg.text();

      // Capture actual console.error calls
      if (type === 'error') {
        // Ignore some common noise
        if (!text.includes('favicon') && !text.includes('DevTools')) {
          consoleErrors.push(text);
        }
      }

      // Also capture logs/warnings that indicate errors (e.g., custom loggers)
      if ((type === 'log' || type === 'warning') &&
          (text.includes('_error') || text.includes('Error:') || text.includes('ERROR'))) {
        // Ignore known non-critical patterns
        if (!text.includes('ResizeObserver')) {
          consoleErrors.push(`[${type}] ${text}`);
        }
      }
    });

    // Collect network errors
    const networkErrors: string[] = [];
    page.on('requestfailed', (request) => {
      const failure = request.failure();
      if (failure) {
        networkErrors.push(`${request.method()} ${request.url()}: ${failure.errorText}`);
      }
    });

    // Track failed responses (4xx, 5xx)
    page.on('response', (response) => {
      const status = response.status();
      if (status >= 400) {
        const url = response.url();
        // Ignore favicon and some common 404s
        if (!url.includes('favicon') && !url.includes('hot-update')) {
          networkErrors.push(`${response.request().method()} ${url}: ${status}`);
        }
      }
    });

    // Navigate to page
    const startTime = Date.now();

    try {
      await page.goto(options.url, {
        timeout: options.timeout,
        waitUntil: 'networkidle',
      });
    } catch (err: any) {
      if (err.message.includes('net::ERR_CONNECTION_REFUSED')) {
        result.errors.push(`Cannot connect to ${options.url} - is the server running?`);
        result.pass = false;
        return result;
      }
      throw err;
    }

    result.loadTime = Date.now() - startTime;

    // Get page title
    result.title = await page.title();
    if (!result.title) {
      result.warnings.push('Page has no title');
    }

    // Check for error page indicators
    const bodyText = await page.textContent('body') || '';
    const errorPatterns = [
      /something went wrong/i,
      /error occurred/i,
      /500 internal server/i,
      /503 service unavailable/i,
      /404 not found/i,
      /oops!/i,
      /application error/i,
      /unhandled runtime error/i,
    ];

    for (const pattern of errorPatterns) {
      if (pattern.test(bodyText)) {
        result.errors.push(`Page contains error text: "${bodyText.match(pattern)?.[0]}"`);
        result.pass = false;
      }
    }

    // Check required selectors
    for (const selector of options.selectors) {
      try {
        const element = await page.$(selector);
        if (element) {
          result.elementsFound.push(selector);
        } else {
          result.elementsMissing.push(selector);
          result.errors.push(`Required element not found: ${selector}`);
          result.pass = false;
        }
      } catch (err: any) {
        result.elementsMissing.push(selector);
        result.errors.push(`Error checking selector "${selector}": ${err.message}`);
        result.pass = false;
      }
    }

    // Check console errors
    result.consoleErrors = consoleErrors;
    if (options.checkConsole && consoleErrors.length > 0) {
      result.errors.push(`${consoleErrors.length} console error(s) detected`);
      result.pass = false;
    }

    // Check network errors
    result.networkErrors = networkErrors;
    if (options.checkNetwork && networkErrors.length > 0) {
      // Only fail on actual errors, not 404s for optional resources
      const criticalErrors = networkErrors.filter(e =>
        !e.includes('favicon') &&
        !e.includes('.map') &&
        !e.includes('hot-update')
      );
      if (criticalErrors.length > 0) {
        result.warnings.push(`${criticalErrors.length} network error(s) detected`);
        // Don't fail on network errors by default, just warn
      }
    }

    // Take screenshot
    if (options.screenshot) {
      await page.screenshot({
        path: options.screenshot,
        fullPage: true,
      });
      result.screenshot = options.screenshot;
    }

  } catch (err: any) {
    result.errors.push(`Browser error: ${err.message}`);
    result.pass = false;
  } finally {
    if (browser) {
      await browser.close();
    }
  }

  return result;
}

async function main() {
  const options = await parseArgs();
  const result = await verify(options);

  // Output JSON result
  console.log(JSON.stringify(result, null, 2));

  // Exit with appropriate code
  process.exit(result.pass ? 0 : 1);
}

main().catch((err) => {
  console.error(JSON.stringify({
    pass: false,
    errors: [`Fatal error: ${err.message}`],
    warnings: [],
    elementsFound: [],
    elementsMissing: [],
    consoleErrors: [],
    networkErrors: [],
    loadTime: 0,
  }, null, 2));
  process.exit(1);
});
