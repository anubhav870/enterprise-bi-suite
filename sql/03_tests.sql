USE BI_DW;
SELECT 'FactSales row count = source' AS test,
  CASE WHEN (SELECT COUNT(*) FROM stg.SalesOrderDetail) = (SELECT COUNT(*) FROM dw.FactSales)
       THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'Sales total = source LineTotal',
  CASE WHEN ABS((SELECT SUM(LineTotal) FROM AdventureWorks2022.Sales.SalesOrderDetail)
              - (SELECT SUM(SalesAmount) FROM dw.FactSales)) < 1 THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'FactPurchasing spend = source',
  CASE WHEN ABS((SELECT SUM(LineTotal) FROM AdventureWorks2022.Purchasing.PurchaseOrderDetail)
              - (SELECT SUM(SpendAmount) FROM dw.FactPurchasing)) < 1 THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'No orphan products in FactSales',
  CASE WHEN NOT EXISTS (SELECT 1 FROM dw.FactSales f
        LEFT JOIN dw.DimProduct p ON p.ProductKey = f.ProductKey WHERE p.ProductKey IS NULL)
       THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'No orphan regions in FactSales',
  CASE WHEN NOT EXISTS (SELECT 1 FROM dw.FactSales f
        LEFT JOIN dw.DimRegion r ON r.RegionKey = f.RegionKey WHERE r.RegionKey IS NULL)
       THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'FactSales grain unique',
  CASE WHEN (SELECT COUNT(*) FROM dw.FactSales) =
       (SELECT COUNT(*) FROM (SELECT DISTINCT SalesOrderID, SalesOrderDetailID FROM dw.FactSales) x)
       THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'All fact dates exist in DimDate',
  CASE WHEN NOT EXISTS (SELECT 1 FROM dw.FactSales f
        LEFT JOIN dw.DimDate d ON d.DateKey = f.OrderDateKey WHERE d.DateKey IS NULL)
       THEN 'PASS' ELSE 'FAIL' END;