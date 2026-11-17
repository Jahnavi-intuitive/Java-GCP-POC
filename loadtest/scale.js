import http from 'k6/http';
import { check, sleep } from 'k6';

// Usage: k6 run -e URL=... -e TOKEN=... -e VUS=1000 scale.js
// One user sends about one request per second (1 s think time).
const URL = __ENV.URL;
const TOKEN = __ENV.TOKEN;
const VUS = parseInt(__ENV.VUS || '1000');
const params = { headers: { 'X-Serverless-Authorization': `Bearer ${TOKEN}` } };

export const options = {
  stages: [
    { duration: '1m',  target: Math.floor(VUS / 2) },
    { duration: '1m',  target: VUS },
    { duration: '2m',  target: VUS },
    { duration: '30s', target: 0 },
  ],
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
  sleep(1);
}
