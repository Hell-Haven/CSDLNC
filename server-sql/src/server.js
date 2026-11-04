import { pathToFileURL } from 'node:url';
import { configuration, databaseConfig } from './config.js';
import { SqlStore } from './store.js';
import { listQuery } from './queries.js';
import { createApiServer } from '../../server/src/http.js';

export async function start() {
  const { env, http } = configuration();
  const { sql, config } = databaseConfig(env);
  const pool = new sql.ConnectionPool(config);
  pool.on('error', () => console.error('Mất kết nối SQL Server. Kiểm tra dịch vụ và cấu hình.'));
  let server;
  try {
    await pool.connect();
    const store = new SqlStore(sql, pool);
    await store.execute("IF OBJECT_ID(N'dbo.LoanItems',N'U') IS NULL THROW 50001,N'Chạy npm run setup trước khi khởi động.',1;");
    server = createApiServer({ ...http, store, mode: 'sqlserver', database: config.database,
      buildListQuery: listQuery, ping: () => store.execute('SELECT 1 AS ok'), categoryStats: () => store.categoryStats() });
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(http.port, http.host, resolve); });
    console.log(`Thư viện API SQL Server: http://${http.host}:${http.port} • ${config.database}`);
    let closing = false;
    const close = async () => {
      if (closing) return;
      closing = true;
      await new Promise(resolve => { server.close(resolve); server.closeAllConnections(); });
      await pool.close();
    };
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => close().catch(() => { process.exitCode = 1; }));
    return { server, close };
  } catch (error) {
    await pool.close();
    if (error.code === 'EADDRINUSE') throw new Error(`Cổng ${http.port} đang được sử dụng. Dừng backend cũ hoặc đổi PORT.`);
    throw error;
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  start().catch(error => {
    console.error(`Không khởi động được backend SQL Server (${error.code || error.name}). Kiểm tra .env, dịch vụ SQL Server và chạy npm run setup lần đầu.`);
    process.exitCode = 1;
  });
}
