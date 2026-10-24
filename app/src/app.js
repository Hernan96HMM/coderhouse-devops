const express = require('express');
const client = require('prom-client');

function createApp() {
  const app = express();
  app.disable('x-powered-by'); // no revelar que se usa Express (hallazgo DAST)
  app.use(express.json());

  // Cabeceras de seguridad (hallazgos DAST: X-Content-Type-Options y CSP)
  app.use((_req, res, next) => {
    res.set({
      'X-Content-Type-Options': 'nosniff',
      'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; form-action 'none'",
      'Cache-Control': 'no-store',
    });
    next();
  });

  const register = new client.Registry();
  client.collectDefaultMetrics({ register });

  const httpRequests = new client.Counter({
    name: 'http_requests_total',
    help: 'Total de requests HTTP',
    labelNames: ['method', 'route', 'status'],
    registers: [register],
  });

  const httpDuration = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duración de requests HTTP en segundos',
    labelNames: ['method', 'route', 'status'],
    buckets: [0.005, 0.01, 0.05, 0.1, 0.3, 0.5, 1, 2],
    registers: [register],
  });

  app.use((req, res, next) => {
    const end = httpDuration.startTimer();
    res.on('finish', () => {
      const route = req.route ? req.route.path : req.path;
      const labels = { method: req.method, route, status: res.statusCode };
      httpRequests.inc(labels);
      end(labels);
    });
    next();
  });

  app.get('/health', (_req, res) => res.json({ status: 'ok' }));

  app.get('/', (_req, res) =>
    res.json({
      service: 'pf-devops-app',
      version: process.env.APP_VERSION || 'dev',
      message: 'Proyecto final DevOps',
    })
  );

  app.get('/api/sum', (req, res) => {
    const a = Number(req.query.a);
    const b = Number(req.query.b);
    if (Number.isNaN(a) || Number.isNaN(b)) {
      return res.status(400).json({ error: 'Parámetros a y b deben ser numéricos' });
    }
    return res.json({ result: a + b });
  });

  // Endpoint que genera carga de CPU: útil para demostrar el HPA
  app.get('/api/load', (req, res) => {
    const ms = Math.min(Number(req.query.ms) || 200, 2000);
    const end = Date.now() + ms;
    while (Date.now() < end) {
      Math.sqrt(Math.random());
    }
    res.json({ burned_ms: ms });
  });

  app.get('/metrics', async (_req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  // 404 propio: evita la página de error por defecto de Express, que pisa nuestras cabeceras
  app.use((_req, res) => res.status(404).json({ error: 'No encontrado' }));

  return app;
}

module.exports = { createApp };
