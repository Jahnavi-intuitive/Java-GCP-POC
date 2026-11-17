import http from 'k6/http';
import { check } from 'k6';

// Usage: k6 run -e URL=... -e TOKEN=... -e RATE=1000 rate.js
// Holds a fixed request rate (open model), independent of response time.
const URL = __ENV.URL;
const TOKEN = __ENV.TOKEN;
const RATE = parseInt(__ENV.RATE || '1000');
const params = { headers: { 'X-Serverless-Authorization': `Bearer ${TOKEN}` } };

export const options = {
  scenarios: {
    rate: {
      executor: 'ramping-arrival-rate',
      startRate: Math.floor(RATE / 2),
      timeUnit: '1s',
      preAllocatedVUs: 800,
      maxVUs: 3000,
      stages: [
        { duration: '1m',  target: RATE },
        { duration: '2m',  target: RATE },
        { duration: '30s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed:   ['rate<0.01'],
  },
};

const paths = ['/data/products', '/data/product_categories', '/public/about'];

export default function () {
  const path = paths[Math.floor(Math.random() * paths.length)];
  const res = http.get(`${URL}${path}`, params);
  check(res, { 'status is 200': (r) => r.status === 200 });
}
