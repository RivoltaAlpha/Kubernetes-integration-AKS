// Application Insights configuration for Node.js application
// Add this to your app/src/index.ts

import * as appInsights from 'applicationinsights';

// Initialize Application Insights
if (process.env.APPINSIGHTS_INSTRUMENTATIONKEY || process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  appInsights.setup()
    .setAutoDependencyCorrelation(true)
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true, true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true, true)
    .setUseDiskRetryCaching(true)
    .setSendLiveMetrics(true)
    .setDistributedTracingMode(appInsights.DistributedTracingModes.AI_AND_W3C)
    .start();

  // Set cloud role name for better tracking
  appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] = 'microservice-app';
  
  console.log('✅ Application Insights initialized');
} else {
  console.log('⚠️  Application Insights not configured');
}

// Custom metrics tracking example
export function trackCustomMetric(name: string, value: number) {
  if (appInsights.defaultClient) {
    appInsights.defaultClient.trackMetric({ name, value });
  }
}

// Track custom events
export function trackCustomEvent(name: string, properties?: { [key: string]: string }) {
  if (appInsights.defaultClient) {
    appInsights.defaultClient.trackEvent({ name, properties });
  }
}

// Add health check endpoint
export function setupHealthChecks(app: any) {
  // Liveness probe - is the app alive?
  app.get('/health', (req: any, res: any) => {
    res.status(200).json({ 
      status: 'healthy', 
      timestamp: new Date().toISOString() 
    });
  });

  // Readiness probe - is the app ready to serve traffic?
  app.get('/ready', (req: any, res: any) => {
    // Add checks for database, dependencies, etc.
    const checks = {
      app: 'ready',
      // database: checkDatabaseConnection(),
      // cache: checkCacheConnection(),
    };
    
    const isReady = Object.values(checks).every(status => status === 'ready');
    
    res.status(isReady ? 200 : 503).json({
      status: isReady ? 'ready' : 'not ready',
      checks,
      timestamp: new Date().toISOString()
    });
  });

  // Metrics endpoint for Prometheus
  app.get('/metrics', (req: any, res: any) => {
    // Implement Prometheus metrics here or use prom-client library
    res.set('Content-Type', 'text/plain');
    res.send('# Metrics endpoint\n');
  });
}
