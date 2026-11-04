import { ApiError } from '../../server/src/store.js';
import { definitions, listQuery } from './queries.js';

const columns = {
  books: { bookCode: 'BookCode', title: 'Title', category: 'Category', publisherId: 'PublisherId', publishedYear: 'PublishedYear', totalCopies: 'TotalCopies', availableCopies: 'AvailableCopies', status: 'Status' },
  readers: { readerId: 'ReaderId', fullName: 'FullName', email: 'Email', phone: 'Phone', address: 'Address', registeredAt: 'RegisteredAt', status: 'Status' },
  staff: { staffId: 'StaffId', fullName: 'FullName', email: 'Email', role: 'Role', status: 'Status' },
  loans: { loanCode: 'LoanCode', readerId: 'ReaderId', staffId: 'StaffId', borrowDate: 'BorrowDate', dueDate: 'DueDate', status: 'Status' },
};
const numeric = new Set(['publisherId', 'year', 'publishedYear', 'totalCopies', 'availableCopies', 'quantity', 'returnedQuantity', 'authorOrder']);
const dates = new Set(['registeredAt', 'borrowDate', 'dueDate']);

// SQL Server lưu quan hệ thành nhiều bảng; adapter trả lại JSON giống backend MongoDB.
export class SqlStore {
  constructor(sql, pool, transaction) { Object.assign(this, { sql, pool, transaction }); }
  async execute(text, values = {}) {
    const request = new this.sql.Request(this.transaction || this.pool);
    for (const [name, value] of Object.entries(values)) {
      const type = numeric.has(name) ? this.sql.Int : dates.has(name) ? this.sql.DateTime2(3)
        : ['bookCode', 'readerId', 'staffId', 'loanCode', 'code', 'status'].includes(name) ? this.sql.VarChar(80) : this.sql.NVarChar(500);
      request.input(name, type, dates.has(name) && value != null ? new Date(value) : value);
    }
    try { return await request.query(text); }
    catch (error) {
      const number = error.number ?? error.originalError?.info?.number;
      if ([2601, 2627].includes(number)) throw new ApiError(409, 'Mã đã tồn tại.');
      if (number === 547) throw new ApiError(409, 'Dữ liệu vi phạm ràng buộc hoặc đang được tham chiếu.');
      if (number === 1205) throw new ApiError(409, 'Dữ liệu vừa thay đổi đồng thời. Hãy tải lại và thử lại.');
      throw error;
    }
  }
  decode(collection, row) {
    if (collection === 'books') {
      const { publisherName, publisherYear, ...book } = row;
      return { ...book, publisher: { name: publisherName, year: publisherYear } };
    }
    return row;
  }
  // SELECT + WHERE + ORDER BY riêng cho SQL, tất cả giá trị đều truyền qua request.input().
  async query(collection, query) {
    const spec = definitions[collection];
    if (!spec) throw new ApiError(404, 'Danh mục không hợp lệ.');
    let select = spec.select;
    // Khi sửa/mượn/trả: khóa cập nhật và giữ khóa đến cuối transaction để bảo vệ tồn kho.
    if (this.transaction) select = select.replace(`dbo.${spec.table} ${spec.alias}`, `dbo.${spec.table} ${spec.alias} WITH (UPDLOCK, HOLDLOCK)`);
    const result = await this.execute(select + query.where + (query.orderBy ? ' ORDER BY ' + query.orderBy : ''), query.values);
    const rows = result.recordset;
    // SQL Server 2014 chưa có FOR JSON: đọc bảng con theo nhóm, ghép mảng tại backend.
    // Mỗi nhóm tối đa 500 mã để tránh vượt giới hạn tham số của SQL Server.
    if (['books', 'loans'].includes(collection)) {
      const grouped = new Map(rows.map(row => [row[spec.key], []]));
      for (let start = 0; start < rows.length; start += 500) {
        const batch = rows.slice(start, start + 500);
        const values = Object.fromEntries(batch.map((row, index) => ['code' + index, row[spec.key]]));
        const codes = Object.keys(values).map(name => '@' + name).join(',');
        const text = collection === 'books'
          ? `SELECT BookCode AS parent, AuthorName AS name FROM dbo.BookAuthors WHERE BookCode IN (${codes}) ORDER BY BookCode,AuthorOrder`
          : `SELECT LoanCode AS parent, BookCode AS bookCode, TitleAtBorrow AS title, Quantity AS quantity, ReturnedQuantity AS returnedQuantity FROM dbo.LoanItems WHERE LoanCode IN (${codes}) ORDER BY LoanCode,BookCode`;
        for (const { parent, ...item } of (await this.execute(text, values)).recordset) {
          grouped.get(parent).push(collection === 'books' ? item.name : item);
        }
      }
      for (const row of rows) row[collection === 'books' ? 'authors' : 'items'] = grouped.get(row[spec.key]);
    }
    return rows.map(row => this.decode(collection, row));
  }
  async all(collection) { return this.query(collection, listQuery(collection, new URLSearchParams())); }
  // Chi tiết theo mã; khi kiểm tra tham chiếu sách dùng EXISTS trên bảng LoanItems.
  async findOne(collection, filter) {
    const spec = definitions[collection];
    const entries = Object.entries(filter);
    if (!spec || entries.length !== 1) throw new ApiError(400, 'Điều kiện tìm không hợp lệ.');
    const [field, code] = entries[0];
    let condition;
    if (field === spec.key) condition = `${spec.alias}.${spec.column}=@code`;
    else if (collection === 'loans' && ['readerId', 'staffId'].includes(field)) condition = `l.${columns.loans[field]}=@code`;
    else if (collection === 'loans' && field === 'items.bookCode') condition = 'EXISTS (SELECT 1 FROM dbo.LoanItems i WHERE i.LoanCode=l.LoanCode AND i.BookCode=@code)';
    else throw new ApiError(400, 'Trường tìm không hợp lệ.');
    return (await this.query(collection, { where: ' WHERE ' + condition, values: { code } }))[0] ?? null;
  }
  // SELECT DISTINCT thay cho distinct('category') của MongoDB.
  async categories() {
    return (await this.execute('SELECT DISTINCT Category AS category FROM dbo.Books ORDER BY Category')).recordset.map(row => row.category);
  }
  // GROUP BY/COUNT/SUM thay cho Aggregation Pipeline thống kê trên MongoDB.
  async categoryStats() {
    return (await this.execute('SELECT Category AS category, COUNT(*) AS titles, SUM(TotalCopies) AS copies FROM dbo.Books GROUP BY Category ORDER BY titles DESC')).recordset;
  }
  // INSERT/UPDATE theo mã nghiệp vụ; tác giả, nhà xuất bản và chi tiết phiếu lưu bảng riêng.
  async put(collection, key, doc, { create = false } = {}) {
    if (!this.transaction) return this.atomic(tx => tx.put(collection, key, doc, { create }));
    const spec = definitions[collection];
    if (!spec || key !== spec.key) throw new ApiError(400, 'Mã nghiệp vụ không hợp lệ.');
    const payload = { ...doc };
    if (collection === 'books') {
      const values = { name: doc.publisher.name, year: doc.publisher.year };
      // Tái sử dụng đúng cặp tên/năm của document publisher.
      const publishers = await this.execute('SELECT TOP (1) PublisherId AS id FROM dbo.Publishers WITH (UPDLOCK, HOLDLOCK) WHERE Name=@name AND [Year]=@year ORDER BY PublisherId', values);
      payload.publisherId = publishers.recordset[0]?.id;
      if (payload.publisherId == null) payload.publisherId = (await this.execute('INSERT dbo.Publishers(Name,[Year]) OUTPUT INSERTED.PublisherId AS id VALUES (@name,@year)', values)).recordset[0].id;
    }
    const mapping = columns[collection];
    const values = Object.fromEntries(Object.keys(mapping).map(field => [field, payload[field]]));
    if (create) {
      await this.execute(`INSERT dbo.${spec.table} (${Object.values(mapping).join(',')}) VALUES (${Object.keys(mapping).map(field => '@' + field).join(',')})`, values);
    } else {
      const fields = Object.keys(mapping).filter(field => field !== key);
      const result = await this.execute(`UPDATE dbo.${spec.table} SET ${fields.map(field => `${mapping[field]}=@${field}`).join(',')} WHERE ${spec.column}=@${key}`, values);
      if (!result.rowsAffected[0]) throw new ApiError(404, 'Không tìm thấy bản ghi.');
    }
    if (collection === 'books') {
      await this.execute('DELETE FROM dbo.BookAuthors WHERE BookCode=@bookCode', { bookCode: doc.bookCode });
      for (let index = 0; index < doc.authors.length; index++) await this.execute('INSERT dbo.BookAuthors(BookCode,AuthorOrder,AuthorName) VALUES (@bookCode,@authorOrder,@authorName)', { bookCode: doc.bookCode, authorOrder: index + 1, authorName: doc.authors[index] });
    }
    if (collection === 'loans') {
      for (const item of doc.items) {
        const values = { loanCode: doc.loanCode, bookCode: item.bookCode, title: item.title, quantity: item.quantity, returnedQuantity: item.returnedQuantity };
        if (create) await this.execute('INSERT dbo.LoanItems(LoanCode,BookCode,TitleAtBorrow,Quantity,ReturnedQuantity) VALUES (@loanCode,@bookCode,@title,@quantity,@returnedQuantity)', values);
        else await this.execute('UPDATE dbo.LoanItems SET ReturnedQuantity=@returnedQuantity WHERE LoanCode=@loanCode AND BookCode=@bookCode', { loanCode: doc.loanCode, bookCode: item.bookCode, returnedQuantity: item.returnedQuantity });
      }
    }
  }
  // DELETE sau khi tầng nghiệp vụ xác nhận không có phiếu mượn tham chiếu.
  async remove(collection, key, value) {
    if (!this.transaction) return this.atomic(tx => tx.remove(collection, key, value));
    const spec = definitions[collection];
    if (!spec || key !== spec.key || collection === 'loans') throw new ApiError(405, 'Không hỗ trợ xóa dữ liệu này.');
    if (collection === 'books') await this.execute('DELETE FROM dbo.BookAuthors WHERE BookCode=@code', { code: value });
    await this.execute(`DELETE FROM dbo.${spec.table} WHERE ${spec.column}=@code`, { code: value });
  }
  // BEGIN TRANSACTION/COMMIT/ROLLBACK: bảo đảm cập nhật sách và phiếu luôn nhất quán.
  async atomic(action) {
    if (this.transaction) return action(this);
    const transaction = new this.sql.Transaction(this.pool);
    let rolledBack = false;
    transaction.on('rollback', () => { rolledBack = true; });
    await transaction.begin(this.sql.ISOLATION_LEVEL.SERIALIZABLE);
    try {
      const result = await action(new SqlStore(this.sql, this.pool, transaction));
      await transaction.commit();
      return result;
    } catch (error) {
      if (!rolledBack) { try { await transaction.rollback(); } catch {} }
      throw error;
    }
  }
}
