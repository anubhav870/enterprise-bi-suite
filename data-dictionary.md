# Data Dictionary

Documents every table in the `BI_DW` warehouse (schema `dw`), the supporting tables, the DAX measures, and where each column comes from.

**Source database:** `AdventureWorks2022` (SQL Server). The load reads from the `etl.*` views, which expose only the columns the warehouse needs.
**Load path:** `etl.*` views, then `stg.*` (staging copy), then `dw.*` (star schema) through `dw.usp_LoadDW`.
**Keys:** dimension keys are the source business keys, because the sample data is static.

---

## 1. Dimension tables

### DimDate
One row per calendar day, 2011-01-01 to 2014-12-31. Generated in SQL, not taken from the source.

| Column | Type | Description |
|---|---|---|
| DateKey | int | Surrogate date key in `yyyymmdd` form (for example 20130115). Primary key. |
| Date | date | The calendar date. Marked as the date table in Power BI. |
| Year | int | Calendar year. |
| Quarter | int | Quarter number, 1 to 4. |
| QuarterName | varchar | Quarter label, such as `Q1`. |
| MonthNumber | int | Month number, 1 to 12. Used to sort `MonthName`. |
| MonthName | varchar | Full month name, such as `January`. |
| MonthYear | varchar | Label such as `Jan 2013`. |
| MonthYearSort | int | `yyyymm` number (for example 201301). Used to sort `MonthYear`. |
| DayName | varchar | Weekday name. |
| IsMonthEnd | int | 1 if the date is the last day of its month, otherwise 0. Used by `FactHeadcount`. |

### DimRegion
One row per sales territory.

| Column | Type | Source | Description |
|---|---|---|---|
| RegionKey | int | `Sales.SalesTerritory.TerritoryID` | Primary key. |
| TerritoryName | varchar | `SalesTerritory.Name` | Territory, such as `Southwest` or `France`. |
| CountryRegionCode | varchar | `SalesTerritory.CountryRegionCode` | Country code. |
| RegionGroup | varchar | `SalesTerritory.[Group]` | `North America`, `Europe` or `Pacific`. Row-level security filters on this column. |

### DimProduct
One row per product.

| Column | Type | Source | Description |
|---|---|---|---|
| ProductKey | int | `Production.Product.ProductID` | Primary key. |
| ProductName | varchar | `Product.Name` | Product name. |
| ProductNumber | varchar | `Product.ProductNumber` | Product code. |
| Color | varchar | `Product.Color` | Colour. Nulls are replaced with `N/A` in Power Query. |
| Category | varchar | `ProductCategory.Name` | Category. Products with no subcategory are labelled `Components/Other`. |
| Subcategory | varchar | `ProductSubcategory.Name` | Subcategory, with the same fallback label. |
| StandardCost | decimal | `Product.StandardCost` | Current standard unit cost. Used to calculate `TotalCost`. |
| ListPrice | decimal | `Product.ListPrice` | List price. |

### DimCustomer
One row per customer.

| Column | Type | Source | Description |
|---|---|---|---|
| CustomerKey | int | `Sales.Customer.CustomerID` | Primary key. |
| CustomerName | varchar | `Sales.Store.Name`, otherwise first and last name from `Person.Person` | Store name for store customers, person name for individuals. |
| CustomerType | varchar | derived | `Store` if the customer has a store, otherwise `Individual`. |

### DimVendor
One row per supplier.

| Column | Type | Source | Description |
|---|---|---|---|
| VendorKey | int | `Purchasing.Vendor.BusinessEntityID` | Primary key. |
| VendorName | varchar | `Vendor.Name` | Vendor name. |
| CreditRating | int | `Vendor.CreditRating` | Credit rating, 1 to 5 (whole number set in Power Query). |

### DimEmployee
One row per employee.

| Column | Type | Source | Description |
|---|---|---|---|
| EmployeeKey | int | `HumanResources.Employee.BusinessEntityID` | Primary key. |
| EmployeeName | varchar | `Person.Person` first and last name | Full name. Trimmed in Power Query. |
| JobTitle | varchar | `Employee.JobTitle` | Job title. Trimmed in Power Query. |
| Gender | varchar | `Employee.Gender` | `M` or `F`. |
| HireDate | date | `Employee.HireDate` | Date hired. |
| DepartmentName | varchar | `HumanResources.Department.Name` | Current department (the history row with no end date). Trimmed in Power Query. |
| DepartmentGroup | varchar | `Department.GroupName` | Department group. |

