-- Chạy trong SSMS: tạo database thực hành riêng, không xóa database đang có.
USE master;
GO
IF DB_ID(N'LibrarySqlDemo') IS NULL
    EXEC(N'CREATE DATABASE LibrarySqlDemo');
GO
USE LibrarySqlDemo;
GO
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    IF OBJECT_ID(N'dbo.Books', N'U') IS NOT NULL
        THROW 50001, N'Bảng Books đã tồn tại. Không chạy lại script tạo bảng.', 1;

    -- Document nhúng books.publisher được chuyển thành bảng riêng.
    -- Mỗi dòng giữ cặp name/year trong MongoDB; year không được hiểu là năm thành lập NXB.
    CREATE TABLE dbo.Publishers (
        PublisherId int IDENTITY(1,1) PRIMARY KEY,
        Name nvarchar(500) NOT NULL,
        [Year] int NOT NULL CHECK ([Year] BETWEEN 1000 AND 2200)
    );

    CREATE TABLE dbo.Books (
        BookCode varchar(40) PRIMARY KEY,
        Title nvarchar(500) NOT NULL,
        Category nvarchar(500) NOT NULL,
        PublisherId int NOT NULL REFERENCES dbo.Publishers(PublisherId),
        PublishedYear int NOT NULL CHECK (PublishedYear BETWEEN 1000 AND 2200),
        TotalCopies int NOT NULL CHECK (TotalCopies >= 0),
        AvailableCopies int NOT NULL,
        Status varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (Status IN ('ACTIVE', 'INACTIVE')),
        CONSTRAINT CK_Books_Stock CHECK (AvailableCopies BETWEEN 0 AND TotalCopies)
    );

    -- Mảng authors: mỗi tác giả của một sách thành một dòng, giữ thứ tự bằng AuthorOrder.
    CREATE TABLE dbo.BookAuthors (
        BookCode varchar(40) NOT NULL REFERENCES dbo.Books(BookCode),
        AuthorOrder int NOT NULL CHECK (AuthorOrder > 0),
        AuthorName nvarchar(200) NOT NULL,
        PRIMARY KEY (BookCode, AuthorOrder)
    );

    CREATE TABLE dbo.Readers (
        ReaderId varchar(40) PRIMARY KEY,
        FullName nvarchar(500) NOT NULL,
        Email nvarchar(500) NOT NULL,
        Phone nvarchar(500) NOT NULL DEFAULT N'',
        Address nvarchar(500) NOT NULL DEFAULT N'',
        RegisteredAt datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        Status varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (Status IN ('ACTIVE', 'INACTIVE'))
    );

    CREATE TABLE dbo.Staff (
        StaffId varchar(40) PRIMARY KEY,
        FullName nvarchar(500) NOT NULL,
        Email nvarchar(500) NOT NULL,
        Role nvarchar(500) NOT NULL,
        Status varchar(20) NOT NULL DEFAULT 'ACTIVE' CHECK (Status IN ('ACTIVE', 'INACTIVE'))
    );

    CREATE TABLE dbo.Loans (
        LoanCode varchar(80) PRIMARY KEY,
        ReaderId varchar(40) NOT NULL REFERENCES dbo.Readers(ReaderId),
        StaffId varchar(40) NOT NULL REFERENCES dbo.Staff(StaffId),
        BorrowDate datetime2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
        DueDate datetime2(3) NOT NULL,
        Status varchar(20) NOT NULL DEFAULT 'BORROWING' CHECK (Status IN ('BORROWING', 'RETURNED')),
        CONSTRAINT CK_Loans_Dates CHECK (DueDate > BorrowDate)
    );

    -- Mảng loans.items: mỗi sách mượn thành một dòng chi tiết phiếu.
    CREATE TABLE dbo.LoanItems (
        LoanCode varchar(80) NOT NULL REFERENCES dbo.Loans(LoanCode),
        BookCode varchar(40) NOT NULL REFERENCES dbo.Books(BookCode),
        TitleAtBorrow nvarchar(500) NOT NULL,
        Quantity int NOT NULL CHECK (Quantity BETWEEN 1 AND 1000),
        ReturnedQuantity int NOT NULL DEFAULT 0,
        PRIMARY KEY (LoanCode, BookCode),
        CONSTRAINT CK_LoanItems_Returns CHECK (ReturnedQuantity BETWEEN 0 AND Quantity)
    );

    -- Các index phục vụ truy vấn tương tự MongoDB.
    CREATE INDEX IX_Loans_Reader_Date ON dbo.Loans(ReaderId, BorrowDate DESC);
    CREATE INDEX IX_Loans_Status_Due ON dbo.Loans(Status, DueDate);
    CREATE INDEX IX_LoanItems_Book ON dbo.LoanItems(BookCode);
    CREATE INDEX IX_Books_Publisher ON dbo.Books(PublisherId);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
