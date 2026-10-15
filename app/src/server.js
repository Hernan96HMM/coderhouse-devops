const { createApp } = require('./app');

const port = Number(process.env.PORT) || 3000;
const server = createApp().listen(port, () => {
  console.log(JSON.stringify({ level: 'info', msg: 'server started', port }));
});

// Apagado ordenado para que Kubernetes pueda reemplazar pods sin cortar requests
process.on('SIGTERM', () => {
  console.log(JSON.stringify({ level: 'info', msg: 'SIGTERM received, closing' }));
  server.close(() => process.exit(0));
});
