import { readFile } from 'node:fs/promises';
import { configuration, databaseConfig } from './config.js';

// Tạo database/bảng và thêm seed khi người dùng chủ động chạy npm run setup.
// Không tự tạo hoặc thêm dữ liệu mỗi khi chạy backend; không truy cập MongoDB.
const { env } = configuration();
let pool;
try {
  const name = env.SQL_DATABASE || 'LibrarySqlDemo';
  const { sql, config } = databaseConfig(env, 'master');
  pool = await new sql.ConnectionPool(config).connect();
  // Tên database được kiểm tra trước khi đưa vào câu lệnh định danh.
  databaseConfig(env, name);
  await pool.request().input('name', sql.NVarChar(128), name).query(`IF DB_ID(@name) IS NULL EXEC(N'CREATE DATABASE [${name}]');`);
  await pool.close();
  pool = await new sql.ConnectionPool({ ...config, database: name }).connect();
  const exists = await pool.request().query("SELECT OBJECT_ID(N'dbo.Books',N'U') AS id");
  if (!exists.recordset[0].id) {
    const text = await readFile(new URL('../../sqlserver/01_create_library_db.sql', import.meta.url), 'utf8');
    const schema = text.slice(text.indexOf('SET XACT_ABORT ON;')).replace(/^GO\s*$/gm, '');
    await pool.request().batch(schema);
    console.log('Đã tạo bảy bảng SQL Server.');
  } else console.log('Database đã có bảng Books; giữ nguyên cấu trúc hiện có.');
  const seed = (await readFile(new URL('../../sqlserver/02_seed_library_db.sql', import.meta.url), 'utf8')).replace(/^\uFEFF/, '')
    .replace(/^USE LibrarySqlDemo;\s*$/gm, '').replace(/^GO\s*$/gm, '');
  await pool.request().batch(seed);
  console.log(`Setup thành công: ${name}. Seed chỉ thêm mã chưa tồn tại.`);
} catch (error) {
  console.error(`Setup SQL Server thất bại (${error.code || error.name}). Kiểm tra instance, quyền tạo database và cấu trúc bảng.`);
  process.exitCode = 1;
} finally { await pool?.close(); }
