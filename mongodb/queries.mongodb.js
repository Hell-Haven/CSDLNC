// MongoDB Playground / mongosh. Select and run each example separately.
// Read queries below are safe to run together. Writes are commented out.
// Field names match server/data/seed.json; collection names alone do not define a schema.
const library = db.getSiblingDB('library_db');

// READ: all books, details, search by title/code/author/publisher (case insensitive).
library.books.find({});
library.books.findOne({ bookCode: 'B001' });
library.books.find({ $or: [
  { title: { $regex: 'mongo', $options: 'i' } },
  { bookCode: { $regex: 'mongo', $options: 'i' } },
  { authors: { $regex: 'mongo', $options: 'i' } },
  { 'publisher.name': { $regex: 'mongo', $options: 'i' } },
] });

// FILTER + SORT: exact genre, available books, newest publication first.
library.books.find({ category: 'Công nghệ thông tin', availableCopies: { $gt: 0 }, status: 'ACTIVE' })
  .sort({ publishedYear: -1, bookCode: 1 });
library.books.find({ category: 'Công nghệ thông tin' })
  .collation({ locale: 'vi', strength: 3 }).sort({ title: 1, bookCode: 1 });
library.books.distinct('category');

// READ: readers/staff and loan history.
library.readers.find({ fullName: { $regex: 'Trí', $options: 'i' } }).sort({ fullName: 1 });
library.staff.find({ status: 'ACTIVE' }).sort({ staffId: 1 });
library.loans.find({ readerId: 'R001' }).sort({ borrowDate: -1 });
library.loans.find({ status: 'BORROWING', dueDate: { $lt: new Date() } }).sort({ dueDate: 1 });
library.loans.find({ 'items.title': { $regex: 'mongo', $options: 'i' } });

// CREATE: uncomment only the individual example you want to insert.
// library.books.insertOne({
//   bookCode: 'DEMO_B001', title: 'Sách thực hành MongoDB', authors: ['Tác giả demo'],
//   category: 'Công nghệ thông tin', publisher: { name: 'NXB Demo', year: 2026 },
//   publishedYear: 2026, totalCopies: 5, availableCopies: 5, status: 'ACTIVE'
// });
// library.readers.insertOne({
//   readerId: 'DEMO_R001', fullName: 'Độc giả demo', email: 'reader.demo@example.com',
//   phone: '', address: '', registeredAt: new Date(), status: 'ACTIVE'
// });
// library.staff.insertOne({
//   staffId: 'DEMO_S001', fullName: 'Nhân viên demo', email: 'staff.demo@example.com',
//   role: 'Thủ thư', status: 'ACTIVE'
// });

// UPDATE: $set changes only the specified fields; business codes stay immutable.
// library.books.updateOne({ bookCode: 'DEMO_B001' }, { $set: { title: 'Tên sách đã sửa', category: 'Khoa học' } });
// library.readers.updateOne({ readerId: 'DEMO_R001' }, { $set: { phone: '0900000000' } });
// library.staff.updateOne({ staffId: 'DEMO_S001' }, { $set: { role: 'Quản lý' } });

// DELETE: use the API for deletion; it checks loan references inside a transaction.
// Raw examples below are ONLY for unreferenced demo records you just created.
// library.books.deleteOne({ bookCode: 'DEMO_B001' });
// library.readers.deleteOne({ readerId: 'DEMO_R001' });
// library.staff.deleteOne({ staffId: 'DEMO_S001' });

// Loans are created/returned through POST /loans and POST /loans/:code/return.
// These endpoints update both loans and book stock in one MongoDB transaction.
// Do not insert/delete a loan directly without updating the corresponding stock.
