USE AdventureWorks2022;
GO
CREATE SCHEMA etl;
GO
CREATE VIEW etl.SalesOrderHeader AS
SELECT SalesOrderID, OrderDate, ShipDate, CustomerID, TerritoryID, OnlineOrderFlag
FROM Sales.SalesOrderHeader;
GO
CREATE VIEW etl.SalesOrderDetail AS
SELECT SalesOrderID, SalesOrderDetailID, ProductID, OrderQty, UnitPrice, UnitPriceDiscount, LineTotal
FROM Sales.SalesOrderDetail;
GO
CREATE VIEW etl.SalesTerritory AS
SELECT TerritoryID, Name AS TerritoryName, CountryRegionCode, [Group] AS RegionGroup
FROM Sales.SalesTerritory;
GO
CREATE VIEW etl.Customer AS
SELECT c.CustomerID,
       COALESCE(s.Name, p.FirstName + ' ' + p.LastName) AS CustomerName,
       CASE WHEN c.StoreID IS NOT NULL THEN 'Store' ELSE 'Individual' END AS CustomerType
FROM Sales.Customer c
LEFT JOIN Sales.Store s ON s.BusinessEntityID = c.StoreID
LEFT JOIN Person.Person p ON p.BusinessEntityID = c.PersonID;
GO
CREATE VIEW etl.Product AS
SELECT p.ProductID, p.Name AS ProductName, p.ProductNumber, p.Color, p.StandardCost, p.ListPrice,
       ISNULL(pc.Name, 'Components/Other') AS Category,
       ISNULL(ps.Name, 'Components/Other') AS Subcategory
FROM Production.Product p
LEFT JOIN Production.ProductSubcategory ps ON ps.ProductSubcategoryID = p.ProductSubcategoryID
LEFT JOIN Production.ProductCategory pc ON pc.ProductCategoryID = ps.ProductCategoryID;
GO
CREATE VIEW etl.PurchaseOrderHeader AS
SELECT PurchaseOrderID, OrderDate, ShipDate, VendorID FROM Purchasing.PurchaseOrderHeader;
GO
CREATE VIEW etl.PurchaseOrderDetail AS
SELECT PurchaseOrderID, PurchaseOrderDetailID, DueDate, ProductID, OrderQty, UnitPrice,
       LineTotal, ReceivedQty, RejectedQty
FROM Purchasing.PurchaseOrderDetail;
GO
CREATE VIEW etl.Vendor AS
SELECT BusinessEntityID AS VendorID, Name AS VendorName, CreditRating FROM Purchasing.Vendor;
GO
CREATE VIEW etl.Employee AS
SELECT e.BusinessEntityID AS EmployeeID,
       p.FirstName + ' ' + p.LastName AS EmployeeName,
       e.JobTitle, e.Gender, e.HireDate,
       d.Name AS DepartmentName, d.GroupName AS DepartmentGroup,
       sp.TerritoryID,
       (SELECT TOP 1 ph.Rate FROM HumanResources.EmployeePayHistory ph
        WHERE ph.BusinessEntityID = e.BusinessEntityID
        ORDER BY ph.RateChangeDate DESC) AS LatestPayRate
FROM HumanResources.Employee e
JOIN Person.Person p ON p.BusinessEntityID = e.BusinessEntityID
LEFT JOIN HumanResources.EmployeeDepartmentHistory dh
       ON dh.BusinessEntityID = e.BusinessEntityID AND dh.EndDate IS NULL
LEFT JOIN HumanResources.Department d ON d.DepartmentID = dh.DepartmentID
LEFT JOIN Sales.SalesPerson sp ON sp.BusinessEntityID = e.BusinessEntityID;
GO