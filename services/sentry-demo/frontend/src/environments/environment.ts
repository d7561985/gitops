export const environment = {
  production: false,
  sentryDsn: 'https://d438ac686202e2a66a89a98989c66b6a@o4509616118562816.ingest.de.sentry.io/4509616119808080',
  apiUrl: '',  // Empty - API calls go to /api/* on same domain via Gateway
  version: '1.0.91-dev',
  // Protocol switching: true = Connect protocol, false = REST
  useConnectProtocol: true,
};
