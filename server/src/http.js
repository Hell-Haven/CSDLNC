import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';
import { ApiError } from './store.js';
import { isDoc, keys, Library } from './library.js';
import { listQuery } from './queries.js';

export function jsonValue(value) {
  if (value instanceof Date) return value.toISOString();
  if (value?.toHexString) return value.toHexString();
  if (Array.isArray(value)) return value.map(jsonValue);
  if (isDoc(value)) return Object.fromEntries(Object.entries(value)
    .filter(([key]) => !key.startsWith('_')).map(([key, item]) => [key, jsonValue(item)]));
  return value;
}

async function body(req) {
  const chunks = [];
  let size = 0;
  // Keep the socket available to return a JSON 413, without buffering more data.
  let tooLarge = false;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 100000) tooLarge = true;
    if (!tooLarge) chunks.push(chunk);
  }
  if (tooLarge) throw new ApiError(413, 'Yêu cầu quá lớn.');
  let value;
  try { value = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new ApiError(400, 'JSON hoặc kiểu dữ liệu không hợp lệ.'); }
  if (!isDoc(value)) throw new ApiError(400, 'Nội dung cần là JSON object.');
  return value;
}

async function serveWeb(res, pathname, root) {
  let parts;
  try { parts = pathname.split('/').filter(Boolean).map(decodeURIComponent); }
  catch { throw new ApiError(400, 'Đường dẫn không hợp lệ.'); }
  if (!parts.length) parts = ['index.html'];
  if (parts.some(part => part === '..' || !/^[A-Za-z0-9_.-]+$/.test(part))) {
    throw new ApiError(400, 'Đường dẫn không hợp lệ.');
  }
  const file = resolve(root, ...parts);
  if (!file.startsWith(resolve(root) + sep)) throw new ApiError(400, 'Đường dẫn không hợp lệ.');
  let content;
  try { content = await readFile(file); }
  catch (error) {
    if (['ENOENT', 'EISDIR', 'ENOTDIR'].includes(error.code)) throw new ApiError(404, 'Không tìm thấy tệp.');
    throw error;
  }
  const mime = {
    '.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.json': 'application/json',
    '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml',
    '.ttf': 'font/ttf', '.otf': 'font/otf', '.ico': 'image/x-icon',
  };
  res.setHeader('Content-Type', mime[extname(file)] ?? 'application/octet-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.end(content);
}

export function createApiServer({ store, db, demo = false, token = '', allowedOrigin, webRoot,
  mode = demo ? 'demo' : 'atlas', database = 'library_db', buildListQuery = listQuery,
  ping, categoryStats }) {
  const library = new Library(store);
  const server = createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (origin && (origin === allowedOrigin || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin))) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
    }
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type,X-API-Key');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    try {
      if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }
      const url = new URL(req.url, 'http://localhost');
      const pathname = url.pathname;
      let path;
      try { path = pathname.split('/').filter(Boolean).map(decodeURIComponent); }
      catch { throw new ApiError(400, 'Đường dẫn không hợp lệ.'); }
      if (webRoot && req.method === 'GET' && (!path.length || path[0].includes('.') ||
          ['assets', 'canvaskit', 'icons'].includes(path[0]))) {
        await serveWeb(res, pathname, webRoot);
        return;
      }
      if (token && req.headers['x-api-key'] !== token) throw new ApiError(401, 'API_KEY không hợp lệ.');
      let output;
      const route = path.join('/');
      if (req.method === 'GET' && route === 'health') {
        // Lệnh ping kiểm tra kết nối MongoDB thật mỗi khi gọi /health.
        if (ping) await ping();
        else if (db) await db.command({ ping: 1 });
        output = { mode, database };
      } else if (req.method === 'GET' && route === 'snapshot') {
        output = {};
        // Đọc bốn collection để cung cấp dữ liệu trang chủ, lịch sử và biểu mẫu.
        for (const name of Object.keys(keys)) output[name] = await store.all(name);
        // Aggregation Pipeline: thống kê số đầu sách và tổng số bản của từng thể loại.
        if (categoryStats) output.categories = await categoryStats();
        else if (db) output.categories = await db.collection('books').aggregate([
          // $group gom theo category; $sum: 1 đếm đầu sách, $sum: '$totalCopies' cộng số bản.
          { $group: { _id: '$category', titles: { $sum: 1 }, copies: { $sum: '$totalCopies' } } },
          // $sort sắp thể loại có nhiều đầu sách nhất lên trước.
          { $sort: { titles: -1 } },
          // $project bỏ _id và đổi khóa nhóm thành category cho Flutter sử dụng.
          { $project: { _id: 0, category: '$_id', titles: 1, copies: 1 } },
        ]).toArray();
        output.mode = mode;
      } else if (req.method === 'GET' && route === 'books/categories') {
        // Lấy danh sách thể loại không trùng bằng distinct('category').
        output = await store.categories();
      } else if (path.length === 1 && req.method === 'GET' && Object.hasOwn(keys, path[0])) {
        // Tạo filter/sort từ URL rồi gửi xuống MongoDB bằng find().sort().
        output = await store.query(path[0], buildListQuery(path[0], url.searchParams));
      } else if (path.length === 2 && req.method === 'GET' && Object.hasOwn(keys, path[0])) {
        // Ví dụ GET /books/B001 gọi findOne({ bookCode: 'B001' }).
        output = await library.find(store, path[0], path[1]);
      } else if (path.length === 1 && req.method === 'POST' && path[0] === 'loans') {
        output = await library.borrow(await body(req));
        res.statusCode = 201;
      } else if (path.length === 3 && req.method === 'POST' && path[0] === 'loans' && path[2] === 'return') {
        await library.returns(path[1], await body(req));
        output = { message: 'Đã ghi nhận trả sách.' };
      } else if (path.length === 1 && req.method === 'POST' && ['books', 'readers', 'staff'].includes(path[0])) {
        await library.save(path[0], await body(req));
        res.statusCode = 201;
        output = { message: 'Đã thêm.' };
      } else if (path.length === 2 && req.method === 'PUT' && Object.hasOwn(keys, path[0])) {
        await library.save(path[0], await body(req), path[1]);
        output = { message: 'Đã cập nhật.' };
      } else if (path.length === 2 && req.method === 'DELETE' && Object.hasOwn(keys, path[0])) {
        await library.delete(path[0], path[1]);
        output = { message: 'Đã xóa.' };
      } else throw new ApiError(404, 'Không tìm thấy API.');
      res.end(JSON.stringify(jsonValue(output)));
    } catch (error) {
      res.statusCode = error instanceof ApiError ? error.status : error.code === 11000 ? 409 : 503;
      res.end(JSON.stringify({ message: error instanceof ApiError ? error.message : error.code === 11000
        ? 'Mã đã tồn tại.' : 'Không xử lý được yêu cầu. Kiểm tra kết nối rồi tải lại dữ liệu.' }));
    }
  });
  server.requestTimeout = 30000;
  return server;
}
