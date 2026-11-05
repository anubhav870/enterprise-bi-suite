# Enterprise Business Intelligence Suite for a Multi-Region Company

One reporting system that combines **sales, finance, supply chain (purchasing) and HR** data from the AdventureWorks sample company, with **secure per-region access** so each region manager sees only their own data.

**Project:** DA-01, Data Analytics track
**Author:** Anubhav
**Stack:** SQL Server, Power Query, Power BI (DAX), Power BI Service, on-premises data gateway
\---

## 1\. Problem

A multi-region company keeps sales, finance, HR and supply-chain data in separate tables. Leaders need one consistent set of numbers (YTD, year-over-year growth, margin %, rolling averages) and regional managers must only see their own region. This project builds that end to end: warehouse, pipeline, semantic model, dashboards, security and scheduled refresh.

## 2\. Architecture

```
AdventureWorks2022 (OLTP, SQL Server)
        |
        v   etl.\* source views (extract contract)
Staging schema (BI\_DW.stg)
        |
        v   dw.usp\_LoadDW (stored procedure)
Star schema (BI\_DW.dw)
        |
        v   Power Query, relationships, DAX measures, RLS
Power BI semantic model (BI\_Suite.pbix)
        |
        v   publish + on-premises data gateway + scheduled refresh
Power BI Service  ->  region managers
```

Architecture diagram: `docs/architecture-diagram.png` `\[TODO: add after drawing in draw.io]`

## 3\. Dataset

**AdventureWorks2022** (Microsoft sample database, OLTP version). It covers four domains in one database:

|Domain|Source schema|
|-|-|
|Sales and finance|`Sales` (orders, customers, territories), `Production` (product cost)|
|Supply chain|`Purchasing` (purchase orders, vendors)|
|HR|`HumanResources` (employees, departments, pay history)|

The data runs from about mid-2011 to mid-2014, so 2011 and 2014 are partial years. Use **2012 vs 2013** for year-over-year comparisons.

## 4\. Data model (star schema)

**Fact tables**

|Table|Grain|Key measures|
|-|-|-|
|`FactSales`|one row per sales order line (121,317 rows)|SalesAmount, TotalCost, OrderQty|
|`FactPurchasing`|one row per purchase order line (8,845 rows)|SpendAmount, ReceivedQty, RejectedQty, OnTimeFlag|
|`FactHeadcount`|one row per employee per month-end|HeadcountFlag, NewHireFlag, PayRate, TenureMonths|

**Dimension tables:** `DimDate` (2011-2014, with month and quarter sort columns), `DimRegion`, `DimProduct`, `DimCustomer`, `DimVendor`, `DimEmployee`.

`DimDate` and `DimRegion` are shared by all three fact tables, which is what lets one slicer filter sales, purchasing and HR together.

Full column list: `docs/data-dictionary.md`

## 5\. Repository structure

```
sql/
  01\_source\_views.sql     etl.\* views over AdventureWorks2022
  02\_warehouse.sql        BI\_DW database, staging refresh proc, star schema load proc
  03\_tests.sql            data-quality tests (7 checks)
powerbi/
  BI\_Suite.pbix           Power BI model and report
docs/
  screenshots/            test and evidence screenshots
  architecture-diagram.png    \[TODO]
  data-dictionary.md          \[TODO]
  user-guide.pdf              \[TODO]
demo/                     screen recording  \[TODO]
README.md
```

## 6\. Setup instructions

### Prerequisites

* Windows PC (Power BI Desktop is Windows-only)
* SQL Server Developer edition and SQL Server Management Studio (SSMS)
* Power BI Desktop
* A work or school account for Power BI Service
* `AdventureWorks2022.bak` from Microsoft's sample databases page

### Steps

1. **Restore the source database.** In SSMS: right-click *Databases*, *Restore Database*, *Device*, choose `AdventureWorks2022.bak`.
2. **Create the source views.** Run `sql/01\_source\_views.sql`.
3. **Build the warehouse.** Run `sql/02\_warehouse.sql`. It creates `BI\_DW`, loads staging, and builds the star schema. Check `SELECT \* FROM BI\_DW.dw.EtlLog;` for row counts.
4. **Run the tests.** Run `sql/03\_tests.sql`. All 7 rows should say `PASS`.
5. **Open the report.** Open `powerbi/BI\_Suite.pbix` in Power BI Desktop. If asked for credentials, use your Windows login for server `localhost`, database `BI\_DW`.
6. **Publish.** *Home, Publish*, choose a workspace.
7. **Refresh.** Install an on-premises data gateway, add a SQL Server connection (server `localhost`, database `BI\_DW`), map the semantic model to it, and set a daily refresh. A dedicated read-only SQL login (`db\_datareader` on `BI\_DW`) was used for the gateway connection. Credentials are not stored in this repository.
8. **Assign security.** In the Service, add region managers to the `RegionManager` role (see section 9).

## 7\. Data movement

