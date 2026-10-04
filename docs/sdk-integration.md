# Connecting projects to Central Sentry

All the official Sentry SDKs work with our server. The only thing that changes is the **DSN**, which you get from
`https://sentry.company.com` → Project → **Settings → Client Keys (DSN)**.

Shared conventions for every project:
- `environment`: `production` | `staging` | `development`
- `release`: `<project-name>@<version or git sha>`. Needed to tell regressions apart and to map source maps
- Never commit the DSN to the repo for backends. Pass it in through an env var (`SENTRY_DSN`)

---

## Web

### React / Vite
```bash
npm i @sentry/react
```
```js
import * as Sentry from "@sentry/react";

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_RELEASE,
  integrations: [Sentry.browserTracingIntegration(), Sentry.replayIntegration()],
  tracesSampleRate: 0.1,
  tracePropagationTargets: [/^https:\/\/api\.company\.com/],
  replaysSessionSampleRate: 0.0,
  replaysOnErrorSampleRate: 1.0,
  // Requests go through your own domain so ad-blockers can't block them (optional)
  // tunnel: "/monitoring",
});
```

### Next.js
```bash
npx @sentry/wizard@latest -i nextjs --url https://sentry.company.com
```
The wizard creates the `sentry.*.config.ts` files and `withSentryConfig`. Set `sentryUrl: "https://sentry.company.com"` in `next.config` so source maps are uploaded to our server.

### Uploading source maps (any JS build)
```bash
npm i -D @sentry/cli
export SENTRY_URL=https://sentry.company.com
export SENTRY_AUTH_TOKEN=...   # Settings → Auth Tokens (org:ci scope)
export SENTRY_ORG=company SENTRY_PROJECT=web-shop
npx sentry-cli sourcemaps inject ./dist
npx sentry-cli sourcemaps upload --release "web-shop@$GIT_SHA" ./dist
```
With Vite/Webpack you can use `@sentry/vite-plugin` / `@sentry/webpack-plugin` too. Just give them `url: "https://sentry.company.com"`.

---

## Backend

### Node.js / Express / NestJS
```bash
npm i @sentry/node
```
```js
// instrument.js: must be imported before anything else
const Sentry = require("@sentry/node");
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.RELEASE,
  tracesSampleRate: 0.1,
});
```
```js
// app.js
require("./instrument");
const express = require("express");
const Sentry = require("@sentry/node");
const app = express();
// ... routes
Sentry.setupExpressErrorHandler(app);
```

### Python / Django / FastAPI
```bash
pip install "sentry-sdk"
```
```python
import os, sentry_sdk
sentry_sdk.init(
    dsn=os.environ["SENTRY_DSN"],
    environment=os.getenv("ENV", "production"),
    release=os.getenv("RELEASE"),
    traces_sample_rate=0.1,
    send_default_pii=False,
)
```
The Django/FastAPI/Celery integrations are enabled automatically.

### PHP / Laravel
```bash
composer require sentry/sentry-laravel
php artisan sentry:publish --dsn=https://<key>@sentry.company.com/<id>
```
In `.env`: `SENTRY_LARAVEL_DSN=...` and `SENTRY_TRACES_SAMPLE_RATE=0.1`.

### Go
```go
import "github.com/getsentry/sentry-go"

sentry.Init(sentry.ClientOptions{
    Dsn:              os.Getenv("SENTRY_DSN"),
    Environment:      "production",
    TracesSampleRate: 0.1,
})
defer sentry.Flush(2 * time.Second)
```

---

## Mobile

### Android (Kotlin)
`build.gradle` (app):
```groovy
plugins { id "io.sentry.android.gradle" version "5.+" }
sentry {
    url = "https://sentry.company.com"
    org = "company"
    projectName = "android-app"
    authToken = System.getenv("SENTRY_AUTH_TOKEN")
    includeProguardMapping = true   // de-obfuscates stack traces
}
```
`AndroidManifest.xml`:
```xml
<meta-data android:name="io.sentry.dsn" android:value="https://<key>@sentry.company.com/<id>" />
<meta-data android:name="io.sentry.traces.sample-rate" android:value="0.1" />
```

### iOS (Swift)
```swift
import Sentry

SentrySDK.start { options in
    options.dsn = "https://<key>@sentry.company.com/<id>"
    options.environment = "production"
    options.tracesSampleRate = 0.1
}
```
To upload dSYMs, add a Build Phase:
```bash
export SENTRY_URL=https://sentry.company.com SENTRY_ORG=company SENTRY_PROJECT=ios-app
sentry-cli debug-files upload "$DWARF_DSYM_FOLDER_PATH"
```

### Flutter
```yaml
dependencies:
  sentry_flutter: ^9.0.0
```
```dart
await SentryFlutter.init(
  (o) {
    o.dsn = const String.fromEnvironment('SENTRY_DSN');
    o.environment = 'production';
    o.tracesSampleRate = 0.1;
  },
  appRunner: () => runApp(const MyApp()),
);
```
To upload debug symbols, use the `sentry_dart_plugin` package with `url: https://sentry.company.com`.

### React Native / Expo
```bash
npx @sentry/wizard@latest -i reactNative --url https://sentry.company.com
```

---

## Testing the connection

After setup, send a test error:
```js
Sentry.captureException(new Error("sentry wiring test"));
```
It should show up under **Issues** within a few seconds. If it doesn't:
1. Check the DSN host is `sentry.company.com` (not `localhost:9000`).
2. Run `curl -I https://sentry.company.com/api/0/` from the app's server.
3. On the Sentry server, run `cd self-hosted && docker compose logs -f relay nginx`.
