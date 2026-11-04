import assert from 'node:assert/strict';
import { once } from 'node:events';
import { test } from 'node:test';
import { listQuery } from '../src/queries.js';
import { MemoryStore, MongoStore } from '../src/store.js';
import { seedData } from '../src/server.js';
import { createApiServer } from '../src/http.js';

test('book search combines literal keyword, genre and numeric sorting', async () => {
  const store = new MemoryStore(await seedData());
  const query = params => store.query('books', listQuery('books', new URLSearchParams(params)));
  assert.equal((await query({ q: 'MONGO' }))[0].bookCode, 'B001');
  assert.equal((await query({ q: 'Nguyễn Văn A' }))[0].bookCode, 'B002');
  assert.equal((await query({ q: 'NXB Kim Đồng' }))[0].bookCode, 'B006');
  assert.equal((await query({ q: 'mongo', category: 'Văn học' })).length, 0);
  assert.equal((await query({ category: 'Công nghệ thông tin', sort: 'publishedYear', order: 'desc' }))[0].bookCode, 'B003');
  assert.equal((await query({ q: '.*' })).length, 0);
  assert.equal((await query({ q: '[' })).length, 0);
  assert.equal((await query({ available: 'false' })).length, 0);
  assert.equal((await query({ available: 'true' })).length, 8);
  const asc = await query({ sort: 'availableCopies' });
  assert.deepEqual(asc.map(book => book.availableCopies), [5, 6, 7, 8, 9, 10, 12, 15]);
  assert.equal((await store.categories()).length, 4);
});

test('reader/staff search and loan status, overdue, reader and nested book filters', async () => {
  const seed = await seedData();
  seed.loans = [
    { loanCode: 'L1', readerId: 'R001', staffId: 'S001', status: 'BORROWING', dueDate: '2000-01-01T00:00:00Z', items: [{ bookCode: 'B001', title: 'MongoDB' }] },
    { loanCode: 'L2', readerId: 'R002', status: 'RETURNED', dueDate: '2000-01-01T00:00:00Z', items: [] },
  ];
  const store = new MemoryStore(seed);
  const query = (name, params) => store.query(name, listQuery(name, new URLSearchParams(params)));
  assert.equal((await query('readers', { q: '0901000001' }))[0].readerId, 'R001');
  assert.equal((await query('staff', { q: 'S001' })).length, 1);
  assert.equal((await query('loans', { q: 'mongo', overdue: 'true', readerId: 'R001', staffId: 'S001' }))[0].loanCode, 'L1');
  assert.equal((await query('loans', { status: 'RETURNED', overdue: 'true' })).length, 0);
  assert.equal((await query('loans', { status: 'RETURNED' }))[0].loanCode, 'L2');
});

test('query parameters reject operator injection, invalid sorts and duplicate values', () => {
  for (const params of ['sort=$where', 'order=bad', 'status=BAD', 'q[x]=x', 'available=1', 'q=a&q=b', 'q=' + 'x'.repeat(201)]) {
    assert.throws(() => listQuery('books', new URLSearchParams(params)), error => error.status === 400);
  }
  assert.throws(() => listQuery('readers', new URLSearchParams('category=IT')), error => error.status === 400);
});

test('Mongo adapter executes filter/sort/collation and indexed detail queries in database', async () => {
  const expected = listQuery('books', new URLSearchParams({ q: 'mongo', category: 'IT', sort: 'publishedYear', order: 'desc' }));
  const cursor = {
    collation(value) { assert.deepEqual(value, { locale: 'vi', strength: 3 }); return this; },
    sort(value) { assert.deepEqual(value, expected.sort); return this; },
    async toArray() { return [{ bookCode: 'B001' }]; },
  };
  const db = { collection(name) {
    assert.equal(name, 'books');
    return {
      find(filter, options) { assert.deepEqual(filter, expected.filter); assert.equal(options.maxTimeMS, 10000); return cursor; },
      async findOne(filter) { assert.deepEqual(filter, { bookCode: 'B001' }); return { bookCode: 'B001' }; },
      async distinct(field) { assert.equal(field, 'category'); return ['IT', 'Văn học', null]; },
    };
  } };
  const store = new MongoStore({}, db);
  assert.equal((await store.query('books', expected))[0].bookCode, 'B001');
  assert.equal((await store.findOne('books', { bookCode: 'B001' })).bookCode, 'B001');
  assert.equal((await store.categories()).length, 2);
});

test('HTTP exposes query strings, single records and genres without changing list response shape', async t => {
  const server = createApiServer({ store: new MemoryStore(await seedData()), demo: true });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const get = path => fetch(`http://127.0.0.1:${server.address().port}${path}`);
  const books = await (await get('/books?q=mongo&sort=title&order=desc')).json();
  assert.equal(books.length, 1);
  assert.equal(books[0].bookCode, 'B001');
  assert.equal((await (await get('/books/B001')).json()).bookCode, 'B001');
  assert.equal((await get('/books/UNKNOWN')).status, 404);
  assert.equal((await (await get('/books/categories')).json()).length, 4);
  assert.equal((await get('/books?sort=$where')).status, 400);
  assert.equal((await (await get('/readers?q=R001')).json()).length, 1);
});
