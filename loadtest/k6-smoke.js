// =============================================================================
// k6-smoke.js — Load test smoke 100 users · 5 min (v0.4.3)
// =============================================================================
// Verifica que el sistema aguanta 100 usuarios concurrentes haciendo flow básico.
//
// Uso:
//   k6 run -e BASE_URL=http://localhost:6700 -e API_URL=http://localhost:6601 loadtest/k6-smoke.js
//
// O contra prod:
//   k6 run -e BASE_URL=https://ams.tuempresa.cl -e API_URL=https://api.ams.tuempresa.cl loadtest/k6-smoke.js
//
// Métricas que verifica:
//   - http_req_duration p95 < 1s (sin LLM)
//   - http_req_failed < 1%
//   - System acepta sin caer (no 5xx)
// =============================================================================

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:6700';
const API_URL = __ENV.API_URL || 'http://localhost:6601';

export const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Warmup: ramp up a 10 users
    { duration: '1m', target: 50 },    // Ramp a 50
    { duration: '2m', target: 100 },   // Sostener 100 users por 2 min
    { duration: '1m', target: 100 },   // Mantener 100
    { duration: '30s', target: 0 },    // Cooldown
  ],
  thresholds: {
    'http_req_duration{type:non-llm}': ['p(95)<1000'],   // 95% < 1s para non-LLM
    'http_req_duration{type:llm}': ['p(95)<10000'],      // 95% < 10s para LLM
    'http_req_failed': ['rate<0.01'],                     // <1% errores
    'errors': ['rate<0.05'],                              // custom <5%
  },
};

export default function () {
  // Test 1: Status endpoint (no LLM)
  const status = http.get(`${API_URL}/api/status`, { tags: { type: 'non-llm' } });
  check(status, {
    'status 200': (r) => r.status === 200,
    'status up': (r) => r.json('status') === 'up',
  }) || errorRate.add(1);

  sleep(1);

  // Test 2: Health (no LLM)
  const health = http.get(`${API_URL}/health`, { tags: { type: 'non-llm' } });
  check(health, { 'health 200': (r) => r.status === 200 }) || errorRate.add(1);

  sleep(0.5);

  // Test 3: Admin usage summary (no LLM, lee DB)
  const usage = http.get(`${API_URL}/api/admin/usage/summary`, { tags: { type: 'non-llm' } });
  check(usage, {
    'usage 200': (r) => r.status === 200,
    'usage has totals': (r) => r.json('totals') !== undefined,
  }) || errorRate.add(1);

  sleep(2);

  // Test 4: Frontend home (Next.js)
  const home = http.get(`${BASE_URL}/`, { tags: { type: 'non-llm' }, redirects: 0 });
  check(home, { 'home redirect or 200': (r) => [200, 307, 308].includes(r.status) }) || errorRate.add(1);

  sleep(1);

  // Test 5: Login page
  const login = http.get(`${BASE_URL}/login`, { tags: { type: 'non-llm' } });
  check(login, { 'login 200': (r) => r.status === 200 }) || errorRate.add(1);

  sleep(1);
}

export function handleSummary(data) {
  return {
    'stdout': textSummary(data),
    'loadtest-report.html': htmlReport(data),
  };
}

function textSummary(data) {
  const m = data.metrics;
  return `
==========================================
LOAD TEST RESULTS
==========================================
Total requests:       ${m.http_reqs?.values?.count ?? 0}
Failed requests:      ${(m.http_req_failed?.values?.rate ?? 0) * 100}%
P50 duration:         ${m.http_req_duration?.values?.['p(50)']?.toFixed(0)}ms
P95 duration:         ${m.http_req_duration?.values?.['p(95)']?.toFixed(0)}ms
P99 duration:         ${m.http_req_duration?.values?.['p(99)']?.toFixed(0)}ms
Errors custom:        ${(m.errors?.values?.rate ?? 0) * 100}%

Thresholds:
${Object.entries(m).filter(([_, v]) => v.thresholds).map(([k, v]) => {
    const pass = !Object.values(v.thresholds).some((t) => !t.ok);
    return `  ${pass ? '✓' : '✗'} ${k}`;
  }).join('\n')}
`;
}

function htmlReport() {
  return `<html><body><h1>k6 Load Test Report</h1><p>Ver detalles en consola.</p></body></html>`;
}
