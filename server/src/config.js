import { existsSync, readFileSync } from 'node:fs';

export function loadEnvironment(file, environment = process.env) {
  const values = {};
  if (existsSync(file)) {
    readFileSync(file, 'utf8').split(/\r?\n/).forEach((raw, index) => {
      const line = raw.trim();
      if (!line || line.startsWith('#')) return;
      const separator = line.indexOf('=');
      const key = line.slice(0, separator).trim();
      if (separator < 1 || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
        throw new Error(`Cấu hình .env không hợp lệ ở dòng ${index + 1}.`);
      }
      let value = line.slice(separator + 1).trim();
      if (value.startsWith('"') || value.startsWith("'")) {
        if (value.length < 2 || !value.endsWith(value[0])) {
          throw new Error(`Thiếu dấu đóng chuỗi .env ở dòng ${index + 1}.`);
        }
        value = value.slice(1, -1);
      }
      values[key] = value;
    });
  }
  return { ...values, ...environment };
}

export function serverConfig(environment) {
  const host = environment.HOST ?? '127.0.0.1';
  const rawPort = environment.PORT ?? '8080';
  const port = Number(rawPort);
  if (!/^\d+$/.test(rawPort) || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error('PORT phải là số nguyên từ 1 đến 65535.');
  }
  const token = environment.API_KEY ?? '';
  if (!['127.0.0.1', 'localhost', '::1'].includes(host) && !token) {
    throw new Error('Khi mở API ra mạng LAN, cần đặt API_KEY.');
  }
  return { host, port, token, allowedOrigin: environment.ALLOWED_ORIGIN };
}
