import assert from 'node:assert/strict';
import { test } from 'node:test';
import { listQuery } from '../src/queries.js';

test('SQL query uses parameters for keyword/category and allowlisted sort', () => {
  const q = listQuery('books', new URLSearchParams({ q: "x%' OR 1=1 --[_", category: 'Khoa học', sort: 'publishedYear', order: 'desc' }));
  assert.ok(q.where.includes('LIKE @q'));
  assert.ok(q.where.includes('EXISTS (SELECT 1 FROM dbo.BookAuthors'));
  assert.ok(q.where.includes('b.Category=@category'));
  assert.equal(q.where.includes('OR 1=1 --'), false);
  assert.equal(q.values.q, "%x~%' OR 1=1 --~[~_%");
  assert.equal(q.values.category, 'Khoa học');
  assert.equal(q.orderBy, 'b.PublishedYear DESC, b.BookCode ASC');
});

test('SQL filters availability, loan references and overdue separately', () => {
  const books = listQuery('books', new URLSearchParams('available=true&status=ACTIVE'));
  assert.ok(books.where.includes('b.AvailableCopies>0'));
  const loans = listQuery('loans', new URLSearchParams('q=mongo&readerId=R001&overdue=true&status=RETURNED'));
  assert.ok(loans.where.includes('dbo.LoanItems'));
  assert.ok(loans.where.includes('l.ReaderId=@readerId'));
  assert.ok(loans.where.includes("l.Status='BORROWING'"));
  assert.equal(loans.values.status, 'RETURNED');
  assert.equal(loans.values.readerId, 'R001');
});

test('SQL rejects query injection through sort, unknown keys and invalid states', () => {
  for (const params of ['sort=title;DROP TABLE Books', 'sort=toString', 'order=invalid', 'available=1', 'status=bad', 'q=a&q=b', 'q[x]=a', 'q=' + 'a'.repeat(201)]) {
    assert.throws(() => listQuery('books', new URLSearchParams(params)), error => error.status === 400);
  }
  assert.throws(() => listQuery('staff', new URLSearchParams('category=IT')), error => error.status === 400);
});
