import { buildHealthResponse } from './health';

describe('buildHealthResponse', () => {
  it('returns a valid health payload', () => {
    const response = buildHealthResponse();

    expect(response.status).toBe('ok');
    expect(response.service).toBe('realworld-api');
    expect(response.timestamp).toBeDefined();
    expect(typeof response.uptimeSeconds).toBe('number');
  });
});
