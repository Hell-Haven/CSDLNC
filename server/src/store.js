export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// Đọc trường nhúng hoặc trường bên trong mảng, ví dụ items.bookCode, cho chế độ demo.
function valuesAt(doc, path) {
  if (Array.isArray(doc)) return doc.flatMap(item => valuesAt(item, path));
  if (!path.length) return [doc];
  return valuesAt(doc?.[path[0]], path.slice(1));
}
// Mô phỏng các điều kiện $or, $and, $regex, $gt, $lt trong RAM; không gọi MongoDB.
function matches(doc, filter) {
  return Object.entries(filter).every(([field, condition]) => {
    if (field === '$or') return condition.some(part => matches(doc, part));
    if (field === '$and') return condition.every(part => matches(doc, part));
    return valuesAt(doc, field.split('.')).some(value => {
      if (condition?.$regex !== undefined) return typeof value === 'string' && new RegExp(condition.$regex, condition.$options).test(value);
      if (condition?.$gt !== undefined) return value > condition.$gt;
      if (condition?.$lt !== undefined) return condition.$lt instanceof Date
        ? new Date(value) < condition.$lt : value < condition.$lt;
      return value === condition;
    });
  });
}

// Kho dữ liệu demo: mô phỏng truy vấn trên RAM, dữ liệu mất khi khởi động lại server.
export class MemoryStore {
  #queue = Promise.resolve();
  constructor(data) { this.data = structuredClone(data); }
  async all(collection) { return structuredClone(this.data[collection] ?? []); }
  async findOne(collection, filter) {
    return structuredClone((this.data[collection] ?? []).find(doc => matches(doc, filter)) ?? null);
  }
  async query(collection, { filter, sort }) {
    const collator = new Intl.Collator('vi', { sensitivity: 'variant' });
    return (await this.all(collection)).filter(doc => matches(doc, filter)).sort((a, b) => {
      for (const [key, order] of Object.entries(sort)) {
        const left = a[key], right = b[key];
        const compare = typeof left === 'string' && typeof right === 'string'
          ? collator.compare(left, right) : left < right ? -1 : left > right ? 1 : 0;
        if (compare) return compare * order;
      }
      return 0;
    });
  }
  async categories() {
    return [...new Set((await this.all('books')).map(book => book.category))]
      .filter(value => typeof value === 'string' && value).sort((a, b) => a.localeCompare(b, 'vi'));
  }
  async put(collection, key, doc, { create = false } = {}) {
    const list = this.data[collection] ??= [];
    const index = list.findIndex(entry => entry[key] === doc[key]);
    if (create && index >= 0) throw new ApiError(409, 'Mã đã tồn tại.');
    if (!create && index < 0) throw new ApiError(404, 'Không tìm thấy bản ghi.');
    if (index < 0) list.push(structuredClone(doc));
    else list[index] = structuredClone(doc);
  }
  async remove(collection, key, value) {
    this.data[collection] = (this.data[collection] ?? []).filter(doc => doc[key] !== value);
  }
  async atomic(action) {
    const previous = this.#queue;
    let release;
    this.#queue = new Promise(resolve => { release = resolve; });
    await previous;
    const tx = new MemoryStore(this.data);
    try {
      const result = await action(tx);
      this.data = tx.data;
      return result;
    } finally { release(); }
  }
}

// Kho dữ liệu thật: mọi phương thức dưới đây gửi lệnh qua MongoDB driver đến Atlas.
export class MongoStore {
  constructor(client, db, session) {
    this.client = client;
    this.db = db;
    this.session = session;
  }
  // Truyền cùng session vào từng lệnh để các lệnh thuộc cùng transaction.
  get options() { return this.session ? { session: this.session } : {}; }
  // READ: find({}) lấy toàn bộ bản ghi; toArray() đọc hết cursor thành mảng cho snapshot/seed.
  async all(collection) {
    return this.db.collection(collection).find({}, this.options).toArray();
  }
  // READ: tìm một bản ghi theo điều kiện, ví dụ { bookCode: 'B001' }; không có thì trả null.
  async findOne(collection, filter) {
    return this.db.collection(collection).findOne(filter, this.options);
  }
  // READ: tìm kiếm, lọc và sắp xếp ngay trên MongoDB theo đối tượng do listQuery() tạo.
  // collation tiếng Việt dùng khi so sánh/sắp xếp chuỗi; maxTimeMS giới hạn thực thi truy vấn 10 giây.
  async query(collection, { filter, sort }) {
    return this.db.collection(collection).find(filter, { ...this.options, maxTimeMS: 10000 })
      .collation({ locale: 'vi', strength: 3 }).sort(sort).toArray();
  }
  // DISTINCT: lấy các thể loại khác nhau từ books, bỏ giá trị trống và sắp tên tiếng Việt.
  async categories() {
    const values = await this.db.collection('books').distinct('category', {}, this.options);
    return values.filter(value => typeof value === 'string' && value).sort((a, b) => a.localeCompare(b, 'vi'));
  }
  // CREATE/UPDATE: create=true dùng insertOne(); còn lại updateOne() theo mã nghiệp vụ.
  async put(collection, key, doc, { create = false } = {}) {
    // Không cập nhật _id vì đây là khóa bất biến do MongoDB quản lý.
    const { _id, ...payload } = doc;
    // Chuyển ngày ISO từ API thành BSON Date để MongoDB so sánh ngày và lọc quá hạn chính xác.
    for (const field of ['registeredAt', 'borrowDate', 'dueDate']) {
      if (typeof payload[field] === 'string') payload[field] = new Date(payload[field]);
    }
    if (create) await this.db.collection(collection).insertOne(payload, this.options);
    else {
      // $set chỉ thay các trường có trong payload, giữ lại những trường khác của document.
      const result = await this.db.collection(collection).updateOne(
        { [key]: doc[key] }, { $set: payload }, this.options,
      );
      if (!result.matchedCount) throw new ApiError(404, 'Không tìm thấy bản ghi.');
    }
  }
  // DELETE: xóa một bản ghi theo mã; tầng Library kiểm tra tham chiếu trước khi gọi hàm này.
  async remove(collection, key, value) {
    await this.db.collection(collection).deleteOne({ [key]: value }, this.options);
  }
  // TRANSACTION: các lệnh trong action cùng thành công hoặc cùng bị hủy khi có lỗi.
  // Dùng cho mượn/trả để cập nhật tồn kho và phiếu mượn nhất quán; driver hỗ trợ retry khi phù hợp.
  async atomic(action) {
    const session = this.client.startSession();
    try {
      return await session.withTransaction(
        () => action(new MongoStore(this.client, this.db, session)),
        // Đọc ảnh chụp nhất quán, ghi được đa số thành viên xác nhận và truy cập máy chủ primary.
        { readConcern: { level: 'snapshot' }, writeConcern: { w: 'majority' }, readPreference: 'primary' },
      );
    } finally { await session.endSession(); }
  }
}
