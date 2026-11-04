# Mộc Thư viện số

Ứng dụng quản lý thư viện xây dựng theo mô hình trong báo cáo MongoDB: bốn collection `books`, `readers`, `staff`, `loans`; `authors` là mảng, `publisher` là document nhúng, `loans.items` chứa tên sách tại thời điểm mượn. Giao diện dùng Flutter/Dart, backend dùng Node.js (JavaScript) và MongoDB driver chính thức. Tên sách, tác giả, thông tin liên hệ trong seed là dữ liệu minh họa để thực hành. Bản demo không cần đăng ký hay đăng nhập.

## Chọn backend MongoDB hoặc SQL Server

Dự án có hai backend Node.js: `server` dùng MongoDB Atlas tại cổng 8080,
`server-sql` dùng SQL Server tại cổng 8081. Cùng giao diện Flutter và REST API,
nhưng câu truy vấn và dữ liệu hai bên độc lập.
Xem [hướng dẫn chạy hai backend](docs/TWO_BACKENDS.md).

## Chức năng

- **Trang chủ:** số đầu sách, bản đang mượn, độc giả, phiếu quá hạn và thống kê thể loại. Khi dùng Atlas, thống kê thể loại lấy từ Aggregation Pipeline.
- **Sách:** danh sách, tìm tên/tác giả/mã/nhà xuất bản, lọc thể loại, sắp xếp tên/năm xuất bản/số bản còn/mã, xem chi tiết, thêm, sửa, xóa, mượn sách. Tìm kiếm, lọc và sắp xếp chạy trên MongoDB qua API.
- **Lịch sử:** lập phiếu nhiều sách, lọc phiếu đang mượn/quá hạn/đã trả, trả từng phần hoặc toàn bộ.
- **Trang cá nhân:** chọn hồ sơ độc giả, xem thông tin và số bản chưa trả, chỉnh sửa hồ sơ; CRUD độc giả và nhân viên.
- Bố cục có sidebar trên máy tính, thanh điều hướng dưới trên điện thoại. Bìa sách là minh họa vẽ trong Flutter, không tải ảnh từ Internet.

## Cấu trúc

```text
library_app/              Flutter Android, Windows và Web
  lib/src/app.dart        Bốn màn hình và điều hướng
  lib/src/forms.dart      Biểu mẫu CRUD, mượn và trả
  lib/src/api.dart        HTTP client, API_URL, API_KEY
server/                   HTTP API bằng Node.js
  src/server.js           Khởi động, kết nối Atlas, seed, đọc .env
  src/http.js             REST API, CORS, JSON, phục vụ Flutter Web
  src/library.js          Validation và nghiệp vụ
  src/store.js            MongoDB transactions và bộ nhớ demo
  src/config.js           Cấu hình local
  data/seed.json          8 đầu sách, 72 bản, 2 độc giả, 1 nhân viên
sqlserver/                Schema, seed và truy vấn so sánh
mongodb/                  Truy vấn MongoDB tương đương
previews/                 Ảnh giao diện do kiểm thử tạo
docs/SQL_SERVER.md        Hướng dẫn SQL Server từng bước
```

## 1 Chạy thử ngay chưa cần Atlas

Cần Node.js từ 20.20.0 trở lên và Flutter stable có Dart SDK từ 3.13.2 trở lên. Chạy các lệnh sau trong **hai cửa sổ PowerShell**.

**Cửa sổ 1: API có dữ liệu mẫu**

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC\server
npm install
npm run demo
```

**Cửa sổ 2: Flutter**

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC\library_app
flutter pub get
flutter run -d chrome --web-port=5173 --dart-define=API_URL=http://localhost:8080
```

Mở địa chỉ Flutter hiển thị. Nếu không có Chrome, dùng `flutter run -d edge` hoặc `flutter run -d windows` nếu đã cài Visual Studio và công cụ Desktop development with C++.

Chế độ demo hiện nhãn **Dữ liệu mẫu**. CRUD và mượn/trả chạy qua API thật, nhưng lưu trong RAM; khởi động lại API sẽ khôi phục seed. Không tự chuyển sang dữ liệu mẫu nếu kết nối Atlas bị lỗi.

Để chạy bản web đã đóng gói cùng API trên một cổng:

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC\library_app
flutter build web --no-pub
cd ..\server
npm run demo -- --web
```

Mở `http://localhost:8080`. Dừng API cũ trước nếu cổng đang được sử dụng. Bỏ `--demo` khi đã đặt `MONGODB_URI` để dùng Atlas. Bản web dùng `API_URL` lúc build; mặc định `http://localhost:8080`, cần build lại khi đổi URL/API key.