---

## 2. Fact tables

### FactSales
**Grain:** one row per sales order line. 121,317 rows.

| Column | Type | Source | Description |
|---|---|---|---|
| SalesOrderID | int | `Sales.SalesOrderDetail` | Order number. Part of the grain. |
| SalesOrderDetailID | int | `Sales.SalesOrderDetail` | Line number. Part of the grain. |
| OrderDateKey | int | `SalesOrderHeader.OrderDate` | Links to `DimDate[DateKey]`. |
| ProductKey | int | `SalesOrderDetail.ProductID` | Links to `DimProduct`. |
| CustomerKey | int | `SalesOrderHeader.CustomerID` | Links to `DimCustomer`. |
| RegionKey | int | `SalesOrderHeader.TerritoryID` | Links to `DimRegion`. |
| Channel | varchar | `SalesOrderHeader.OnlineOrderFlag` | `Online` or `Reseller`. |
| OrderQty | int | `SalesOrderDetail.OrderQty` | Units ordered. |
| UnitPrice | decimal | `SalesOrderDetail.UnitPrice` | Price per unit. |
| UnitPriceDiscount | decimal | `SalesOrderDetail.UnitPriceDiscount` | Discount fraction. |
| SalesAmount | decimal(19,4) | `SalesOrderDetail.LineTotal` | Revenue for the line. |
| TotalCost | decimal(19,4) | `OrderQty * Product.StandardCost` | Cost for the line, at the product's current standard cost. |

### FactPurchasing
**Grain:** one row per purchase order line. 8,845 rows.

| Column | Type | Source | Description |
|---|---|---|---|
| PurchaseOrderID | int | `Purchasing.PurchaseOrderDetail` | Order number. |
| PurchaseOrderDetailID | int | `Purchasing.PurchaseOrderDetail` | Line number. |
| OrderDateKey | int | `PurchaseOrderHeader.OrderDate` | Links to `DimDate`. |
| VendorKey | int | `PurchaseOrderHeader.VendorID` | Links to `DimVendor`. |
| ProductKey | int | `PurchaseOrderDetail.ProductID` | Links to `DimProduct`. |
| RegionKey | int | derived: `(VendorID % 10) + 1` | **Synthetic.** The source has no region for vendors. Links to `DimRegion`. |
| OrderQty | int | `PurchaseOrderDetail.OrderQty` | Units ordered. |
| ReceivedQty | decimal | `PurchaseOrderDetail.ReceivedQty` | Units received. |
| RejectedQty | decimal | `PurchaseOrderDetail.RejectedQty` | Units rejected. |
| UnitPrice | decimal | `PurchaseOrderDetail.UnitPrice` | Price per unit. |
| SpendAmount | decimal(19,4) | `PurchaseOrderDetail.LineTotal` | Spend for the line. |
| OnTimeFlag | int | derived: `ShipDate <= DueDate` | 1 on time, 0 late, null if not yet shipped. |

### FactHeadcount
**Grain:** one row per employee per month-end, from the month of hire onwards.

| Column | Type | Source | Description |
|---|---|---|---|
| DateKey | int | `DimDate` (month-end days only) | Links to `DimDate`. |
| EmployeeKey | int | `Employee.BusinessEntityID` | Links to `DimEmployee`. |
| RegionKey | int | `SalesPerson.TerritoryID`, otherwise `(EmployeeID % 10) + 1` | Real territory for salespeople, **synthetic** for everyone else. Links to `DimRegion`. |
| HeadcountFlag | int | constant 1 | Counts the employee as present on that month-end. |
| NewHireFlag | int | derived | 1 if the employee was hired in that month. |
| PayRate | decimal | `EmployeePayHistory.Rate` (latest) | Latest hourly pay rate. |
| TenureMonths | int | `DATEDIFF(MONTH, HireDate, Date)` | Months employed at that month-end. |

---

## 3. Supporting tables

