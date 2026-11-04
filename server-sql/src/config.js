import { createRequire } from 'node:module';
import { loadEnvironment, serverConfig } from '../../server/src/config.js';

const require = createRequire(import.meta.url);

export function configuration() {
  const env = loadEnvironment(new URL('../.env', import.meta.url));
  return { env, http: serverConfig({ ...env, PORT: env.PORT ?? '8081' }) };
}

// Chọn driver theo kiểu đăng nhập; thông tin kết nối chỉ đọc từ .env của backend SQL.
export function databaseConfig(env, database = env.SQL_DATABASE || 'LibrarySqlDemo') {
  if (!/^[A-Za-z][A-Za-z0-9_]{0,127}$/.test(database)) throw new Error('SQL_DATABASE không hợp lệ.');
  const windows = (env.SQL_AUTH || 'windows') === 'windows';
  if (!['windows', 'sql'].includes(env.SQL_AUTH || 'windows')) throw new Error('SQL_AUTH phải là windows hoặc sql.');
  const sql = require(windows ? 'mssql/msnodesqlv8' : 'mssql');
  const parts = (env.SQL_SERVER || 'localhost\\SQLEXPRESS').split('\\');
  const config = {
    server: parts[0], database,
    connectionTimeout: 10000, requestTimeout: 15000,
    pool: { min: 0, max: 10, idleTimeoutMillis: 30000 },
    options: {
      instanceName: parts[1],
      encrypt: env.SQL_ENCRYPT === 'true',
      trustServerCertificate: env.SQL_TRUST_SERVER_CERTIFICATE !== 'false',
      useUTC: true, abortTransactionOnError: true,
      ...(windows ? { trustedConnection: true } : {}),
    },
  };
  if (windows) config.driver = env.SQL_ODBC_DRIVER || 'ODBC Driver 17 for SQL Server';
  else {
    if (!env.SQL_USER || !env.SQL_PASSWORD) throw new Error('Điền SQL_USER và SQL_PASSWORD cho SQL_AUTH=sql.');
    config.user = env.SQL_USER;
    config.password = env.SQL_PASSWORD;
  }
  if (env.SQL_PORT) {
    config.port = Number(env.SQL_PORT);
    if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) throw new Error('SQL_PORT không hợp lệ.');
    delete config.options.instanceName;
  }
  return { sql, config };
}
