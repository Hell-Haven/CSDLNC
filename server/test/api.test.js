import assert from 'node:assert/strict';
import { test } from 'node:test';
import { once } from 'node:events';
import { MemoryStore } from '../src/store.js';
import { Library } from '../src/library.js';
import { createApiServer, jsonValue } from '../src/http.js';
import { seedData, seedStore } from '../src/server.js';

const status = code => error => error.status === code;
async function fixture() {
  const store = new MemoryStore(await seedData());
  return { store, library: new Library(store) };
}
const request = (items = [{ bookCode: 'B001', quantity: 2 }]) => ({
  readerId: 'R001', staffId: 'S001', dueDate: new Date(Date.now() + 86400000).toISOString(), items,
});

test('book CRUD, duplicate codes, immutable code and stock validation', async () => {
  const { store, library } = await fixture();
  const book = { ...(await store.all('books'))[0], bookCode: 'TEST' };
  await library.save('books', book);
  await assert.rejects(library.save('books', book), status(409));
  book.title = 'Sách tiếng Việt';
  await library.save('books', book, 'TEST');
  assert.equal((await library.find(store, 'books', 'TEST')).title, book.title);
  await assert.rejects(library.save('books', book, 'B001'), status(400));
  await assert.rejects(library.save('books', { ...book, availableCopies: 100 }), status(400));
  await assert.rejects(library.save('books', { ...book, availableCopies: 1 }), status(400));
  await assert.rejects(library.save('books', { ...book, totalCopies: 1.5 }), status(400));
  await assert.rejects(library.save('books', { ...book, authors: [] }), status(400));
  await assert.rejects(library.save('books', { ...book, publisher: null }), status(400));
  await library.delete('books', 'TEST');
  await assert.rejects(library.find(store, 'books', 'TEST'), status(404));
});

test('reader and staff CRUD, registered date, email and status validation', async () => {
  const { store, library } = await fixture();
  for (const [collection, key] of [['readers', 'readerId'], ['staff', 'staffId']]) {
    const doc = { ...(await store.all(collection))[0], [key]: 'TEST' };
    await library.save(collection, doc);
    const created = await library.find(store, collection, 'TEST');
    await library.save(collection, { ...doc, fullName: 'Tên mới' }, 'TEST');
    const updated = await library.find(store, collection, 'TEST');
    assert.equal(updated.fullName, 'Tên mới');
    if (collection === 'readers') assert.equal(updated.registeredAt, created.registeredAt);
    await assert.rejects(library.save(collection, { ...doc, email: 'bad' }, 'TEST'), status(400));
    await assert.rejects(library.save(collection, { ...doc, status: 'bad' }, 'TEST'), status(400));
    await library.delete(collection, 'TEST');
  }
});

test('multi-book loan and partial/full returns keep historical title and references', async () => {
  const { store, library } = await fixture();
  const before = (await store.all('books'))[0];
  const loan = await library.borrow(request([{ bookCode: 'B001', quantity: 2 }, { bookCode: 'B002', quantity: 1 }]));
  assert.equal((await library.find(store, 'books', 'B001')).availableCopies, before.availableCopies - 2);
  for (const [collection, code] of [['books', 'B001'], ['readers', 'R001'], ['staff', 'S001']]) {
    await assert.rejects(library.delete(collection, code), status(409));
  }
  const book = await library.find(store, 'books', 'B001');
  await assert.rejects(library.save('books', { ...book, availableCopies: book.totalCopies }, 'B001'), status(409));
  await library.save('books', { ...book, title: 'Đổi tên' }, 'B001');
  assert.equal((await library.find(store, 'loans', loan.loanCode)).items[0].title, before.title);
  await library.returns(loan.loanCode, { items: [{ bookCode: 'B001', quantity: 1 }] });
  assert.equal((await library.find(store, 'loans', loan.loanCode)).status, 'BORROWING');
  await library.returns(loan.loanCode, { items: [{ bookCode: 'B001', quantity: 1 }, { bookCode: 'B002', quantity: 1 }] });
  assert.equal((await library.find(store, 'loans', loan.loanCode)).status, 'RETURNED');
  assert.equal((await library.find(store, 'books', 'B001')).availableCopies, before.availableCopies);
  await assert.rejects(library.returns(loan.loanCode, { items: [{ bookCode: 'B001', quantity: 1 }] }), status(409));
});

test('failed loan and partial return roll back every earlier stock update', async () => {
  const { store, library } = await fixture();
  const before = await store.all('books');
  await assert.rejects(library.borrow(request([{ bookCode: 'B001', quantity: 1 }, { bookCode: 'B002', quantity: 1000 }])), status(409));
  assert.deepEqual(await store.all('books'), before);
  assert.deepEqual(await store.all('loans'), []);
  const loan = await library.borrow(request([{ bookCode: 'B001', quantity: 2 }, { bookCode: 'B002', quantity: 1 }]));
  const borrowed = await store.all('books');
  await assert.rejects(library.returns(loan.loanCode, { items: [{ bookCode: 'B001', quantity: 1 }, { bookCode: 'B002', quantity: 2 }] }), status(409));
  assert.deepEqual(await store.all('books'), borrowed);
  assert.equal((await store.all('loans'))[0].items[0].returnedQuantity, 0);
});