| Table | Where | Purpose |
|---|---|---|
| `dw.EtlLog` | `BI_DW` | One row per table per load: table name, row count and time. Used to check each run. |
| `UserRegion` | Power BI model (entered data) | Maps manager emails to a `RegionGroup` for row-level security. Hidden from report view. Emails are placeholders. |
| `_Measures` | Power BI model | Empty table that holds all DAX measures. |
| `stg.*` | `BI_DW` | Staging copies of the nine `etl.*` views, rebuilt on every load. |

---

## 4. Relationships

All are many-to-one, single direction, active.

| From (many) | To (one) |
|---|---|
| FactSales[OrderDateKey], FactPurchasing[OrderDateKey], FactHeadcount[DateKey] | DimDate[DateKey] |
| FactSales[RegionKey], FactPurchasing[RegionKey], FactHeadcount[RegionKey] | DimRegion[RegionKey] |
| FactSales[ProductKey], FactPurchasing[ProductKey] | DimProduct[ProductKey] |
| FactSales[CustomerKey] | DimCustomer[CustomerKey] |
| FactPurchasing[VendorKey] | DimVendor[VendorKey] |
| FactHeadcount[EmployeeKey] | DimEmployee[EmployeeKey] |

`UserRegion` has no relationships. The security role reads it directly.

---

## 5. DAX measures

| Measure | Definition | Meaning |
|---|---|---|
| Sales | `SUM(FactSales[SalesAmount])` | Total revenue. |
| Total Cost | `SUM(FactSales[TotalCost])` | Total cost of goods sold. |
| Gross Profit | `[Sales] - [Total Cost]` | Revenue minus cost. |
| Margin % | `DIVIDE([Gross Profit], [Sales])` | Gross profit as a share of sales. |
| Orders | `DISTINCTCOUNT(FactSales[SalesOrderID])` | Number of distinct orders. |
| Avg Order Value | `DIVIDE([Sales], [Orders])` | Average revenue per order. |
| Sales YTD | `TOTALYTD([Sales], DimDate[Date])` | Running total since 1 January. |
| Sales PY | `CALCULATE([Sales], SAMEPERIODLASTYEAR(DimDate[Date]))` | Sales for the same period last year. |
| Sales YoY % | `DIVIDE([Sales] - [Sales PY], [Sales PY])` | Growth versus last year. |
| Sales YTD PY | `CALCULATE([Sales YTD], SAMEPERIODLASTYEAR(DimDate[Date]))` | Last year's YTD at the same point. |
| Sales YTD YoY % | `DIVIDE([Sales YTD] - [Sales YTD PY], [Sales YTD PY])` | YTD growth versus last year. |
| Sales 3M Rolling Avg | Average of the current month and the two before it | Smooths monthly swings. |
| Purchase Spend | `SUM(FactPurchasing[SpendAmount])` | Total purchasing spend. |
| On-Time Delivery % | `DIVIDE(SUM(FactPurchasing[OnTimeFlag]), COUNT(FactPurchasing[OnTimeFlag]))` | Share of order lines shipped by their due date. |
| Rejection Rate % | `DIVIDE(SUM(FactPurchasing[RejectedQty]), SUM(FactPurchasing[ReceivedQty]))` | Share of received units rejected. |
| Headcount | `CALCULATE(SUM(FactHeadcount[HeadcountFlag]), LASTDATE(DimDate[Date]))` | Employees on the last month-end of the selected period. |
| New Hires | `SUM(FactHeadcount[NewHireFlag])` | Employees hired in the selected period. |
| Avg Pay Rate | `CALCULATE(AVERAGE(FactHeadcount[PayRate]), LASTDATE(DimDate[Date]))` | Average hourly pay at the last month-end. |
| Avg Tenure (Months) | `CALCULATE(AVERAGE(FactHeadcount[TenureMonths]), LASTDATE(DimDate[Date]))` | Average months employed at the last month-end. |

`LASTDATE` is used for the HR measures because the headcount fact has one row per employee per month-end, so adding a whole year would count each person twelve times.

---

## 6. Known data caveats

- `RegionKey` in `FactPurchasing`, and for non-sales staff in `FactHeadcount`, is **synthetic** (assigned from IDs). Sales regions are real.
- `TotalCost` uses the product's **current** standard cost, not the cost at the time of sale.
- Sales data runs mid-2011 to mid-2014, so 2011 and 2014 are partial years.
- The source has no employee termination dates, so attrition cannot be calculated.
