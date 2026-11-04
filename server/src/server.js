import { readFile, access } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { loadEnvironment, serverConfig } from './config.js';
import { MemoryStore, MongoStore } from './store.js';
import { keys } from './library.js';
import { createApiServer } from './http.js';
import { configureMongoDns } from './mongo-config.js';

// Đọc dữ liệu mẫu từ JSON; hàm này chưa ghi vào MongoDB.
export async function seedData() {
  return JSON.parse(await readFile(new URL('../data/seed.json', import.meta.url), 'utf8'));
}

// Thêm dữ liệu mẫu trong transaction: chỉ insertOne() những mã chưa tồn tại, không ghi đè dữ liệu cũ.
export async function seedStore(store, seed) {
  await store.atomic(async tx => {
    for (const [collection, docs] of Object.entries(seed)) {
      const key = keys[collection];
      const old = await tx.all(collection);
      for (const doc of docs) {
        if (!old.some(d => d[key] === doc[key])) await tx.put(collection, key, doc, { create: true });
      }
    }
  });
}

export async function start(args = process.argv.slice(2)) {
  const environment = loadEnvironment(new URL('../.env', import.meta.url));
  const config = serverConfig(environment);
  const demo = args.includes('--demo');
  const webRoot = args.includes('--web')
    ? fileURLToPath(new URL('../../library_app/build/web/', import.meta.url)) : undefined;
  if (webRoot) {
    try { await access(new URL('../../library_app/build/web/index.html', import.meta.url)); }
    catch { throw new Error('Chạy flutter build web trong library_app trước khi dùng --web.'); }
  }
  let client;
  let db;
  let store;
  let server;
  try {
    if (demo) store = new MemoryStore(await seedData());
    else {
      const uri = environment.MONGODB_URI;
      if (!uri || /USER:PASSWORD|CLUSTER\.mongodb\.net/.test(uri)) {
        throw new Error('Điền MONGODB_URI thật vào server/.env hoặc chạy npm run demo.');
      }
      let parsed;
      try { parsed = new URL(uri); } catch { throw new Error('MONGODB_URI không hợp lệ.'); }
      if (!['mongodb:', 'mongodb+srv:'].includes(parsed.protocol) || parsed.pathname !== '/library_db') {
        throw new Error('URI phải chỉ rõ database /library_db trước dấu ?.');
      }
      const { MongoClient } = await import('mongodb');
      configureMongoDns(environment);
      client = new MongoClient(uri, { serverSelectionTimeoutMS: 10000 });
      await client.connect();
      db = client.db('library_db');
      await db.command({ ping: 1 });
      // listCollections() lấy tên collection hiện có; tạo collection còn thiếu trước transaction seed.
      const existing = new Set((await db.listCollections({}, { nameOnly: true }).toArray()).map(c => c.name));
      for (const [collection, key] of Object.entries(keys)) {
        if (!existing.has(collection)) await db.createCollection(collection);
        // Unique index ngăn trùng mã nghiệp vụ và hỗ trợ tìm chi tiết theo mã bằng findOne().
        await db.collection(collection).createIndex({ [key]: 1 }, { unique: true });
      }
      // Index ghép hỗ trợ tra lịch sử một độc giả và sắp ngày mượn mới nhất trước.
      await db.collection('loans').createIndex({ readerId: 1, borrowDate: -1 });
      // Index ghép hỗ trợ lọc phiếu theo trạng thái và hạn trả, bao gồm phiếu quá hạn.
      await db.collection('loans').createIndex({ status: 1, dueDate: 1 });
      // Index ghép hỗ trợ lọc thể loại rồi sắp tên sách và mã với collation tiếng Việt.
      await db.collection('books').createIndex(
        { category: 1, title: 1, bookCode: 1 }, { collation: { locale: 'vi', strength: 3 } },
      );
      store = new MongoStore(client, db);
      if (args.includes('--seed')) await seedStore(store, await seedData());
    }
    server = createApiServer({ store, db, demo, webRoot, ...config });
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(config.port, config.host, resolve);
    });
    console.log(`Thư viện API: http://${config.host}:${config.port} • ${demo ? 'DEMO: bộ nhớ tạm' : 'MongoDB Atlas: library_db'}`);
    let closing = false;
    const close = async () => {
      if (closing) return;
      closing = true;
      await new Promise(resolve => { server.close(resolve); server.closeAllConnections(); });
      await client?.close();
    };
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => {
      close().catch(() => { process.exitCode = 1; });
    });
    return { server, close };
  } catch (error) {
    await client?.close();
    if (error.code === 'EADDRINUSE') throw new Error(`Cổng ${config.port} đang được sử dụng. Dừng API cũ hoặc đổi PORT.`);
    // Never log driver errors or URIs: they may include credentials.
    if (error.name?.startsWith('Mongo')) {
      throw new Error('Không kết nối được MongoDB. Kiểm tra URI, Database User, IP Access List và dữ liệu trùng mã.');
    }
    throw error;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  start().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
