// Read-only connection/schema/query smoke check. Never prints credentials or records.
import { MongoClient } from 'mongodb';
import { loadEnvironment } from './config.js';
import { MongoStore } from './store.js';
import { listQuery } from './queries.js';
import { configureMongoDns } from './mongo-config.js';

const environment = loadEnvironment(new URL('../.env', import.meta.url));
let client;
try {
  configureMongoDns(environment);
  client = new MongoClient(environment.MONGODB_URI, { serverSelectionTimeoutMS: 10000 });
  await client.connect();
  const db = client.db('library_db');
  await db.command({ ping: 1 });
  console.log('Atlas ping: OK');
  for (const [collection, key] of Object.entries({ books: 'bookCode', readers: 'readerId', staff: 'staffId', loans: 'loanCode' })) {
    const count = await db.collection(collection).countDocuments({});
    const missing = await db.collection(collection).countDocuments({ [key]: { $exists: false } });
    console.log(`${collection}: ${count} documents; missing ${key}: ${missing}`);
    if (missing) process.exitCode = 1;
  }
  const store = new MongoStore(client, db);
  const books = await store.query('books', listQuery('books', new URLSearchParams({ sort: 'title' })));
  console.log(`MongoDB find/sort/collation: OK (${books.length} books)`);
  console.log(`MongoDB distinct: OK (${(await store.categories()).length} categories)`);
  const sample = books.find(book => typeof book.title === 'string' && book.title.trim());
  if (sample) {
    const results = await store.query('books', listQuery('books', new URLSearchParams({ q: sample.title, category: sample.category ?? '' })));
    if (!results.some(book => book.bookCode === sample.bookCode)) throw new Error('QUERY_MISMATCH');
    console.log('MongoDB keyword + category filter: OK');
  }
} catch (error) {
  // Driver messages may contain URI credentials, so report only safe error codes.
  console.error(`Atlas verification failed (${error.code ?? error.name ?? 'unknown'}). Check URI, IP Access List, database user and field names.`);
  process.exitCode = 1;
} finally { await client?.close(); }
