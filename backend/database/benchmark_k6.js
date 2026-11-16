import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '15s', target: 50 },
    { duration: '30s', target: 200 },
    { duration: '15s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<50'], // Hedef: 50 ms altı uzamsal sorgu yanıtı
  },
};

const BASE_URL = __ENV.API_URL || 'http://localhost:5088';

export default function () {
  const lat = 41.0119 + (Math.random() - 0.5) * 0.01;
  const lon = 28.9639 + (Math.random() - 0.5) * 0.01;

  const nearbyRes = http.get(`${BASE_URL}/api/capsules?lat=${lat}&lon=${lon}&radiusMeters=1500`);
  check(nearbyRes, {
    'nearby status 200': (r) => r.status === 200,
  });

  const benchRes = http.get(`${BASE_URL}/api/spatial/benchmark?count=10000&radius=5&iterations=50`);
  check(benchRes, {
    'benchmark status 200': (r) => r.status === 200,
  });

  sleep(0.2);
}
