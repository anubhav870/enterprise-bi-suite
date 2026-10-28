CREATE DATABASE BI_DW;
GO
USE BI_DW;
GO
CREATE SCHEMA stg;
GO
CREATE SCHEMA dw;
GO
CREATE TABLE dw.EtlLog (
    RunId int IDENTITY PRIMARY KEY,
    RunAt datetime2 DEFAULT SYSUTCDATETIME(),
    TableName sysname,
    RowCnt int
);
GO
-- LOCAL MODE ONLY (in ADF mode, Copy activities fill stg instead)
CREATE OR ALTER PROCEDURE stg.usp_RefreshStaging AS
BEGIN
    SET NOCOUNT ON;
    DROP TABLE IF EXISTS stg.SalesOrderHeader, stg.SalesOrderDetail, stg.SalesTerritory,
        stg.Customer, stg.Product, stg.PurchaseOrderHeader, stg.PurchaseOrderDetail,
        stg.Vendor, stg.Employee;
    SELECT * INTO stg.SalesOrderHeader   FROM AdventureWorks2022.etl.SalesOrderHeader;
    SELECT * INTO stg.SalesOrderDetail   FROM AdventureWorks2022.etl.SalesOrderDetail;
    SELECT * INTO stg.SalesTerritory     FROM AdventureWorks2022.etl.SalesTerritory;
    SELECT * INTO stg.Customer           FROM AdventureWorks2022.etl.Customer;
    SELECT * INTO stg.Product            FROM AdventureWorks2022.etl.Product;
    SELECT * INTO stg.PurchaseOrderHeader FROM AdventureWorks2022.etl.PurchaseOrderHeader;
    SELECT * INTO stg.PurchaseOrderDetail FROM AdventureWorks2022.etl.PurchaseOrderDetail;
    SELECT * INTO stg.Vendor             FROM AdventureWorks2022.etl.Vendor;
    SELECT * INTO stg.Employee           FROM AdventureWorks2022.etl.Employee;
END
GO
CREATE OR ALTER PROCEDURE dw.usp_LoadDW AS
BEGIN
    SET NOCOUNT ON;
    DROP TABLE IF EXISTS dw.FactSales, dw.FactPurchasing, dw.FactHeadcount,
        dw.DimDate, dw.DimRegion, dw.DimProduct, dw.DimCustomer, dw.DimVendor, dw.DimEmployee;

    -- DIMENSIONS
    ;WITH d AS (
        SELECT CAST('2011-01-01' AS date) AS dt
        UNION ALL SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2014-12-31')
    SELECT CONVERT(int, CONVERT(char(8), dt, 112)) AS DateKey,
           dt AS [Date], YEAR(dt) AS [Year], DATEPART(QUARTER, dt) AS [Quarter],
           'Q' + CAST(DATEPART(QUARTER, dt) AS varchar(1)) AS QuarterName,
           MONTH(dt) AS MonthNumber, DATENAME(MONTH, dt) AS [MonthName],
           LEFT(DATENAME(MONTH, dt), 3) + ' ' + CAST(YEAR(dt) AS varchar(4)) AS MonthYear,
           YEAR(dt) * 100 + MONTH(dt) AS MonthYearSort,
           DATENAME(WEEKDAY, dt) AS [DayName],
           CASE WHEN dt = EOMONTH(dt) THEN 1 ELSE 0 END AS IsMonthEnd
    INTO dw.DimDate FROM d OPTION (MAXRECURSION 0);

    SELECT TerritoryID AS RegionKey, TerritoryName, CountryRegionCode, RegionGroup
    INTO dw.DimRegion FROM stg.SalesTerritory;

    SELECT ProductID AS ProductKey, ProductName, ProductNumber, Color, Category,
           Subcategory, StandardCost, ListPrice
    INTO dw.DimProduct FROM stg.Product;

    SELECT CustomerID AS CustomerKey, CustomerName, CustomerType
    INTO dw.DimCustomer FROM stg.Customer;

    SELECT VendorID AS VendorKey, VendorName, CreditRating
    INTO dw.DimVendor FROM stg.Vendor;

    SELECT EmployeeID AS EmployeeKey, EmployeeName, JobTitle, Gender, HireDate,
           DepartmentName, DepartmentGroup
    INTO dw.DimEmployee FROM stg.Employee;

    -- FACTS
    SELECT d.SalesOrderID, d.SalesOrderDetailID,
           CONVERT(int, CONVERT(char(8), h.OrderDate, 112)) AS OrderDateKey,
           d.ProductID AS ProductKey, h.CustomerID AS CustomerKey, h.TerritoryID AS RegionKey,
           CASE WHEN h.OnlineOrderFlag = 1 THEN 'Online' ELSE 'Reseller' END AS Channel,
           d.OrderQty, d.UnitPrice, d.UnitPriceDiscount,
           CAST(d.LineTotal AS decimal(19,4)) AS SalesAmount,
           CAST(d.OrderQty * p.StandardCost AS decimal(19,4)) AS TotalCost
    INTO dw.FactSales
    FROM stg.SalesOrderDetail d
    JOIN stg.SalesOrderHeader h ON h.SalesOrderID = d.SalesOrderID
    JOIN stg.Product p ON p.ProductID = d.ProductID;

    SELECT d.PurchaseOrderID, d.PurchaseOrderDetailID,
           CONVERT(int, CONVERT(char(8), h.OrderDate, 112)) AS OrderDateKey,
           h.VendorID AS VendorKey, d.ProductID AS ProductKey,
           (h.VendorID % 10) + 1 AS RegionKey,          -- synthetic region
           d.OrderQty, d.ReceivedQty, d.RejectedQty, d.UnitPrice,
           CAST(d.LineTotal AS decimal(19,4)) AS SpendAmount,
           CASE WHEN h.ShipDate IS NULL THEN NULL
                WHEN h.ShipDate <= d.DueDate THEN 1 ELSE 0 END AS OnTimeFlag
    INTO dw.FactPurchasing
    FROM stg.PurchaseOrderDetail d
    JOIN stg.PurchaseOrderHeader h ON h.PurchaseOrderID = d.PurchaseOrderID;

    SELECT dd.DateKey, e.EmployeeID AS EmployeeKey,
           COALESCE(e.TerritoryID, (e.EmployeeID % 10) + 1) AS RegionKey,
           1 AS HeadcountFlag,
           CASE WHEN EOMONTH(e.HireDate) = dd.[Date] THEN 1 ELSE 0 END AS NewHireFlag,
           e.LatestPayRate AS PayRate,
           DATEDIFF(MONTH, e.HireDate, dd.[Date]) AS TenureMonths
    INTO dw.FactHeadcount
    FROM dw.DimDate dd
    JOIN stg.Employee e ON e.HireDate <= dd.[Date]
    WHERE dd.IsMonthEnd = 1;

    -- LOG
    INSERT dw.EtlLog (TableName, RowCnt)
    SELECT 'FactSales', COUNT(*) FROM dw.FactSales
    UNION ALL SELECT 'FactPurchasing', COUNT(*) FROM dw.FactPurchasing
    UNION ALL SELECT 'FactHeadcount', COUNT(*) FROM dw.FactHeadcount;
END
GO
EXEC stg.usp_RefreshStaging;
EXEC dw.usp_LoadDW;