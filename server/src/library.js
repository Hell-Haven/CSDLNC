import { randomUUID } from 'node:crypto';
import { ApiError } from './store.js';

export const keys = Object.freeze({ books: 'bookCode', readers: 'readerId', staff: 'staffId', loans: 'loanCode' });
export const isDoc = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const editable = ['books', 'readers', 'staff'];
function text(doc, key, optional = false) {
  const value = doc[key];
  if (value == null && optional) return '';
  if (typeof value !== 'string' || (!optional && !value.trim()) || value.length > 500) {
    throw new ApiError(400, `Trường ${key} không hợp lệ (tối đa 500 ký tự).`);
  }
  return value.trim();
}
function number(doc, key, min = 0, max = 100000) {
  const value = doc[key];
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ApiError(400, `${key} phải là số nguyên từ ${min} đến ${max}.`);
  }
  return value;
}
function state(doc) {
  const value = text(doc, 'status');
  if (!['ACTIVE', 'INACTIVE'].includes(value)) throw new ApiError(400, 'Trạng thái không hợp lệ.');
  return value;
}
function normalize(collection, input) {
  const key = keys[collection];
  const code = text(input, key);
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(code)) {
    throw new ApiError(400, 'Mã chỉ gồm chữ, số, _ hoặc -, tối đa 40 ký tự.');
  }
  if (collection === 'books') {
    const { authors, publisher } = input;
    if (!Array.isArray(authors) || !authors.length || authors.length > 20 ||
        authors.some(a => typeof a !== 'string' || !a.trim() || a.length > 200)) {
      throw new ApiError(400, 'Cần từ 1 đến 20 tác giả hợp lệ.');
    }
    if (!isDoc(publisher)) throw new ApiError(400, 'Thiếu nhà xuất bản.');
    const totalCopies = number(input, 'totalCopies');
    const availableCopies = number(input, 'availableCopies');
    if (availableCopies > totalCopies) throw new ApiError(400, 'Số bản còn không được vượt tổng số bản.');
    return {
      [key]: code, title: text(input, 'title'), authors: authors.map(a => a.trim()),
      category: text(input, 'category'),
      publisher: { name: text(publisher, 'name'), year: number(publisher, 'year', 1000, 2200) },
      publishedYear: number(input, 'publishedYear', 1000, 2200),
      totalCopies, availableCopies, status: state(input),
    };
  }
  const email = text(input, 'email');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new ApiError(400, 'Email không hợp lệ.');
  const result = { [key]: code, fullName: text(input, 'fullName'), email, status: state(input) };
  if (collection === 'readers') Object.assign(result, {
    phone: text(input, 'phone', true), address: text(input, 'address', true),
  });
  else result.role = text(input, 'role');
  return result;
}

