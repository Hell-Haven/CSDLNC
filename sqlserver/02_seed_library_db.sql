-- Dữ liệu mẫu từ server/data/seed.json, không phải bản sao dữ liệu Atlas hiện tại.
-- Chỉ thêm mã chưa tồn tại; không cập nhật hoặc xóa dữ liệu cũ.
USE LibrarySqlDemo;
GO
SET XACT_ABORT ON;
BEGIN TRY
  BEGIN TRANSACTION;
  IF NOT EXISTS (SELECT 1 FROM dbo.Publishers WHERE Name = N'NXB Giáo dục' AND [Year] = 2024)
    INSERT dbo.Publishers(Name, [Year]) VALUES (N'NXB Giáo dục', 2024);
  IF NOT EXISTS (SELECT 1 FROM dbo.Books WHERE BookCode = N'B001')
  BEGIN
    INSERT dbo.Books(BookCode, Title, Category, PublisherId, PublishedYear, TotalCopies, AvailableCopies, Status)
    VALUES (N'B001', N'Cơ sở dữ liệu MongoDB', N'Công nghệ thông tin', (SELECT TOP (1) PublisherId FROM dbo.Publishers WHERE Name = N'NXB Giáo dục' AND [Year] = 2024 ORDER BY PublisherId), 2024, 12, 12, N'ACTIVE');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B001', 1, N'Nhóm nghiên cứu CSDL');
  END;
  IF NOT EXISTS (SELECT 1 FROM dbo.Publishers WHERE Name = N'NXB Đại học Quốc gia' AND [Year] = 2023)
    INSERT dbo.Publishers(Name, [Year]) VALUES (N'NXB Đại học Quốc gia', 2023);
  IF NOT EXISTS (SELECT 1 FROM dbo.Books WHERE BookCode = N'B002')
  BEGIN
    INSERT dbo.Books(BookCode, Title, Category, PublisherId, PublishedYear, TotalCopies, AvailableCopies, Status)
    VALUES (N'B002', N'Lập trình Java căn bản', N'Công nghệ thông tin', (SELECT TOP (1) PublisherId FROM dbo.Publishers WHERE Name = N'NXB Đại học Quốc gia' AND [Year] = 2023 ORDER BY PublisherId), 2023, 8, 8, N'ACTIVE');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B002', 1, N'Nguyễn Văn A');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B002', 2, N'Trần Thị B');
  END;
  IF NOT EXISTS (SELECT 1 FROM dbo.Publishers WHERE Name = N'NXB Thanh niên' AND [Year] = 2025)
    INSERT dbo.Publishers(Name, [Year]) VALUES (N'NXB Thanh niên', 2025);
  IF NOT EXISTS (SELECT 1 FROM dbo.Books WHERE BookCode = N'B003')
  BEGIN
    INSERT dbo.Books(BookCode, Title, Category, PublisherId, PublishedYear, TotalCopies, AvailableCopies, Status)
    VALUES (N'B003', N'Flutter & Dart thực hành', N'Công nghệ thông tin', (SELECT TOP (1) PublisherId FROM dbo.Publishers WHERE Name = N'NXB Thanh niên' AND [Year] = 2025 ORDER BY PublisherId), 2025, 10, 10, N'ACTIVE');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B003', 1, N'Nhóm phát triển ứng dụng');
  END;
  IF NOT EXISTS (SELECT 1 FROM dbo.Publishers WHERE Name = N'NXB Khoa học và Kỹ thuật' AND [Year] = 2024)
    INSERT dbo.Publishers(Name, [Year]) VALUES (N'NXB Khoa học và Kỹ thuật', 2024);
  IF NOT EXISTS (SELECT 1 FROM dbo.Books WHERE BookCode = N'B004')
  BEGIN
    INSERT dbo.Books(BookCode, Title, Category, PublisherId, PublishedYear, TotalCopies, AvailableCopies, Status)
    VALUES (N'B004', N'Nhập môn trí tuệ nhân tạo', N'Công nghệ thông tin', (SELECT TOP (1) PublisherId FROM dbo.Publishers WHERE Name = N'NXB Khoa học và Kỹ thuật' AND [Year] = 2024 ORDER BY PublisherId), 2024, 6, 6, N'ACTIVE');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B004', 1, N'Lê Minh Khoa');
  END;
  IF NOT EXISTS (SELECT 1 FROM dbo.Publishers WHERE Name = N'NXB Trẻ' AND [Year] = 2022)
    INSERT dbo.Publishers(Name, [Year]) VALUES (N'NXB Trẻ', 2022);
  IF NOT EXISTS (SELECT 1 FROM dbo.Books WHERE BookCode = N'B005')
  BEGIN
    INSERT dbo.Books(BookCode, Title, Category, PublisherId, PublishedYear, TotalCopies, AvailableCopies, Status)
    VALUES (N'B005', N'Tư duy thiết kế', N'Kỹ năng', (SELECT TOP (1) PublisherId FROM dbo.Publishers WHERE Name = N'NXB Trẻ' AND [Year] = 2022 ORDER BY PublisherId), 2022, 5, 5, N'ACTIVE');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B005', 1, N'Trần An');
  END;
  IF NOT EXISTS (SELECT 1 FROM dbo.Publishers WHERE Name = N'NXB Kim Đồng' AND [Year] = 2020)
    INSERT dbo.Publishers(Name, [Year]) VALUES (N'NXB Kim Đồng', 2020);
  IF NOT EXISTS (SELECT 1 FROM dbo.Books WHERE BookCode = N'B006')
  BEGIN
    INSERT dbo.Books(BookCode, Title, Category, PublisherId, PublishedYear, TotalCopies, AvailableCopies, Status)
    VALUES (N'B006', N'Dế Mèn phiêu lưu ký', N'Văn học', (SELECT TOP (1) PublisherId FROM dbo.Publishers WHERE Name = N'NXB Kim Đồng' AND [Year] = 2020 ORDER BY PublisherId), 2020, 15, 15, N'ACTIVE');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B006', 1, N'Tô Hoài');
  END;
  IF NOT EXISTS (SELECT 1 FROM dbo.Publishers WHERE Name = N'NXB Giáo dục' AND [Year] = 2021)
    INSERT dbo.Publishers(Name, [Year]) VALUES (N'NXB Giáo dục', 2021);
  IF NOT EXISTS (SELECT 1 FROM dbo.Books WHERE BookCode = N'B007')
  BEGIN
    INSERT dbo.Books(BookCode, Title, Category, PublisherId, PublishedYear, TotalCopies, AvailableCopies, Status)
    VALUES (N'B007', N'Đại số tuyến tính', N'Khoa học', (SELECT TOP (1) PublisherId FROM dbo.Publishers WHERE Name = N'NXB Giáo dục' AND [Year] = 2021 ORDER BY PublisherId), 2021, 7, 7, N'ACTIVE');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B007', 1, N'Phạm Quốc Bình');
  END;
  IF NOT EXISTS (SELECT 1 FROM dbo.Publishers WHERE Name = N'NXB Thông tin và Truyền thông' AND [Year] = 2024)
    INSERT dbo.Publishers(Name, [Year]) VALUES (N'NXB Thông tin và Truyền thông', 2024);
  IF NOT EXISTS (SELECT 1 FROM dbo.Books WHERE BookCode = N'B008')
  BEGIN
    INSERT dbo.Books(BookCode, Title, Category, PublisherId, PublishedYear, TotalCopies, AvailableCopies, Status)
    VALUES (N'B008', N'Hệ quản trị SQL Server', N'Công nghệ thông tin', (SELECT TOP (1) PublisherId FROM dbo.Publishers WHERE Name = N'NXB Thông tin và Truyền thông' AND [Year] = 2024 ORDER BY PublisherId), 2024, 9, 9, N'ACTIVE');
    INSERT dbo.BookAuthors(BookCode, AuthorOrder, AuthorName) VALUES (N'B008', 1, N'Nguyễn Hoàng Nam');
  END;
  IF NOT EXISTS (SELECT 1 FROM dbo.Readers WHERE ReaderId = N'R001')
    INSERT dbo.Readers(ReaderId, FullName, Email, Phone, Address, RegisteredAt, Status) VALUES (N'R001', N'Võ Công Trí', N'tri@example.com', N'0901000001', N'TP. Hồ Chí Minh', CONVERT(datetime2(3), N'2026-10-01T00:00:00Z', 127), N'ACTIVE');
  IF NOT EXISTS (SELECT 1 FROM dbo.Readers WHERE ReaderId = N'R002')
    INSERT dbo.Readers(ReaderId, FullName, Email, Phone, Address, RegisteredAt, Status) VALUES (N'R002', N'Nguyễn Văn Hồng', N'hong@example.com', N'0901000002', N'TP. Hồ Chí Minh', CONVERT(datetime2(3), N'2026-10-02T00:00:00Z', 127), N'ACTIVE');
  IF NOT EXISTS (SELECT 1 FROM dbo.Staff WHERE StaffId = N'S001')
    INSERT dbo.Staff(StaffId, FullName, Email, Role, Status) VALUES (N'S001', N'Thủ thư mẫu', N'library@example.com', N'LIBRARIAN', N'ACTIVE');
  COMMIT TRANSACTION;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
  THROW;
END CATCH;
GO
SELECT COUNT(*) AS Titles, SUM(TotalCopies) AS Copies FROM dbo.Books;
