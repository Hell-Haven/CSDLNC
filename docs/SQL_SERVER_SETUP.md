# Tạo SQL Server tương ứng MongoDB của dự án

Backend `server` dùng MongoDB Atlas; backend `server-sql` dùng SQL Server.
Các script dưới đây tạo database SQL Server độc lập để chạy backend SQL.
Xem `docs/TWO_BACKENDS.md` để chọn backend khi chạy Flutter; dữ liệu không tự đồng bộ.

## Chạy bằng SQL Server Management Studio (SSMS)

1. Mở SSMS, chọn Database Engine, nhập server instance. Máy này có instance
   SQLEXPRESS: thử `localhost\SQLEXPRESS`, chọn Windows Authentication.
   Nếu không kết nối được, kiểm tra dịch vụ `SQL Server (SQLEXPRESS)` đang chạy.
2. Mở `sqlserver/01_create_library_db.sql`, nhấn Execute (F5).
   Script tạo database `LibrarySqlDemo` và bảy bảng, không xóa database cũ.
   Chỉ chạy tạo bảng một lần; nếu đã có bảng thì script báo lỗi và rollback.
3. Mở `sqlserver/02_seed_library_db.sql`, nhấn F5 để thêm dữ liệu mẫu tương ứng
   `server/data/seed.json`: 8 sách, 72 bản, 2 độc giả, 1 nhân viên, chưa có phiếu mượn.
   Đây không phải dữ liệu hiện tại trên Atlas và không phải công cụ đồng bộ.
4. Trong Object Explorer, nhấn Refresh ở Databases, mở LibrarySqlDemo → Tables.
5. Mở `sqlserver/03_query_examples.sql`, chọn câu lệnh cần chạy và nhấn F5.

## Ánh xạ dữ liệu

| MongoDB | SQL Server |
|---|---|
| books | Books |
| books.publisher | Publishers, liên kết qua Books.PublisherId |
| books.authors[] | BookAuthors, mỗi phần tử một dòng; giữ thứ tự bằng AuthorOrder |
| readers | Readers |
| staff | Staff |
| loans | Loans |
| loans.items[] | LoanItems, liên kết LoanCode và BookCode |

Publishers giữ cặp name/year từ document nhúng, không suy diễn year là năm thành lập NXB.
Category vẫn là cột trên Books; có thể tách thành bảng Categories nếu cần quản lý riêng.
TitleAtBorrow giữ tên sách tại thời điểm mượn như items.title của MongoDB.

PRIMARY KEY ngăn trùng mã; FOREIGN KEY giữ quan hệ; CHECK chặn số bản âm,
số còn lớn hơn tổng và số trả lớn hơn số mượn. Dùng nvarchar để lưu tiếng Việt,
datetime2 theo quy ước UTC. Ràng buộc SQL chưa đủ thay thế nghiệp vụ: cần transaction
để mượn/trả sách và kiểm tra ACTIVE, tồn kho, trạng thái phiếu nhất quán.

## Dùng cả SQL Server và MongoDB

- **Chuyển đổi backend cho demo:** chạy `server` hoặc `server-sql`, sau đó chạy Flutter
  với API_URL trỏ đến cổng 8080 hoặc 8081. Hai database không tự đồng bộ.
- **Hai hệ cùng phục vụ ứng dụng:** chọn một nguồn dữ liệu chính, ví dụ SQL Server giữ
  mượn/trả và tồn kho; MongoDB giữ bản sao phục vụ đọc/tìm kiếm. Phải thiết kế đồng bộ,
  chấp nhận độ trễ và tránh sửa cùng dữ liệu từ hai phía.
- **Không ghi hai database bằng hai lệnh nối tiếp rồi coi như một transaction:**
  SQL có thể thành công nhưng MongoDB lỗi. Có thể dùng outbox trong database chính
  và worker đồng bộ có retry, kiểm soát phiên bản và xử lý sự kiện lặp.

Backend SQL đã có SqlStore: JOIN các bảng rồi trả lại đúng JSON có authors,
publisher, items mà Flutter đang dùng.

## Tài liệu

- https://learn.microsoft.com/en-us/ssms/quickstarts/ssms-connect-query-sql-server
- https://learn.microsoft.com/en-us/sql/relational-databases/tables/create-foreign-key-relationships
- https://www.mongodb.com/docs/manual/data-modeling/

Đã chạy setup trên SQL Server 2014 SQLEXPRESS local và kiểm thử tích hợp CRUD,
mượn/trả, API, rollback qua backend SQL. Dữ liệu thử được rollback sau kiểm thử.
Script verify_sqlserver.ps1 cũ dùng bộ file và stored procedure khác, không dùng để kiểm tra bộ này.