export class Library {
  constructor(store) { this.store = store; }
  // Tìm theo mã nghiệp vụ qua store: MongoDB dùng findOne(), SQL Server dùng SELECT theo khóa.
  // Trả lỗi 404 nếu không tồn tại; nghiệp vụ này được hai backend dùng chung.
  async find(tx, collection, code) {
    const doc = await tx.findOne(collection, { [keys[collection]]: code });
    if (!doc) throw new ApiError(404, `Không tìm thấy ${code}.`);
    return doc;
  }
  // Thêm/sửa sách, độc giả, nhân viên sau khi kiểm tra dữ liệu và quy tắc tồn kho.
  // Không truyền code: thêm mới; có code: cập nhật, không được đổi mã.
  // MongoStore dùng insertOne/updateOne, SqlStore dùng INSERT/UPDATE tham số hóa.
  async save(collection, input, code) {
    if (!editable.includes(collection)) throw new ApiError(404, 'Không hỗ trợ danh mục này.');
    const doc = normalize(collection, input);
    const key = keys[collection];
    if (code !== undefined && doc[key] !== code) throw new ApiError(400, 'Không được đổi mã.');
    await this.store.atomic(async tx => {
      if (code !== undefined) {
        const old = await this.find(tx, collection, code);
        if (collection === 'books' && doc.totalCopies - doc.availableCopies !== old.totalCopies - old.availableCopies) {
          throw new ApiError(409, 'Số bản đang mượn phải được giữ nguyên. Hãy dùng chức năng mượn/trả.');
        }
        if (collection === 'readers') doc.registeredAt = old.registeredAt;
      } else if (collection === 'readers') doc.registeredAt = new Date().toISOString();
      if (collection === 'books' && code === undefined && doc.availableCopies !== doc.totalCopies) {
        throw new ApiError(400, 'Sách mới phải có số bản còn bằng tổng số bản.');
      }
      doc._version = randomUUID();
      await tx.put(collection, key, doc, { create: code === undefined });
    });
  }
  // Chỉ xóa khi chưa có phiếu mượn tham chiếu: deleteOne() ở MongoDB, DELETE ở SQL Server.
  // Kiểm tra tham chiếu và xóa được thực hiện trong cùng transaction.
  async delete(collection, code) {
    if (!editable.includes(collection)) throw new ApiError(405, 'Không xóa phiếu mượn để bảo toàn lịch sử.');
    await this.store.atomic(async tx => {
      await this.find(tx, collection, code);
      // Tìm mã sách trong mảng items bằng items.bookCode; độc giả/nhân viên dùng mã tương ứng.
      const referenced = await tx.findOne('loans', {
        [collection === 'books' ? 'items.bookCode' : keys[collection]]: code,
      });
      if (referenced) throw new ApiError(409, 'Bản ghi đã có lịch sử mượn. Hãy chuyển sang Ngừng hoạt động.');
      await tx.remove(collection, keys[collection], code);
    });
  }
  // Lập phiếu mượn: kiểm tra độc giả/nhân viên, giảm số bản còn và thêm phiếu mới qua store.
  // Tất cả nằm trong một transaction; một sách không đủ thì hủy toàn bộ thao tác.
  async borrow(input) {
    const readerId = text(input, 'readerId');
    const staffId = text(input, 'staffId');
    const rawDate = input.dueDate;
    const due = new Date(typeof rawDate === 'string' ? rawDate : NaN);
    if (!Number.isFinite(due.getTime())) throw new ApiError(400, 'dueDate phải là ngày ISO 8601.');
    const now = new Date();
    if (due <= now) throw new ApiError(400, 'Hạn trả phải sau thời điểm hiện tại.');
    if (!Array.isArray(input.items) || !input.items.length || input.items.length > 30) {
      throw new ApiError(400, 'Phiếu cần từ 1 đến 30 đầu sách.');
    }
    const seen = new Set();
    const requested = input.items.map(item => {
      if (!isDoc(item)) throw new ApiError(400, 'Dòng sách không hợp lệ.');
      const bookCode = text(item, 'bookCode');
      if (seen.has(bookCode)) throw new ApiError(400, 'Không được lặp mã sách trong phiếu.');
      seen.add(bookCode);
      return { bookCode, quantity: number(item, 'quantity', 1, 1000) };
    });
    const loanCode = `L${randomUUID()}`;
    return this.store.atomic(async tx => {
      for (const [collection, code] of [['readers', readerId], ['staff', staffId]]) {
        const person = await this.find(tx, collection, code);
        if (person.status !== 'ACTIVE') throw new ApiError(409, `${code} đã ngừng hoạt động.`);
        // MongoDB dùng phiên bản để tạo xung đột khi ghi đồng thời; SQL dùng khóa trong transaction.
        person._version = randomUUID();
        await tx.put(collection, keys[collection], person);
      }
      const items = [];
      for (const item of requested) {
        const book = await this.find(tx, 'books', item.bookCode);
        if (book.status !== 'ACTIVE' || book.availableCopies < item.quantity) {
          throw new ApiError(409, `${book.title}: không đủ sách khả dụng.`);
        }
        // Cập nhật tồn kho trước khi thêm phiếu; giữ tên sách tại thời điểm mượn vào items.
        book.availableCopies -= item.quantity;
        await tx.put('books', 'bookCode', book);
        items.push({ bookCode: book.bookCode, title: book.title, quantity: item.quantity, returnedQuantity: 0 });
      }
      const loan = {
        loanCode, readerId, staffId, borrowDate: now.toISOString(), dueDate: due.toISOString(),
        status: 'BORROWING', items,
      };
      await tx.put('loans', 'loanCode', loan, { create: true });
      return loan;
    });
  }
  // Trả sách: tăng tồn kho, tăng returnedQuantity và cập nhật phiếu trong cùng transaction.
  // Chỉ chuyển RETURNED khi tất cả dòng sách đã được trả đủ; hỗ trợ trả từng phần.
  async returns(code, input) {
    if (!Array.isArray(input.items) || !input.items.length) throw new ApiError(400, 'Chọn ít nhất một sách để trả.');
    const seen = new Set();
    for (const item of input.items) {
      if (!isDoc(item)) throw new ApiError(400, 'Dòng trả không hợp lệ.');
      const bookCode = text(item, 'bookCode');
      if (seen.has(bookCode)) throw new ApiError(400, 'Mã sách bị lặp.');
      seen.add(bookCode);
      number(item, 'quantity', 1, 1000);
    }
    await this.store.atomic(async tx => {
      const loan = await this.find(tx, 'loans', code);
      if (loan.status === 'RETURNED') throw new ApiError(409, 'Phiếu đã trả toàn bộ.');
      for (const request of input.items) {
        const line = loan.items.find(item => item.bookCode === request.bookCode);
        if (!line) throw new ApiError(400, 'Sách không thuộc phiếu.');
        if (line.returnedQuantity + request.quantity > line.quantity) throw new ApiError(409, 'Số trả vượt số còn mượn.');
        const book = await this.find(tx, 'books', request.bookCode);
        if (book.availableCopies + request.quantity > book.totalCopies) throw new ApiError(409, 'Tồn kho không nhất quán.');
        book.availableCopies += request.quantity;
        line.returnedQuantity += request.quantity;
        await tx.put('books', 'bookCode', book);
      }
      if (loan.items.every(item => item.returnedQuantity === item.quantity)) loan.status = 'RETURNED';
      await tx.put('loans', 'loanCode', loan);
    });
  }
}