|Item|Status|
|-|-|
|Source views to staging to star schema, in SQL (`stg.usp\_RefreshStaging`, `dw.usp\_LoadDW`)|Done|
| Scheduled load: SQL Server Agent job `BI_DW_Daily_Load` (step 1 refreshes staging, step 2 loads the warehouse, daily at 2:00 AM). Evidence: `docs/screenshots/sql-agent-job-history.png` | Done |
| Azure Data Factory pipeline | Not completed. The scheduled SQL load was used instead, which the brief allows. |
|Power BI Service scheduled refresh through the gateway|Done (daily, 3:00 AM)|

The warehouse load rebuilds all tables on each run. This is fine at this data size.

## 8\. Report pages and DAX measures

**Pages:** Executive Overview, Sales, Finance, Supply Chain, HR. **Drill-through pages:** Product Detail, Customer Detail, Vendor Detail. A hidden `Test Checks` page holds the validation tables.

**Measures (all in the `\_Measures` table)**

|Group|Measures|
|-|-|
|Sales|Sales, Total Cost, Gross Profit, Margin %, Orders, Avg Order Value|
|Time intelligence|Sales YTD, Sales PY, Sales YoY %, Sales YTD PY, Sales YTD YoY %, Sales 3M Rolling Avg|
|Supply chain|Purchase Spend, On-Time Delivery %, Rejection Rate %|
|HR|Headcount, New Hires, Avg Pay Rate, Avg Tenure (Months)|

`Headcount`, `Avg Pay Rate` and `Avg Tenure` use `LASTDATE` because the headcount fact has one row per employee per month-end, so adding up a year would count each person twelve times.

## 9\. Row-level security

One dynamic role, `RegionManager`, filters `DimRegion` using a mapping table:

```dax
\[RegionGroup] IN
    SELECTCOLUMNS(
        FILTER(UserRegion, UserRegion\[Email] = USERPRINCIPALNAME()),
        "g", UserRegion\[RegionGroup]
    )
```

`UserRegion` (Email, RegionGroup) maps each manager to North America, Europe or Pacific. The relationships pass the filter to all three fact tables, so every page is restricted. A user not in the table sees nothing.

The emails in the repository are placeholders. In production, replace them with real organisation accounts and add the same accounts as members of the `RegionManager` role in the Power BI Service.

Evidence: `docs/screenshots/rls-north-america.png`, `rls-europe.png`, `rls-pacific.png`, `rls-unlisted-user.png`, and the Service tests `service-rls-\*.png`.

## 10\. Testing and results

### Data-quality tests (`sql/03\_tests.sql`): 7 of 7 pass

Row count equals source, sales total equals source, purchasing spend equals source, no orphan products, no orphan regions, unique fact grain, all fact dates exist in `DimDate`.

### DAX validation against SQL Server

|Check|Power BI|SQL|
|-|-|-|
|2013 sales|43,622,479|43,622,479.07|
|2013 orders|14,182|14,182|
|Sales PY for Jan 2013|3,970,627|Jan 2012 = 3,970,627|
|Sales YTD at Dec 2013|43,622,479|full-year 2013 total|
|3M rolling average at Mar 2013|2,605,621|(Jan + Feb + Mar 2013) / 3|
|Purchasing and headcount by year|matched|matched|

### Security results (2013)

|Region|Sales|Margin %|Headcount|
|-|-|-|-|
|North America|$29.4M|3.43%|177|
|Europe|$10.0M|11.86%|85|
|Pacific|$4.2M|27.39%|28|

The three regions add up to the company total of $43.6M.

### Performance `\[TODO]`

* SQL warehouse load time: `\[TODO: seconds]`
* Power BI Service refresh duration: `\[TODO: from refresh history]`
* Slowest visual (Performance Analyzer): `\[TODO: ms]`

## 11\. Known limitations

* **Synthetic regions for purchasing and HR.** AdventureWorks has no region for vendors or most employees. Vendors were assigned a region from their ID (`VendorID % 10 + 1`), and employees without a sales territory from their ID. Sales regions are real. The purchasing and HR region views are for demonstration of the security design only.
* **Margin uses today's standard cost.** `TotalCost` is quantity multiplied by the product's current `StandardCost`, not the historical cost at time of sale.
* **No attrition data.** AdventureWorks has no termination dates, so headcount, hires, tenure and pay are reported but attrition is not.
* **On-time delivery is about 99.9%.** Only 7 of 8,845 purchase order lines ship late, all in 2014 for credit-rating-1 vendors, so the metric varies little.
* **Partial years.** 2011 and 2014 are incomplete, so year-over-year growth is blank for 2011 and misleading for 2014.
* **Refresh depends on a local machine.** The data gateway runs on a laptop, so scheduled refresh only works while it is on and online.
* **Full reload on every run.** The warehouse rebuilds all tables each time instead of loading incrementally.
* **Placeholder manager emails** in `UserRegion` (see section 9).

## 12\. Next steps
*- Build the Azure Data Factory pipeline (copy to staging, then run the warehouse load) and schedule it
* Slowly changing dimensions (SCD Type 2) for products, customers and employees
* Incremental refresh on the fact tables
* Historical standard cost for accurate margins
* Add the IBM HR Analytics dataset for a real attrition module
* Move the warehouse and gateway to Azure so refresh does not depend on a laptop
* Data-quality alerts when a test fails

## 13\. Data source

Microsoft AdventureWorks sample databases (AdventureWorks2022).

