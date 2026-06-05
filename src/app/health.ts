
export function buildHealthResponse() {
  return {
    status: 'ok',
    service: 'realworld-api',
    environment: process.env.APP_ENV || 'local',
    commit: process.env.GIT_COMMIT || 'unknown',
    uptimeSeconds: Math.round(process.uptime()),
    timestamp: new Date().toISOString(),
  };
}

