import assert from 'node:assert/strict';
import { test } from 'node:test';
import { MongoStore } from '../src/store.js';

test('Mongo adapter passes one session to reads/writes and stores BSON dates', async () => {
  const calls = [];
  const session = {
    async withTransaction(action, options) {
      assert.equal(options.readConcern.level, 'snapshot');
      assert.equal(options.writeConcern.w, 'majority');
      return action();
    },
    async endSession() { calls.push('end'); },
  };
  const collection = {
    find(filter, options) {
      assert.equal(options.session, session);
      return { async toArray() { return []; } };
    },
    async insertOne(doc, options) {
      assert.equal(options.session, session);
      assert.equal(doc._id, undefined);
      assert.ok(doc.dueDate instanceof Date);
      calls.push('insert');
    },
    async updateOne(filter, update, options) {
      assert.equal(options.session, session);
      assert.deepEqual(filter, { loanCode: 'L1' });
      assert.ok(update.$set.dueDate instanceof Date);
      calls.push('update');
      return { matchedCount: 1 };
    },
    async deleteOne(filter, options) {
      assert.equal(options.session, session);
      calls.push('delete');
    },
  };
  const store = new MongoStore({ startSession: () => session }, { collection: () => collection });
  const value = await store.atomic(async tx => {
    await tx.all('loans');
    const doc = { _id: 'old', loanCode: 'L1', dueDate: '2026-12-01T00:00:00Z' };
    await tx.put('loans', 'loanCode', doc, { create: true });
    await tx.put('loans', 'loanCode', doc);
    await tx.remove('loans', 'loanCode', 'L1');
    return 'committed';
  });
  assert.equal(value, 'committed');
  assert.deepEqual(calls, ['insert', 'update', 'delete', 'end']);
});

test('Mongo adapter ends session and propagates failed transaction', async () => {
  let ended = false;
  const session = {
    withTransaction: action => action(),
    async endSession() { ended = true; },
  };
  const store = new MongoStore({ startSession: () => session }, {});
  await assert.rejects(store.atomic(() => { throw new Error('rollback'); }), /rollback/);
  assert.equal(ended, true);
});
