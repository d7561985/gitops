#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Get environment variables from command line or process.env
// Keep existing Sentry DSN if env variable not provided
const sentryDsn = process.env.SENTRY_DSN || 'https://d438ac686202e2a66a89a98989c66b6a@o4509616118562816.ingest.de.sentry.io/4509616119808080';
const apiUrl = process.env.API_URL || '';
const version = process.env.APP_VERSION || '1.0.0';
const useConnectProtocol = process.env.USE_CONNECT_PROTOCOL === 'true';
const production = process.env.NODE_ENV === 'production';

// Generate environment.ts content
const devContent = `export const environment = {
  production: false,
  sentryDsn: '${sentryDsn}',
  apiUrl: '${apiUrl}',
  version: '${version}-dev',
  useConnectProtocol: ${useConnectProtocol}
};
`;

// Generate environment.prod.ts content
const prodContent = `export const environment = {
  production: true,
  sentryDsn: '${sentryDsn}',
  apiUrl: '${apiUrl}',
  version: '${version}',
  useConnectProtocol: ${useConnectProtocol}
};
`;

// Write files
const envDir = path.join(__dirname, '..', 'src', 'environments');

// Create environments directory if it doesn't exist
if (!fs.existsSync(envDir)) {
  fs.mkdirSync(envDir, { recursive: true });
}

fs.writeFileSync(path.join(envDir, 'environment.ts'), devContent);
fs.writeFileSync(path.join(envDir, 'environment.prod.ts'), prodContent);

console.log(`Environment files generated with:`);
console.log(`  SENTRY_DSN: ${sentryDsn}`);
console.log(`  API_URL: ${apiUrl}`);
console.log(`  VERSION: ${version}`);
console.log(`  USE_CONNECT_PROTOCOL: ${useConnectProtocol}`);