import { ApiError } from "../../server/src/store.js";

// Câu SELECT T-SQL riêng: JOIN thay document nhúng; store.js ghép các bảng con thành mảng JSON.
export const definitions = {
  books: {
    table: "Books",
    key: "bookCode",
    column: "BookCode",
    alias: "b",
    select: `SELECT b.BookCode AS bookCode, b.Title AS title, b.Category AS category,
      p.Name AS publisherName, p.[Year] AS publisherYear, b.PublishedYear AS publishedYear,
      b.TotalCopies AS totalCopies, b.AvailableCopies AS availableCopies, b.Status AS status
      FROM dbo.Books b JOIN dbo.Publishers p ON p.PublisherId=b.PublisherId`,
    sort: {
      bookCode: "b.BookCode",
      title: "b.Title",
      category: "b.Category",
      publishedYear: "b.PublishedYear",
      totalCopies: "b.TotalCopies",
      availableCopies: "b.AvailableCopies",
    },
    search: ["b.BookCode", "b.Title", "p.Name"],
    default: "title",
  },
  readers: {
    table: "Readers",
    key: "readerId",
    column: "ReaderId",
    alias: "r",
    select: `SELECT r.ReaderId AS readerId, r.FullName AS fullName, r.Email AS email,
      r.Phone AS phone, r.Address AS address, r.RegisteredAt AS registeredAt, r.Status AS status FROM dbo.Readers r`,
    sort: {
      readerId: "r.ReaderId",
      fullName: "r.FullName",
      email: "r.Email",
      registeredAt: "r.RegisteredAt",
    },
    search: ["r.ReaderId", "r.FullName", "r.Email", "r.Phone", "r.Address"],
    default: "fullName",
  },
  staff: {
    table: "Staff",
    key: "staffId",
    column: "StaffId",
    alias: "s",
    select: `SELECT s.StaffId AS staffId, s.FullName AS fullName, s.Email AS email,
      s.Role AS role, s.Status AS status FROM dbo.Staff s`,
    sort: {
      staffId: "s.StaffId",
      fullName: "s.FullName",
      email: "s.Email",
      role: "s.Role",
    },
    search: ["s.StaffId", "s.FullName", "s.Email", "s.Role"],
    default: "fullName",
  },
  loans: {
    table: "Loans",
    key: "loanCode",
    column: "LoanCode",
    alias: "l",
    select: `SELECT l.LoanCode AS loanCode, l.ReaderId AS readerId, l.StaffId AS staffId,
      l.BorrowDate AS borrowDate, l.DueDate AS dueDate, l.Status AS status FROM dbo.Loans l`,
    sort: {
      loanCode: "l.LoanCode",
      borrowDate: "l.BorrowDate",
      dueDate: "l.DueDate",
      status: "l.Status",
      readerId: "l.ReaderId",
    },
    search: ["l.LoanCode", "l.ReaderId", "l.StaffId"],
    default: "borrowDate",
  },
};

// Tham số hóa giá trị (@q, @category...), không nối trực tiếp đầu vào vào SQL.
// ESCAPE bảo đảm các ký tự %, _, [ được tìm như văn bản thường.
const likeLiteral = (value) => value.replace(/[~%_\[]/g, "~$&");
export function listQuery(collection, params) {
  const spec = definitions[collection];
  if (!spec) throw new ApiError(404, "Danh mục không hợp lệ.");
  const allowed = [
    "q",
    "status",
    "sort",
    "order",
    ...(collection === "books" ? ["category", "available"] : []),
    ...(collection === "loans" ? ["readerId", "staffId", "overdue"] : []),
  ];
  for (const key of params.keys())
    if (!allowed.includes(key) || params.getAll(key).length !== 1)
      throw new ApiError(400, `Tham số ${key} không hợp lệ.`);
  const read = (key, max = 500) => {
    const value = (params.get(key) || "").trim();
    if (value.length > max)
      throw new ApiError(400, `${key} tối đa ${max} ký tự.`);
    return value;
  };
  const where = [],
    values = {};
  const q = read("q", 200);
  if (q) {
    values.q = "%" + likeLiteral(q) + "%";
    const search = spec.search.map(
      (field) => `${field} COLLATE Vietnamese_100_CI_AS LIKE @q ESCAPE N'~'`,
    );
    if (collection === "books")
      search.push(
        `EXISTS (SELECT 1 FROM dbo.BookAuthors a WHERE a.BookCode=b.BookCode AND a.AuthorName COLLATE Vietnamese_100_CI_AS LIKE @q ESCAPE N'~')`,
      );
    if (collection === "loans")
      search.push(
        `EXISTS (SELECT 1 FROM dbo.LoanItems i WHERE i.LoanCode=l.LoanCode AND (i.TitleAtBorrow COLLATE Vietnamese_100_CI_AS LIKE @q ESCAPE N'~' OR i.BookCode COLLATE Vietnamese_100_CI_AS LIKE @q ESCAPE N'~'))`,
      );
    where.push("(" + search.join(" OR ") + ")");
  }
  const status = read("status");
  if (status) {
    if (
      !(
        collection === "loans"
          ? ["BORROWING", "RETURNED"]
          : ["ACTIVE", "INACTIVE"]
      ).includes(status)
    )
      throw new ApiError(400, "Trạng thái không hợp lệ.");
    values.status = status;
    where.push(spec.alias + ".Status=@status");
  }
  if (collection === "books" && read("category")) {
    values.category = read("category");
    where.push("b.Category=@category");
  }
  if (collection === "books" && params.has("available")) {
    if (!["true", "false"].includes(params.get("available")))
      throw new ApiError(400, "available phải là true hoặc false.");
    where.push(
      params.get("available") === "true"
        ? "b.AvailableCopies>0"
        : "b.AvailableCopies=0",
    );
  }
  if (collection === "loans") {
    for (const [key, column] of [
      ["readerId", "ReaderId"],
      ["staffId", "StaffId"],
    ]) {
      if (read(key)) {
        values[key] = read(key);
        where.push(`l.${column}=@${key}`);
      }
    }
    if (params.has("overdue")) {
      if (!["true", "false"].includes(params.get("overdue")))
        throw new ApiError(400, "overdue phải là true hoặc false.");
      if (params.get("overdue") === "true")
        where.push("l.Status='BORROWING' AND l.DueDate<SYSUTCDATETIME()");
    }
  }
  const sort = read("sort") || spec.default;
  const order = read("order") || (collection === "loans" ? "desc" : "asc");
  if (!Object.hasOwn(spec.sort, sort) || !["asc", "desc"].includes(order))
    throw new ApiError(400, "Sắp xếp không hợp lệ.");
  const numeric = [
    "publishedYear",
    "totalCopies",
    "availableCopies",
    "registeredAt",
    "borrowDate",
    "dueDate",
  ].includes(sort);
  const orderBy =
    spec.sort[sort] +
    (numeric ? "" : " COLLATE Vietnamese_100_CI_AS") +
    " " +
    order.toUpperCase() +
    (sort !== spec.key ? `, ${spec.alias}.${spec.column} ASC` : "");
  return {
    where: where.length ? " WHERE " + where.join(" AND ") : "",
    values,
    orderBy,
  };
}