## 2 Tạo và kết nối MongoDB Atlas

1. Đăng nhập [MongoDB Atlas](https://cloud.mongodb.com/), tạo Project và một cluster phù hợp với tài khoản, ví dụ `LibraryCluster`.
2. Trong **Database Access / Database Users**, tạo **Database User** có quyền `readWrite` trên database `library_db`. Đây là tài khoản cơ sở dữ liệu, khác tài khoản đăng nhập website Atlas.
3. Trong **Network Access / IP Access List**, thêm IP công cộng của máy chạy API bằng **Add Current IP Address**. Nếu IP mạng thay đổi, cập nhật danh sách này.
4. Chọn **Connect → Drivers**, lấy chuỗi `mongodb+srv://...`. Thay tài khoản, mật khẩu và hostname thật. Mã hóa URL các ký tự đặc biệt trong tài khoản/mật khẩu, ví dụ `@` thành `%40`.
5. Bảo đảm database trong URI là `/library_db` trước dấu `?`. Không đưa URI vào mã Flutter, Git hoặc ảnh chụp báo cáo.
6. Dừng API demo bằng `Ctrl+C`. Tạo file cấu hình local:

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC\server
Copy-Item .env.example .env
```

Mở `server/.env`, thay USER, PASSWORD và CLUSTER trong `MONGODB_URI` bằng thông tin Atlas thật rồi lưu. Server tự đọc file này; biến môi trường PowerShell được ưu tiên nếu đã đặt. File `.env` đã được loại khỏi Git. Sau đó chạy:

```powershell
npm run seed
```

`npm run seed` chỉ thêm các mã mẫu chưa tồn tại và không ghi đè sách/độc giả đang có. Sau lần đầu, chạy `npm start` không cần seed lại. API tự tạo unique index cho bốn mã nghiệp vụ và index phiếu theo độc giả, trạng thái/hạn trả. Nếu dữ liệu cũ có mã trùng hoặc thiếu trường, cần chuẩn hóa trước khi chạy. Không cần tạo tài khoản đăng nhập ứng dụng; Database User của Atlas chỉ dùng để server kết nối database.

7. Làm mới giao diện. Khi kết nối thành công, sidebar hiển thị **MongoDB Atlas** và không còn nhãn dữ liệu mẫu. Kiểm tra `http://localhost:8080/health` để thấy `"mode":"atlas"`.
8. Trong Atlas Data Explorer, mở `library_db` → `books`, `readers`, `staff`, `loans` để đối chiếu các thay đổi từ giao diện. Các trường ngày được ghi bằng BSON Date, API trả chuỗi ISO 8601 UTC.

Tham khảo chính thức: [kết nối cluster và điều kiện Database User/IP Access List](https://www.mongodb.com/docs/atlas/connect-to-database-deployment/).

### Android emulator hoặc điện thoại thật

Android emulator truy cập máy Windows qua `10.0.2.2`, không dùng `localhost`. API cần lắng nghe mạng và có API key cho buổi thực hành:

```powershell
# Cửa sổ API
$env:HOST='0.0.0.0'
$env:API_KEY='THAY_BANG_CHUOI_NGAU_NHIEN_CUA_BAN'
npm run demo

# Cửa sổ Flutter, chọn thiết bị bằng flutter devices
flutter run --dart-define=API_URL=http://10.0.2.2:8080 --dart-define=API_KEY=THAY_BANG_CHUOI_NGAU_NHIEN_CUA_BAN
```

Điện thoại thật dùng IP LAN của máy Windows, ví dụ `http://192.168.1.10:8080`, cùng Wi-Fi và mở cổng 8080 cho mạng Private nếu firewall yêu cầu. HTTP cleartext chỉ bật trong manifest **debug**; bản phát hành dùng URL HTTPS. Flutter Web được phục vụ qua HTTPS cũng cần API HTTPS.

Khi có API key, mọi request cần header `X-API-Key`. Web từ domain riêng cần đặt `ALLOWED_ORIGIN` đúng origin, ví dụ `https://library.example.com`. API key dùng chung cho bài thực hành; **chưa có đăng nhập, phiên người dùng hoặc phân quyền theo vai trò**. Hồ sơ trên Trang cá nhân là hồ sơ độc giả được chọn, không phải tài khoản đã xác thực.

## 3 Quy tắc dữ liệu

- Mã duy nhất, không được đổi mã khi sửa; trường và kiểu dữ liệu được kiểm tra tại API.
- `0 <= availableCopies <= totalCopies`. Sách mới có số còn bằng tổng số bản. Khi sửa sách, hiệu `totalCopies - availableCopies` phải giữ nguyên; muốn thêm 2 bản vào kho thì tăng cả hai số lên 2.
- Phiếu tối đa 30 đầu sách khác nhau; số lượng mỗi dòng 1–1000. Độc giả, nhân viên và sách phải hoạt động.
- Mượn giảm tồn kho và tạo phiếu trong cùng transaction. Trả tăng số đã trả và tồn kho trong cùng transaction; khi trả hết mới chuyển `RETURNED`. Tên trong phiếu giữ nguyên nếu đổi tên sách sau đó.
- Không xóa cứng sách/độc giả/nhân viên đã có bất kỳ phiếu tham chiếu nào; sửa trạng thái thành **Ngừng hoạt động**. Không sửa/xóa phiếu đã phát sinh; dùng chức năng trả sách.
- Ngày lưu UTC, hiển thị theo giờ thiết bị. Quá hạn là phiếu chưa trả hết và `dueDate < hiện tại`.
- Backend dùng MongoDB Node.js driver chính thức, `session.withTransaction()`, đọc snapshot và ghi majority. Driver xử lý retry transaction khi phù hợp. Cần cluster hỗ trợ multi-document transactions, dùng Atlas replica set, không dùng MongoDB standalone. Nếu lỗi hoặc commit chưa xác nhận, tải lại dữ liệu trước khi lặp thao tác. Tham khảo [transaction trong Node.js driver](https://www.mongodb.com/docs/drivers/node/v6.x/crud/transactions/).

## 4 API

| Method | Đường dẫn | Chức năng |
|---|---|---|
| GET | `/health` | Trạng thái nguồn dữ liệu, ping Atlas |
| GET | `/snapshot` | Dữ liệu bốn collection và thống kê thể loại |
| GET | `/books`, `/readers`, `/staff`, `/loans` | Danh sách |
| GET | `/books/categories` | Danh sách thể loại bằng MongoDB `distinct` |
| GET | `/books/:bookCode`, `/readers/:readerId`, `/staff/:staffId`, `/loans/:loanCode` | Xem chi tiết bằng `findOne` |
| POST | `/books`, `/readers`, `/staff` | Thêm |
| PUT | `/books/:bookCode`, `/readers/:readerId`, `/staff/:staffId` | Sửa |
| DELETE | Các đường dẫn mã ở trên | Xóa bản ghi chưa được tham chiếu |
| POST | `/loans` | Mượn nhiều sách |
| POST | `/loans/:loanCode/return` | Trả một phần/toàn bộ |

Ví dụ body mượn, thay hạn trả bằng một thời điểm trong tương lai:

```json
{
  "readerId": "R001",
  "staffId": "S001",
  "dueDate": "2026-12-01T16:59:00Z",
  "items": [{"bookCode":"B001","quantity":2},{"bookCode":"B002","quantity":1}]
}
```

Body trả: `{"items":[{"bookCode":"B001","quantity":1}]}`. Quantity là **số trả thêm trong lần này**, không phải tổng số đã trả.

### Tìm kiếm, lọc và sắp xếp trên MongoDB

Ví dụ API (URL có khoảng trắng và dấu tiếng Việt cần được URL encode; Flutter tự xử lý):

```text
GET /books?q=mongo&sort=title&order=asc
GET /books?category=C%C3%B4ng%20ngh%E1%BB%87%20th%C3%B4ng%20tin&sort=publishedYear&order=desc
GET /books?available=true&status=ACTIVE&sort=availableCopies&order=desc
GET /readers?q=R001&sort=fullName&order=asc
GET /staff?q=S001&sort=staffId&order=asc
GET /loans?readerId=R001&status=BORROWING&sort=dueDate&order=asc
GET /loans?overdue=true&sort=dueDate&order=asc
```

Các API danh sách trả về mảng JSON. `q` tìm chuỗi con không phân biệt hoa/thường; ký tự regex được coi là văn bản thường. Từ khóa có dấu cần nhập đúng dấu. `category` lọc thể loại; `status` lọc trạng thái; `available=true/false` lọc sách còn/hết; `readerId`, `staffId`, `overdue=true` lọc phiếu mượn. `sort` chỉ nhận các trường cho phép, `order` là `asc` hoặc `desc`. Sắp xếp tên dùng collation tiếng Việt; mã nghiệp vụ là tiêu chí phụ khi giá trị bằng nhau.

| Collection | Trường `sort` được hỗ trợ |
|---|---|
| `books` | `bookCode`, `title`, `category`, `publishedYear`, `totalCopies`, `availableCopies` |
| `readers` | `readerId`, `fullName`, `email`, `registeredAt` |
| `staff` | `staffId`, `fullName`, `email`, `role` |
| `loans` | `loanCode`, `borrowDate`, `dueDate`, `status`, `readerId` |

Backend dùng các truy vấn `find`, `$or`, `$regex`, `sort`, `findOne`, `insertOne`, `updateOne` với `$set`, `deleteOne` và `distinct`. Xem [các câu truy vấn MongoDB mẫu](mongodb/queries.mongodb.js): truy vấn đọc có thể chạy trực tiếp; ví dụ ghi được chú thích để bạn chủ động chọn từng lệnh. Tên trường theo `server/data/seed.json`; bốn tên collection trong Atlas không đảm bảo dữ liệu có đúng các trường đó.

CRUD đầy đủ áp dụng cho sách, độc giả và nhân viên. Phiếu mượn được tạo qua mượn sách, cập nhật qua trả sách; không sửa/xóa trực tiếp phiếu đã phát sinh để giữ tồn kho và lịch sử nhất quán. Xóa sách/độc giả/nhân viên phải qua API để kiểm tra tham chiếu trong transaction.

Tham khảo: [MongoDB Node.js: truy vấn và sắp xếp](https://www.mongodb.com/docs/drivers/node/current/crud/query/retrieve/), [distinct](https://www.mongodb.com/docs/drivers/node/current/crud/query/distinct/).

## 5 SQL Server để so sánh

Đọc [hướng dẫn tạo SQL Server](docs/SQL_SERVER_SETUP.md) và [chọn backend](docs/TWO_BACKENDS.md). Backend `server-sql` dùng T-SQL riêng, hỗ trợ SQL Server 2014 trở lên. Chạy `npm run setup` trong `server-sql` hoặc chạy các script mới trong thư mục `sqlserver` bằng SSMS để tạo database và dữ liệu mẫu. Dữ liệu SQL và MongoDB được lưu độc lập.

## 6 Kiểm thử

```powershell
cd D:\CSDLNC\CSDLNC_demo\CSDLNC\server
npm run check
npm test

cd D:\CSDLNC\CSDLNC_demo\CSDLNC\library_app
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub
```

Xuất ảnh kiểm tra bố cục trên Windows:

```powershell
flutter test --no-pub --dart-define=CAPTURE_PREVIEWS=true
```

API có kiểm thử CRUD, validation, mượn/trả, rollback, tham chiếu, cạnh tranh tồn kho và HTTP trên `MemoryStore`. Flutter có kiểm thử điều hướng, tìm kiếm, lọc/sắp xếp, xử lý lỗi kết nối và bố cục rộng 320/390 px. Backend SQL đã được kiểm chứng bằng integration test trên SQL Server 2014 SQLEXPRESS local: CRUD, JSON tương thích Flutter, mượn/trả và rollback. Dữ liệu thử được rollback sau kiểm thử.

Trong `server`, chạy `npm run verify:atlas` để kiểm tra kết nối, số bản ghi, mã nghiệp vụ và truy vấn tìm kiếm/lọc/sắp xếp trên Atlas bằng thao tác chỉ đọc. Lệnh không thêm/sửa/xóa dữ liệu và không in URI hoặc nội dung bản ghi.

Nếu Node.js báo `querySrv ECONNREFUSED` và DNS hệ thống đang trỏ tới `127.0.0.1`, có thể đặt `MONGODB_DNS_SERVERS=1.1.1.1,8.8.8.8` trong `server/.env`. Cấu hình này chỉ đổi DNS cho tiến trình Node.js để phân giải địa chỉ Atlas, không thay đổi DNS của Windows. Bỏ dòng này để dùng DNS mặc định.

Để kiểm chứng SQL, trong `server-sql` đặt `$env:SQL_INTEGRATION_TEST='true'` rồi chạy `npm run test:integration`. Script `verify_sqlserver.ps1` cũ dùng bộ schema/procedure khác và không áp dụng cho backend SQL mới.

Đây là ứng dụng phục vụ bài học: trang sách tìm kiếm/lọc/sắp xếp qua API trên backend được chọn; trang chủ, biểu mẫu và lịch sử vẫn tải snapshot. Với thư viện lớn cần phân trang, giảm tải snapshot, đăng nhập và phân quyền, audit log và cơ chế chống gửi lặp phiếu mượn trước khi triển khai nhiều người dùng.
