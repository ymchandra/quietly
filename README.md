# Quietly

**Quietread** — a calm, eye-friendly mobile reading app for free public-domain books.

Books are sourced from the [Project Gutenberg](https://gutenberg.org/) catalog via the [Gutendex API](https://gutendex.com/). Offline reading is powered by `expo-file-system`; user state (wishlist, read-later, library, progress, and reader settings) is stored locally via `AsyncStorage`.

## Repository layout

```
quietly/
├── artifacts/
│   ├── api-server/        # Express 5 REST API
│   ├── mobile/            # Expo (React Native) mobile app
│   └── mockup-sandbox/    # Vite + React UI mockup playground
├── lib/
│   ├── api-client-react/  # Generated React Query hooks (do not edit by hand)
│   ├── api-spec/          # OpenAPI spec + Orval codegen config
│   ├── api-zod/           # Generated Zod request/response schemas
│   └── db/                # PostgreSQL schema (Drizzle ORM)
├── scripts/               # Workspace utility scripts
├── package.json           # Root workspace scripts
└── pnpm-workspace.yaml    # pnpm workspace + catalog config
```

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Node.js | 24 |
| pnpm | 9 |
| PostgreSQL | 15 (for the API server) |

> **pnpm only** — the root `package.json` blocks `npm` and `yarn` via the `preinstall` script.

Install pnpm if you don't have it:

```bash
npm install -g pnpm
```

## Setup

### 1. Install dependencies

```bash
pnpm install
```

### 2. Configure environment variables

**API server** (`artifacts/api-server`):

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string, e.g. `postgresql://user:pass@localhost:5432/quietly` |
| `PORT` | Port the HTTP server listens on, e.g. `3000` |

You can place these in a `.env` file at the repo root or export them in your shell before running the server.

### 3. Push the database schema

Run this once (and again whenever you change `lib/db/src/schema`):

```bash
pnpm --filter @workspace/db run push
```

Use `push-force` to apply schema changes that Drizzle considers destructive:

```bash
pnpm --filter @workspace/db run push-force
```

## Running the apps

### API server

```bash
pnpm --filter @workspace/api-server run dev
```

This typechecks, builds (esbuild → `dist/index.mjs`), and starts the server. Logs are emitted via [Pino](https://getpino.io/) and pretty-printed in development.

### Mobile app (Expo)

```bash
pnpm --filter @workspace/mobile run dev
```

Starts the Expo dev server. Scan the QR code with [Expo Go](https://expo.dev/go) on your device, or press `w` to open the web preview.

### Mockup sandbox

```bash
pnpm --filter @workspace/mockup-sandbox run dev
```

Opens a Vite dev server with the UI mockup playground, useful for prototyping screens without the mobile runtime.

## Building

Build every package in the workspace (runs a full typecheck first):

```bash
pnpm run build
```

Build individual packages:

```bash
# API server only
pnpm --filter @workspace/api-server run build

# Mobile (creates an Expo web bundle)
pnpm --filter @workspace/mobile run build

# Mockup sandbox
pnpm --filter @workspace/mockup-sandbox run build
```

## Typechecking

```bash
# Typecheck everything (lib packages + all artifacts)
pnpm run typecheck

# Typecheck lib packages only (TypeScript project references)
pnpm run typecheck:libs

# Typecheck a single package
pnpm --filter @workspace/api-server run typecheck
pnpm --filter @workspace/mobile run typecheck
pnpm --filter @workspace/mockup-sandbox run typecheck
```

## Code generation

The `lib/api-client-react` and `lib/api-zod` packages are generated from the OpenAPI spec in `lib/api-spec/openapi.yaml` using [Orval](https://orval.dev/). After editing the spec, regenerate:

```bash
pnpm --filter @workspace/api-spec run codegen
```

This runs Orval and then immediately typechecks the lib packages to catch any breakage.

> **Do not edit** `lib/api-client-react/src` or `lib/api-zod/src` by hand — your changes will be overwritten the next time `codegen` runs.

## Debugging

### API server

The server uses [Pino](https://getpino.io/) for structured JSON logging. In development the output is piped through `pino-pretty` for readability. To see raw JSON (e.g. to pipe to a log aggregator), run the built bundle directly:

```bash
node --enable-source-maps artifacts/api-server/dist/index.mjs
```

Source maps are enabled (`--enable-source-maps`), so stack traces point back to the original TypeScript files.

To attach a Node.js debugger (e.g. VS Code or Chrome DevTools):

```bash
node --inspect --enable-source-maps artifacts/api-server/dist/index.mjs
```

Then open `chrome://inspect` or connect your IDE's debugger to `localhost:9229`.

### Mobile app

Use the [Expo dev tools](https://docs.expo.dev/debugging/tools/) built into the Expo CLI. Press `j` in the terminal running `pnpm --filter @workspace/mobile run dev` to open the JS debugger in your browser.

For React Native-specific issues, the [Flipper](https://fbflipper.com/) desktop app can be connected to the Expo Go client on a physical device.

## Development workflow

### Adding a new API endpoint

1. Describe the endpoint in `lib/api-spec/openapi.yaml`.
2. Run `pnpm --filter @workspace/api-spec run codegen` to regenerate types and hooks.
3. Implement the route handler in `artifacts/api-server/src/routes/`.
4. Use the generated Zod schemas from `@workspace/api-zod` for request validation.
5. Use the generated React Query hooks from `@workspace/api-client-react` in the mobile app.

### Updating the database schema

1. Edit `lib/db/src/schema/index.ts`.
2. Run `pnpm --filter @workspace/db run push` to apply changes to your local database.
3. If Drizzle reports a destructive change, use `push-force` (dev only).

### Adding a new workspace package

1. Create a directory under `artifacts/` (for runnable apps) or `lib/` (for shared libraries).
2. Add a `package.json` with a unique `"name"` scoped to `@workspace/`.
3. Reference shared dependency versions from the catalog in `pnpm-workspace.yaml` using `catalog:` instead of a version string.
4. Run `pnpm install` from the repo root to link the new package.

## Project structure details

### `lib/db`

Drizzle ORM schema and migration helpers. Exports:

- `@workspace/db` — database client and query helpers
- `@workspace/db/schema` — raw Drizzle table definitions (used by `drizzle-zod` to derive Zod schemas)

### `lib/api-spec`

Single source of truth for the REST API contract (`openapi.yaml`). Contains the Orval config (`orval.config.ts`) that drives code generation for both `lib/api-zod` and `lib/api-client-react`.

### `artifacts/api-server`

Express 5 HTTP server. Built with esbuild into a single ESM bundle (`dist/index.mjs`). Key entry points:

- `src/index.ts` — reads `PORT` env var and starts the server
- `src/app.ts` — Express app with CORS, JSON body parsing, and Pino HTTP logging
- `src/routes/` — route handlers

### `artifacts/mobile`

Expo Router app targeting iOS, Android, and web. Key directories:

- `app/(tabs)/` — tab-based navigation screens (Home, Library, Lists, Settings)
- `app/book/` — book detail screen
- `app/reader/` — in-app reader screen
- `contexts/` — React context providers for app-wide state
- `hooks/` — custom React hooks
