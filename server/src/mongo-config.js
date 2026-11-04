import { setServers } from 'node:dns';
import { isIP } from 'node:net';

// Optional per-process DNS override for Atlas SRV/TXT lookup.
// Does not change Windows network settings.
export function configureMongoDns(environment) {
  if (!environment.MONGODB_DNS_SERVERS?.trim()) return;
  const servers = environment.MONGODB_DNS_SERVERS.split(',').map(value => value.trim());
  if (servers.some(server => !isIP(server))) {
    throw new Error('MONGODB_DNS_SERVERS phải là các địa chỉ IP phân cách bằng dấu phẩy.');
  }
  setServers(servers);
}
