# Chọn MongoDB hoặc SQL Server

Dự án có hai backend Node.js độc lập về tiến trình và cấu hình kết nối:

| Backend | Thư mục | Cổng mặc định | Database |
|---|---|---|---|
| MongoDB | server | 8080 | library_db trên Atlas |
| SQL Server | server-sql | 8081 | LibrarySqlDemo trên SQLEXPRESS |

Hai backend dùng chung định dạng REST API và nghiệp vụ mượn/trả trong
`server/src/library.js`, router trong `server/src/http.js`. Phần SQL không thực thi
truy vấn MongoDB. Câu truy vấn và driver được tách riêng:

- MongoDB: `server/src/queries.js`, `server/src/store.js` — find, insertOne, updateOne, deleteOne, aggregate.
- SQL Server: `server-sql/src/queries.js`, `server-sql/src/store.js` — SELECT, JOIN, LIKE, ORDER BY, INSERT, UPDATE, DELETE, GROUP BY.
- SQL Server chuyển dữ liệu quan hệ thành JSON có authors, publisher và items giống MongoDB để Flutter dùng cùng giao diện.

## Chuẩn bị SQL Server một lần

Máy này có SQL Server instance `localhost\SQLEXPRESS` và ODBC Driver 17.
Backend tương thích SQL Server 2014; không yêu cầu tính năng FOR JSON của phiên bản mới hơn.
Trong PowerShell:

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC\server-sql
npm install
# Chỉ copy khi chưa có .env để tránh ghi đè cấu hình đã sửa.
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
npm run setup
```

Mặc định dùng Windows Authentication theo tài khoản chạy Node.js, không cần
tạo SQL_USER/SQL_PASSWORD. Tài khoản phải có quyền tạo database/bảng khi setup
và quyền đọc/ghi khi chạy ứng dụng. `npm run setup` tạo database, bảy bảng và thêm
seed từ `server/data/seed.json` (8 sách, 72 bản, 2 độc giả, 1 nhân viên).
Chạy lại setup giữ bảng hiện có và chỉ thêm mã mẫu còn thiếu.

Nếu muốn làm bằng SSMS, chạy theo thứ tự:
`sqlserver/01_create_library_db.sql`, `02_seed_library_db.sql`, `03_query_examples.sql`.
Xem thêm `docs/SQL_SERVER_SETUP.md` để hiểu khóa chính/ngoại và cách tách bảng.

Nếu dùng SQL Server Authentication, sửa `server-sql/.env`: SQL_AUTH=sql,
SQL_USER, SQL_PASSWORD; server phải bật chế độ đăng nhập tương ứng.
SQL_ENCRYPT và SQL_TRUST_SERVER_CERTIFICATE là cấu hình kết nối local;
khi dùng server từ xa, cấu hình TLS theo chứng chỉ của server đó.

## Chạy với MongoDB

Terminal 1:

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC
.\scripts\run_backend.ps1 -Database mongodb
```

Terminal 2:

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC
.\scripts\run_frontend.ps1 -Database mongodb
```

## Chạy với SQL Server

Terminal 1:

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC
.\scripts\run_backend.ps1 -Database sqlserver
```

Terminal 2:

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC
.\scripts\run_frontend.ps1 -Database sqlserver
```

Giao diện hiển thị MongoDB Atlas hoặc SQL Server theo backend được kết nối.
Nếu cổng web 5173 đang dùng, thêm `-WebPort 5174` vào lệnh chạy frontend.
Đổi backend cần dừng Flutter bằng Ctrl+C rồi chạy lại để đổi API_URL lúc biên dịch.

Nếu không muốn dùng script: `cd server` hoặc `cd server-sql`, chạy `npm start`.
Flutter dùng `--dart-define=API_URL=http://localhost:8080` cho MongoDB,
hoặc `--dart-define=API_URL=http://localhost:8081` cho SQL Server.
Script chọn cổng mặc định; nếu đổi PORT trong .env thì phải đổi API_URL tương ứng.
Nếu bật API_KEY, chạy Flutter trực tiếp và truyền thêm `--dart-define=API_KEY=...`.

Hai backend có thể cùng chạy vì dùng cổng khác nhau. Mỗi phiên Flutter chọn một API.
Hai database lưu dữ liệu độc lập; thêm sách bên SQL không tự xuất hiện bên MongoDB.

## Kiểm tra

- MongoDB: GET http://localhost:8080/health → mode=atlas.
- SQL Server: GET http://localhost:8081/health → mode=sqlserver.
- Trong server: `npm test`.
- Trong server-sql: `npm test`; kiểm thử tích hợp thật dùng biến
  `SQL_INTEGRATION_TEST=true` và `npm run test:integration`.
  Kiểm thử tích hợp dùng transaction rollback, không giữ dữ liệu thử.

```powershell
# Chạy trong server-sql để kiểm tra với SQL Server thật:
$env:SQL_INTEGRATION_TEST='true'
npm run test:integration
Remove-Item Env:SQL_INTEGRATION_TEST
```

Tài liệu driver: https://github.com/tediousjs/node-mssql
