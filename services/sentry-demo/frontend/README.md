# Sentry POC Frontend

Angular 20 frontend application demonstrating Sentry integration with debug-ids support.

## Quick Start

### Using Docker (Recommended)

From the project root:

```bash
# Development mode (no source map upload)
./start-dev.sh

# Production mode (with source map upload)
./start-prod.sh
```

## Setup

### 1. Install Dependencies
```bash
npm install
```

### 2. Configure Sentry

#### Create Sentry Auth Token
1. Go to https://sentry.io/settings/account/api/auth-tokens/
2. Click "Create New Token"
3. Give it a name (e.g., "Source Maps Upload")
4. Select scopes:
   - `project:releases` (for managing releases)
   - `project:write` (for uploading source maps)
5. Save the token

#### Set Environment Variables
Create a `.env` file in the frontend directory:
```bash
cp .env.example .env
```

Edit `.env` with your values:
```bash
# Your Sentry organization slug (from URL: sentry.io/organizations/YOUR-ORG/)
SENTRY_ORG=your-org-slug

# Your Sentry project slug (NOT the folder name!)
# Find it in: Project Settings → General Settings → Project Slug
SENTRY_PROJECT=your-project-slug

# Auth token from step above
SENTRY_AUTH_TOKEN=your-token-here
```

**Important:** The `SENTRY_PROJECT` is your Sentry project slug, not the folder name! 
For example, if your project URL is `sentry.io/organizations/acme/projects/web-app/`, then:
- `SENTRY_ORG=acme`
- `SENTRY_PROJECT=web-app`

### 3. Development

```bash
# Start development server
npm start

# Or use the development build script (no source map upload)
./build-dev.sh

# The app will be available at http://localhost:4200
```

### 4. Production Build with Source Maps

```bash
# Build and upload source maps with debug-ids
npm run build:prod

# This will:
# 1. Build the production app
# 2. Inject debug-ids into JS files
# 3. Upload source maps to Sentry
# 4. Optionally delete source maps from dist (set DELETE_SOURCEMAPS=true)
```

## Debug-IDs Integration

This project uses Sentry's debug-ids feature for automatic source map resolution:

- **No release management needed** - debug-ids are automatically generated
- **Automatic linking** - Sentry matches errors to source maps by debug-id
- **90-day retention** - Source maps are stored for 90 days
- **Simplified CI/CD** - Just run the upload script after each build

### Manual Source Map Upload

If you need to manually upload source maps:

```bash
# 1. Build production with source maps
npm run build -- --source-map

# 2. Inject debug-ids and upload
./upload-sourcemaps.sh

# Optional: Delete source maps before deployment
DELETE_SOURCEMAPS=true ./upload-sourcemaps.sh
```

## CI/CD Integration

For automated deployments, ensure these environment variables are set in your CI/CD:

```yaml
env:
  SENTRY_ORG: ${{ secrets.SENTRY_ORG }}
  SENTRY_PROJECT: ${{ secrets.SENTRY_PROJECT }}
  SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
  DELETE_SOURCEMAPS: true  # Remove source maps after upload
```

## Troubleshooting

### Source Maps Not Working
1. Check that debug-ids were injected: Look for `//# debugId=` comments in JS files
2. Verify upload succeeded: Check Sentry project settings → Source Maps
3. Ensure Sentry SDK version is 7.47.0 or higher

### Authentication Errors
1. Verify your auth token has the required scopes
2. Check that SENTRY_ORG and SENTRY_PROJECT match your Sentry account
3. Ensure the token hasn't expired

### Build Issues
- Source maps must be enabled in production build
- Angular 20 uses esbuild, not webpack
- Debug-ids are injected by Sentry CLI, not during build

## Development with Docker

When using `start-dev.sh` from the root:
- The script automatically increments version numbers
- Environment files are generated with the new version
- Source maps are NOT uploaded in development mode
- Debug-ids are still generated but not uploaded
- Use `./start-prod.sh` for production mode with source map upload

### Available Scripts

| Script | Description |
|--------|-------------|
| `./start-dev.sh` | Start in development mode (no source map upload) |
| `./start-prod.sh` | Start in production mode (with source map upload) |
| `./build-dev.sh` | Build for development without source map upload |
| `npm run build` | Production build |
| `npm run build:upload` | Production build + source map upload |