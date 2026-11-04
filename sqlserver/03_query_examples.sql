USE LibrarySqlDemo;
GO
-- READ: danh sách sách kèm thông tin NXB (JOIN thay document nhúng).
SELECT b.*, p.Name AS PublisherName, p.[Year] AS PublisherYear
FROM dbo.Books b JOIN dbo.Publishers p ON p.PublisherId = b.PublisherId;

-- Tìm theo tên, mã hoặc tác giả. N trước chuỗi để giữ nguyên tiếng Việt.
DECLARE @Keyword nvarchar(200) = N'mongo';
SELECT b.* FROM dbo.Books b
WHERE b.Title LIKE N'%' + @Keyword + N'%'
   OR b.BookCode LIKE N'%' + @Keyword + N'%'
   OR EXISTS (SELECT 1 FROM dbo.BookAuthors a
              WHERE a.BookCode = b.BookCode AND a.AuthorName LIKE N'%' + @Keyword + N'%');

-- Lọc thể loại và sắp xếp năm xuất bản mới nhất trước.
SELECT * FROM dbo.Books
WHERE Category = N'Công nghệ thông tin' AND AvailableCopies > 0 AND Status = 'ACTIVE'
ORDER BY PublishedYear DESC, BookCode ASC;

-- DISTINCT tương ứng MongoDB distinct('category').
SELECT DISTINCT Category FROM dbo.Books ORDER BY Category;

-- GROUP BY tương ứng Aggregation Pipeline thống kê thể loại.
SELECT Category, COUNT(*) AS Titles, SUM(TotalCopies) AS Copies
FROM dbo.Books GROUP BY Category ORDER BY Titles DESC;

-- Phiếu quá hạn và chi tiết phiếu (JOIN thay loans.items).
SELECT l.LoanCode, r.FullName, l.DueDate, i.BookCode, i.TitleAtBorrow,
       i.Quantity - i.ReturnedQuantity AS OutstandingQuantity
FROM dbo.Loans l
JOIN dbo.Readers r ON r.ReaderId = l.ReaderId
JOIN dbo.LoanItems i ON i.LoanCode = l.LoanCode
WHERE l.Status = 'BORROWING' AND l.DueDate < SYSUTCDATETIME()
  AND i.ReturnedQuantity < i.Quantity
ORDER BY l.DueDate;

-- Ví dụ UPDATE/DELETE để chọn chạy riêng, không tự thay dữ liệu khi chạy cả file.
-- UPDATE dbo.Books SET Title = N'Tên mới' WHERE BookCode = 'B001';
-- UPDATE dbo.Readers SET Phone = N'0900000000' WHERE ReaderId = 'R001';
-- Không xóa sách có phiếu mượn tham chiếu. Dùng INACTIVE để giữ lịch sử.
-- UPDATE dbo.Books SET Status = 'INACTIVE' WHERE BookCode = 'B001';
-- DELETE FROM dbo.BookAuthors WHERE BookCode = 'MA_SACH_THU';
-- DELETE FROM dbo.Books WHERE BookCode = 'MA_SACH_THU';

-- Ghi chú: lập phiếu/trả sách phải cập nhật Books và Loans/LoanItems trong
-- cùng transaction, kèm kiểm tra tồn kho; không chỉ INSERT phiếu riêng lẻ.
