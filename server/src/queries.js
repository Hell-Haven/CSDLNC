import { ApiError } from './store.js';

// Quy định các trường được tìm kiếm, sắp xếp và trường sắp xếp mặc định của từng collection.
// Dấu chấm truy cập trường nhúng: publisher.name, items.title, items.bookCode.
const fields = {
  books: { search: ['bookCode', 'title', 'authors', 'publisher.name'], sort: ['bookCode', 'title', 'category', 'publishedYear', 'totalCopies', 'availableCopies'], default: 'title' },
  readers: { search: ['readerId', 'fullName', 'email', 'phone', 'address'], sort: ['readerId', 'fullName', 'email', 'registeredAt'], default: 'fullName' },
  staff: { search: ['staffId', 'fullName', 'email', 'role'], sort: ['staffId', 'fullName', 'email', 'role'], default: 'fullName' },
  loans: { search: ['loanCode', 'readerId', 'staffId', 'items.title', 'items.bookCode'], sort: ['loanCode', 'borrowDate', 'dueDate', 'status', 'readerId'], default: 'borrowDate' },
};
// Chuyển ký tự đặc biệt thành văn bản thường để từ khóa không trở thành biểu thức regex tùy ý.
const escapeRegex = value => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Chuyển tham số URL thành điều kiện lọc và sắp xếp cho MongoStore.query().
 * Ví dụ: /books?q=mongo&category=Công nghệ thông tin&sort=publishedYear&order=desc.
 * Hàm chỉ tạo đối tượng truy vấn; store.js mới gửi truy vấn đến MongoDB.
 */
export function listQuery(collection, params) {
  const spec = fields[collection];
  // Chỉ nhận tham số đã định nghĩa, từ chối tham số lặp và tham số toán tử do client tự chèn.
  const allowed = new Set(['q', 'status', 'sort', 'order', ...(collection === 'books' ? ['category', 'available'] : []),
    ...(collection === 'loans' ? ['readerId', 'staffId', 'overdue'] : [])]);
  for (const key of params.keys()) {
    if (!allowed.has(key) || params.getAll(key).length !== 1) throw new ApiError(400, `Tham số ${key} không hợp lệ.`);
  }
  // Đọc, bỏ khoảng trắng hai đầu và giới hạn độ dài giá trị tham số.
  const read = (key, max = 500) => {
    const value = (params.get(key) ?? '').trim();
    if (value.length > max) throw new ApiError(400, `${key} tối đa ${max} ký tự.`);
    return value;
  };
  const filter = {};
  const q = read('q', 200);
  // $or: khớp ít nhất một trường. $regex: tìm chuỗi con; $options: 'i': không phân biệt hoa/thường.
  // Truy vấn vào authors cũng khớp khi một phần tử trong mảng tác giả chứa từ khóa.
  if (q) filter.$or = spec.search.map(field => ({ [field]: { $regex: escapeRegex(q), $options: 'i' } }));
  // Lọc theo trạng thái hợp lệ của từng collection bằng phép so sánh bằng.
  const status = read('status');
  if (status) {
    const states = collection === 'loans' ? ['BORROWING', 'RETURNED'] : ['ACTIVE', 'INACTIVE'];
    if (!states.includes(status)) throw new ApiError(400, 'Trạng thái không hợp lệ.');
    filter.status = status;
  }
  // Các trường trong filter được kết hợp đồng thời: từ khóa, thể loại và trạng thái đều phải khớp.
  if (collection === 'books' && read('category')) filter.category = read('category');
  for (const key of ['available', 'overdue']) {
    if (!params.has(key)) continue;
    if (!['true', 'false'].includes(params.get(key))) throw new ApiError(400, `${key} phải là true hoặc false.`);
    // $gt: số bản còn lớn hơn 0; available=false chọn sách có số bản còn bằng 0.
    if (key === 'available') filter.availableCopies = params.get(key) === 'true' ? { $gt: 0 } : 0;
    if (key === 'overdue' && params.get(key) === 'true') {
      // $and: phải đang mượn VÀ hạn trả nhỏ hơn hiện tại ($lt) mới được coi là quá hạn.
      // Giữ điều kiện status bên ngoài để status=RETURNED kết hợp overdue=true không trả kết quả.
      filter.$and = [{ status: 'BORROWING' }, { dueDate: { $lt: new Date() } }];
    }
  }
  // Giới hạn phiếu mượn theo đúng mã độc giả hoặc nhân viên phụ trách.
  if (collection === 'loans') {
    for (const key of ['readerId', 'staffId']) if (read(key)) filter[key] = read(key);
  }
  // Chỉ cho phép sắp xếp theo trường đã khai báo; MongoDB dùng 1 tăng dần, -1 giảm dần.
  const sort = read('sort') || spec.default;
  if (!spec.sort.includes(sort)) throw new ApiError(400, 'Trường sắp xếp không hợp lệ.');
  const order = read('order') || (collection === 'loans' ? 'desc' : 'asc');
  if (!['asc', 'desc'].includes(order)) throw new ApiError(400, 'order phải là asc hoặc desc.');
  const key = { books: 'bookCode', readers: 'readerId', staff: 'staffId', loans: 'loanCode' }[collection];
  // Khi hai bản ghi bằng nhau ở trường chính, sắp tiếp theo mã để thứ tự ổn định.
  return { filter, sort: { [sort]: order === 'asc' ? 1 : -1, ...(sort !== key ? { [key]: 1 } : {}) } };
}