test('concurrent borrowers cannot overdraw stock and loan codes are unique', async () => {
  const { store, library } = await fixture();
  const result = await Promise.allSettled(Array.from({ length: 20 }, () => library.borrow(request([{ bookCode: 'B001', quantity: 1 }]))));
  assert.equal(result.filter(r => r.status === 'fulfilled').length, 12);
  assert.equal((await library.find(store, 'books', 'B001')).availableCopies, 0);
  const loans = await store.all('loans');
  assert.equal(new Set(loans.map(l => l.loanCode)).size, 12);
});

test('invalid loan/return input and inactive or unknown references are rejected', async () => {
  const { library, store } = await fixture();
  for (const input of [
    { ...request(), dueDate: 'invalid' }, { ...request(), dueDate: 0 },
    { ...request(), dueDate: '2000-01-01' }, { ...request(), readerId: 'UNKNOWN' },
    request([]), request([null]), request([{ bookCode: 'B001', quantity: -1 }]),
    request([{ bookCode: 'B001', quantity: 1 }, { bookCode: 'B001', quantity: 1 }]),
  ]) await assert.rejects(library.borrow(input), error => [400, 404].includes(error.status));
  const loan = await library.borrow(request());
  for (const items of [[], [null], [{ bookCode: 'B002', quantity: 1 }], [{ bookCode: 'B001', quantity: 0 }],
    [{ bookCode: 'B001', quantity: 1 }, { bookCode: 'B001', quantity: 1 }]]) {
    await assert.rejects(library.returns(loan.loanCode, { items }), status(400));
  }
  for (const [collection, code] of [['readers', 'R001'], ['staff', 'S001'], ['books', 'B001']]) {
    const doc = await library.find(store, collection, code);
    await library.save(collection, { ...doc, status: 'INACTIVE' }, code);
    await assert.rejects(library.borrow(request()), status(409));
    await library.save(collection, doc, code);
  }
});

test('seed is idempotent and preserves modified existing records', async () => {
  const { library, store } = await fixture();
  const book = (await store.all('books'))[0];
  await library.save('books', { ...book, title: 'Giữ nguyên' }, book.bookCode);
  await store.remove('books', 'bookCode', 'B008');
  await seedStore(store, await seedData());
  await seedStore(store, await seedData());
  assert.equal((await store.all('books')).length, 8);
  assert.equal((await library.find(store, 'books', book.bookCode)).title, 'Giữ nguyên');
});

test('HTTP contract matches Flutter: JSON, CORS, API key, CRUD, loans, errors', async t => {
  const { store } = await fixture();
  const server = createApiServer({ store, demo: true, token: 'test-key' });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (path, method = 'GET', data) => fetch(base + path, {
    method, headers: { 'X-API-Key': 'test-key', 'Content-Type': 'application/json', Origin: 'http://localhost:5173' },
    body: data === undefined ? undefined : JSON.stringify(data),
  });
  assert.equal((await fetch(base + '/health')).status, 401);
  const preflight = await fetch(base + '/books', { method: 'OPTIONS', headers: { Origin: 'http://localhost:5173' } });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), 'http://localhost:5173');
  const health = await call('/health');
  assert.deepEqual(await health.json(), { mode: 'demo', database: 'library_db' });
  const snapshot = await (await call('/snapshot')).json();
  assert.equal(snapshot.books.length, 8);
  assert.equal(snapshot.mode, 'demo');
  assert.ok(snapshot.books[0].title.includes('Cơ sở'));
  assert.equal(snapshot.books[0]._version, undefined);
  const book = { ...snapshot.books[0], bookCode: 'HTTP' };
  assert.equal((await call('/books', 'POST', book)).status, 201);
  assert.equal((await call('/books', 'POST', book)).status, 409);
  assert.equal((await call('/books/HTTP', 'PUT', { ...book, title: 'Đã sửa' })).status, 200);
  assert.equal((await call('/books/HTTP', 'DELETE')).status, 200);
  const loanResponse = await call('/loans', 'POST', request());
  assert.equal(loanResponse.status, 201);
  const loan = await loanResponse.json();
  assert.equal((await call(`/loans/${loan.loanCode}/return`, 'POST', { items: [{ bookCode: 'B001', quantity: 2 }] })).status, 200);
  assert.equal((await call(`/loans/${loan.loanCode}`, 'DELETE')).status, 405);
  assert.equal((await call('/unknown')).status, 404);
  assert.equal((await call('/toString')).status, 404);
  assert.equal((await call('/books', 'POST', [])).status, 400);
  const raw = data => fetch(base + '/books', { method: 'POST', headers: { 'X-API-Key': 'test-key' }, body: data });
  assert.equal((await raw('{bad')).status, 400);
  assert.equal((await raw('x'.repeat(100001))).status, 413);
});

test('API without a key allows local demo and strips MongoDB internal fields', async t => {
  const { store } = await fixture();
  const server = createApiServer({ store, demo: true });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }));
  assert.equal((await fetch(`http://127.0.0.1:${server.address().port}/health`)).status, 200);
  assert.deepEqual(jsonValue({ _id: 'secret', nested: { _version: 1, date: new Date('2026-01-01Z') } }),
    { nested: { date: '2026-01-01T00:00:00.000Z' } });
});
