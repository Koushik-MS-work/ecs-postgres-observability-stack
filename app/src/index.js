const express = require('express');
const client = require('prom-client');
const { checkDbConnection } = require('./db');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());

// --- Prometheus metrics ---------------------------------------------------
// Exposed on /metrics and scraped either by the Prometheus container
// (monitoring/docker-compose.monitoring.yml) or by a CloudWatch agent /
// ADOT sidecar in ECS. Covers the "application metrics" requirement:
// request rate, error rate, and latency.
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
});
register.registerMetric(httpRequestDuration);

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
});
register.registerMetric(httpRequestsTotal);

app.use((req, res, next) => {
  const endTimer = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path;
    const labels = { method: req.method, route, status_code: res.statusCode };
    httpRequestsTotal.inc(labels);
    endTimer(labels);
  });
  next();
});

// --- Routes ----------------------------------------------------------------

app.get('/', (req, res) => {
  res.json({ service: 'devops-project-app', status: 'ok' });
});

// Liveness/readiness probe used by the ALB target group health check and by
// the ECS container health check (see terraform/ecs.tf, terraform/alb.tf).
app.get('/health', async (req, res) => {
  try {
    const db = await checkDbConnection();
    res.status(200).json({ status: 'healthy', db });
  } catch (err) {
    res.status(503).json({ status: 'unhealthy', error: err.message });
  }
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/api/items', (req, res) => {
  res.json({ items: [{ id: 1, name: 'sample-item' }] });
});

// Simple 500 for pipeline error-budget demos, gated behind an env var so it
// never fires in a real deployment by accident.
app.get('/api/simulate-error', (req, res) => {
  if (process.env.ALLOW_ERROR_SIMULATION !== 'true') {
    return res.status(404).json({ error: 'not found' });
  }
  return res.status(500).json({ error: 'simulated failure' });
});

app.use((req, res) => {
  res.status(404).json({ error: 'not found' });
});

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  // eslint-disable-next-line no-console
  console.error(JSON.stringify({ level: 'error', message: err.message, stack: err.stack }));
  res.status(500).json({ error: 'internal server error' });
});

if (require.main === module) {
  app.listen(port, () => {
    // Structured logging to stdout -> picked up by the awslogs driver and
    // shipped to CloudWatch Logs / Fluent Bit (see monitoring/fluent-bit).
    // eslint-disable-next-line no-console
    console.log(JSON.stringify({ level: 'info', message: `app listening on port ${port}` }));
  });
}

module.exports = app;
