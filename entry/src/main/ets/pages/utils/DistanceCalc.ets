// DistanceCalc.ets - 距离计算工具
const EARTH_RADIUS = 6378137.0;

function toRadians(degree: number): number {
  return degree * Math.PI / 180.0;
}

export function calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const radLat1 = toRadians(lat1);
  const radLat2 = toRadians(lat2);
  const a = radLat1 - radLat2;
  const b = toRadians(lng1) - toRadians(lng2);

  let s = 2 * Math.asin(Math.sqrt(Math.pow(Math.sin(a / 2), 2) +
    Math.cos(radLat1) * Math.cos(radLat2) * Math.pow(Math.sin(b / 2), 2)));
  s = s * EARTH_RADIUS;
  s = Math.round(s * 10000) / 10000;

  return s;
}

export function formatDistance(distance: number): string {
  if (distance < 1000) {
    return `${Math.round(distance)}米`;
  } else {
    return `${(distance / 1000).toFixed(1)}公里`;
  }
}
