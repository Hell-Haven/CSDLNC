import assert from 'node:assert/strict';
import { once } from 'node:events';
import { randomUUID } from 'node:crypto';
import { test } from 'node:test';
import { configuration, databaseConfig } from '../src/config.js';
import { SqlStore } from '../src/store.js';
import { listQuery } from '../src/queries.js';
import { Library } from '../../server/src/library.js';
import { createApiServer } from '../../server/src/http.js';

const enabled = process.env.SQL_INTEGRATION_TEST === 'true';
test('real SQL: CRUD, nested JSON, HTTP contract, borrow/return and rollback', { skip: !enabled }, async () => {
  const { env } = configuration();
  const { sql, config } = databaseConfig(env);
  const pool = await new sql.ConnectionPool(config).connect();
  const root = new SqlStore(sql, pool);
  const before = (await root.all('books')).length;
  const code = 'T' + randomUUID().replaceAll('-', '').slice(0, 16);
  const rollback = new Error('ROLLBACK_TEST_DATA');
  try {
    await assert.rejects(root.atomic(async tx => {
      const library = new Library(tx);
      const book = { bookCode: code, title: 'Sách kiểm thử SQL', authors: ['Tác giả A', 'Tác giả B'], category: 'Kiểm thử', publisher: { name: 'NXB kiểm thử', year: 2026 }, publishedYear: 2026, totalCopies: 3, availableCopies: 3, status: 'ACTIVE' };
      const reader = { readerId: code, fullName: 'Độc giả thử', email: 'test@example.com', phone: '', address: '', status: 'ACTIVE' };
      const staff = { staffId: code, fullName: 'Nhân viên thử', email: 'staff@example.com', role: 'LIBRARIAN', status: 'ACTIVE' };
      await library.save('books', book);
      await library.save('readers', reader);
      await library.save('staff', staff);
      const saved = await library.find(tx, 'books', code);
      assert.deepEqual(saved.authors, book.authors);
      assert.deepEqual(saved.publisher, book.publisher);
      assert.equal((await tx.query('books', listQuery('books', new URLSearchParams({ q: 'Tác giả B', category: 'Kiểm thử' })))).some(b => b.bookCode === code), true);
      await library.save('books', { ...book, title: 'Tên đã sửa' }, code);
      const loan = await library.borrow({ readerId: code, staffId: code, dueDate: new Date(Date.now() + 86400000).toISOString(), items: [{ bookCode: code, quantity: 2 }] });
      assert.equal((await library.find(tx, 'books', code)).availableCopies, 1);
      assert.equal((await library.find(tx, 'loans', loan.loanCode)).items[0].title, 'Tên đã sửa');
      await assert.rejects(library.delete('books', code), error => error.status === 409);
      await library.returns(loan.loanCode, { items: [{ bookCode: code, quantity: 1 }] });
      assert.equal((await library.find(tx, 'loans', loan.loanCode)).status, 'BORROWING');
      await library.returns(loan.loanCode, { items: [{ bookCode: code, quantity: 1 }] });
      assert.equal((await library.find(tx, 'loans', loan.loanCode)).status, 'RETURNED');
      assert.equal((await library.find(tx, 'books', code)).availableCopies, 3);
      const server = createApiServer({ store: tx, mode: 'sqlserver', database: config.database, buildListQuery: listQuery,
        ping: () => tx.execute('SELECT 1'), categoryStats: () => tx.categoryStats() });
      server.listen(0, '127.0.0.1');
      await once(server, 'listening');
      try {
        const base = 'http://127.0.0.1:' + server.address().port;
        assert.equal((await (await fetch(base + '/health')).json()).mode, 'sqlserver');
        const snapshot = await (await fetch(base + '/snapshot')).json();
        assert.equal(snapshot.mode, 'sqlserver');
        assert.ok(snapshot.categories.some(c => c.category === 'Kiểm thử'));
        assert.equal((await (await fetch(base + '/books?q=' + code)).json())[0].bookCode, code);
      } finally { await new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }); }
      const removable = { ...book, bookCode: code + 'X' };
      await library.save('books', removable);
      await library.delete('books', removable.bookCode);
      assert.equal(await tx.findOne('books', { bookCode: removable.bookCode }), null);
      throw rollback;
    }), error => error === rollback);
    assert.equal((await root.all('books')).length, before);
    assert.equal(await root.findOne('readers', { readerId: code }), null);
  } finally { await pool.close(); }
});

test('real SQL: failure after stock update rolls back the entire loan transaction', { skip: !enabled }, async () => {
  const { env } = configuration();
  const { sql, config } = databaseConfig(env);
  const pool = await new sql.ConnectionPool(config).connect();
  const root = new SqlStore(sql, pool);
  try {
    const books = await root.all('books');
    const book = books.find(b => b.status === 'ACTIVE' && b.availableCopies > 0);
    const reader = (await root.all('readers')).find(r => r.status === 'ACTIVE');
    const staff = (await root.all('staff')).find(s => s.status === 'ACTIVE');
    assert.ok(book && reader && staff, 'Chạy npm run setup để có dữ liệu mẫu.');
    const library = new Library(root);
    const before = (await root.all('loans')).length;
    await assert.rejects(library.borrow({ readerId: reader.readerId, staffId: staff.staffId, dueDate: new Date(Date.now() + 86400000).toISOString(),
      items: [{ bookCode: book.bookCode, quantity: 1 }, { bookCode: '__DOES_NOT_EXIST__', quantity: 1 }] }), error => error.status === 404);
    assert.equal((await root.findOne('books', { bookCode: book.bookCode })).availableCopies, book.availableCopies);
    assert.equal((await root.all('loans')).length, before);
  } finally { await pool.close(); }
});
