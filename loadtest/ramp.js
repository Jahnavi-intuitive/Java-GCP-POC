import http from 'k6/http';
import { check, sleep } from 'k6';

const URL = __ENV.URL;
const TOKEN = __ENV.TOKEN;
const params = { headers: { 'X-Serverless-Authorization': `Bearer ${TOKEN}` } };

export const options = {
  stages: [
    { duration: '1m',  target: 20 },
    { duration: '1m',  target: 50 },
    { duration: '1m',  target: 50 },
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
  sleep(0.1);
}