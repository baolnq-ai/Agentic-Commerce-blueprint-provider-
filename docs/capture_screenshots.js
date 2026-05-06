const { chromium } = require('playwright-chromium');
const fs = require('fs');

async function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function run() {
  const candidates = [
    process.env.CHROME_BIN,
    '/usr/bin/chromium-browser',
    '/usr/bin/chromium',
    '/usr/bin/google-chrome',
  ].filter(Boolean);

  const executablePath = candidates.find((path) => fs.existsSync(path));

  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox'],
    executablePath,
  });

  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });

  await page.goto('http://localhost', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('text=Client Agent', { timeout: 20000 });
  await wait(1200);
  await page.screenshot({ path: '/repo/docs/images/hero.png', fullPage: true });

  await page.goto('http://localhost/metrics', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('text=Retail Metrics Dashboard', { timeout: 20000 });
  await wait(1200);
  await page.screenshot({ path: '/repo/docs/images/metrics.png', fullPage: true });

  await page.goto('http://localhost', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('text=Client Agent', { timeout: 20000 });
  const productButton = page.locator('button[aria-label^="Select "]').first();
  await productButton.waitFor({ timeout: 20000 });
  await productButton.click();
  await page.waitForSelector('button[aria-label="Close payment modal"]', { timeout: 20000 });
  await wait(1200);
  await page.screenshot({ path: '/repo/docs/images/checkout-flow.png', fullPage: true });

  const continueBtn = page.locator('button:has-text("Continue")').first();
  await continueBtn.waitFor({ timeout: 20000 });
  await continueBtn.click();
  await page.waitForSelector('text=Add payment method', { timeout: 20000 });
  await wait(1200);
  await page.screenshot({ path: '/repo/docs/images/checkout-payment.png', fullPage: true });

  await page.goto('http://localhost', { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('text=Client Agent', { timeout: 20000 });
  const anotherProductButton = page.locator('button[aria-label^="Select "]').first();
  await anotherProductButton.waitFor({ timeout: 20000 });
  await anotherProductButton.click();
  await page.waitForSelector('text=Autonomous Decisions', { timeout: 20000 });
  await wait(1200);
  await page.screenshot({
    path: '/repo/docs/images/agents.png',
    clip: { x: 1260, y: 70, width: 640, height: 980 },
  });

  await browser.close();
}

run()
  .then(() => {
    console.log('screenshots done');
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
