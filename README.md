## 📋 目錄

- [專案簡介](#專案簡介)
- [功能特色](#功能特色)
- [系統架構](#系統架構)
- [高層次流程圖](#高層次流程圖)
- [單元互動流程圖](#單元互動流程圖)
- [專案結構](#專案結構)
- [環境需求](#環境需求)
- [安裝與設定](#安裝與設定)
- [使用方式](#使用方式)
- [配置說明](#配置說明)
- [部署](#部署)

## 專案簡介

GSheet Report 是一個基於 Go 語言開發的 AWS Lambda 函數，主要功能是：

1. 從指定的 SQL 檔案目錄讀取查詢語句
2. 連接到資料庫執行查詢
3. 將查詢結果自動更新到 Google Sheets
4. 支援動態日期欄位對齊和批量寫入

## 功能特色

- ✅ **自動化報表更新**：定期執行 SQL 查詢並更新 Google Sheets
- ✅ **多 SQL 檔案支援**：支援一次處理多個 SQL 檔案
- ✅ **動態日期對齊**：自動識別 Sheet 中的日期欄位並對齊資料
- ✅ **批量寫入優化**：使用 Google Sheets API 批量操作提升效能
- ✅ **環境自動判斷**：自動識別 Lambda 或本地環境
- ✅ **配置化設計**：透過請求參數動態配置 Sheet 設定

## 高層次流程圖

```mermaid
graph TD
    A[開始] --> B{環境判斷}
    B -->|Lambda 環境| C[接收 Lambda 請求]
    B -->|本地環境| D[載入測試請求]
    
    C --> E[解析請求參數]
    D --> E
    
    E --> F[載入 SQL 檔案目錄]
    F --> G{遍歷 SQL 檔案}
    
    G -->|有檔案| H[執行資料庫查詢]
    G -->|無檔案| Z[返回成功]
    
    H --> I[連接 Google Sheets API]
    I --> J[讀取 Sheet 配置]
    J --> K[查找日期欄位位置]
    K --> L[讀取日期標題列]
    L --> M[讀取查詢參數範圍]
    M --> N[處理並對齊資料]
    N --> O[批量清空舊資料]
    O --> P[批量寫入新資料]
    P --> Q{還有 SQL 檔案?}
    
    Q -->|是| H
    Q -->|否| R[返回成功響應]
    R --> Z
    
    style A fill:#e1f5ff
    style Z fill:#c8e6c9
    style H fill:#fff9c4
    style I fill:#fff9c4
    style P fill:#ffccbc
```

## 單元互動流程圖

```mermaid
sequenceDiagram
    participant Lambda as Lambda/本地環境
    participant Main as cmd/main.go
    participant Sys as sys 模組
    participant DB as dbquery 模組
    participant GSheet as gsheet 模組
    participant Redshift as Redshift DB
    participant GoogleAPI as Google Sheets API

    Lambda->>Main: 發送請求 (JSON)
    Main->>Main: 解析 LambdaRequest
    Main->>Main: 轉換為 SheetConfig
    
    Main->>Sys: LoadSQLFiles(sqlDir)
    Sys-->>Main: 返回 SQL 檔案 Map
    
    loop 每個 SQL 檔案
        Main->>DB: GetSingleQueryResult(connStr, sql)
        DB->>Redshift: 執行 SQL 查詢
        Redshift-->>DB: 返回查詢結果
        DB-->>Main: 返回 QueryResults
        
        Main->>GSheet: WriteTargetDateData(key, config, results)
        
        GSheet->>GoogleAPI: InitSheetService()
        GoogleAPI-->>GSheet: 返回 Service
        
        GSheet->>GSheet: findMinDate(results)
        GSheet->>GSheet: findStartColumn(config, minDate)
        GSheet->>GoogleAPI: 讀取日期標題列
        GoogleAPI-->>GSheet: 返回 dateHeaders
        
        GSheet->>GoogleAPI: 讀取查詢參數範圍
        GoogleAPI-->>GSheet: 返回 PointerMap
        
        GSheet->>GSheet: ExtractValue(params, results, headers)
        GSheet->>GSheet: 準備批量更新資料
        
        GSheet->>GoogleAPI: BatchClear(清除範圍)
        GoogleAPI-->>GSheet: 確認清除
        
        GSheet->>GoogleAPI: BatchUpdate(寫入資料)
        GoogleAPI-->>GSheet: 確認寫入
        
        GSheet-->>Main: 寫入完成
    end
    
    Main-->>Lambda: 返回 LambdaResponse
```

## 專案結構

```
GSheet_Report/
├── cmd/
│   └── main.go              # Lambda Handler 和主程式入口
├── dbquery/
│   ├── definitions.go       # 資料查詢相關類型定義
│   └── function.go         # 資料庫查詢函數
├── gsheet/
│   ├── connector.go         # Google Sheets API 連接
│   ├── sheetwriter.go       # Sheet 寫入邏輯
│   ├── utils.go             # 工具函數（日期處理、類型轉換等）
│   └── definitions.go        # Sheet 相關類型定義
├── sys/
│   └── functions.go         # 系統工具函數（SQL 載入、欄位轉換等）
├── dev_sql/                 # SQL 查詢檔案目錄
│   ├── payers.sql
│   └── revenue.sql
├── go.mod                   # Go 模組定義
├── go.sum                   # 依賴版本鎖定
├── deploy.sh                # 部署腳本
└── README.md                # 本文件
```

## 環境需求

- **Go**: 1.23.2 或更高版本
- **AWS Lambda**: 支援 Go runtime
- **資料庫**: PostgreSQL/Redshift
- **Google Cloud**: Google Sheets API 憑證

## 安裝與設定

### 1. Clone Repo

```bash
git clone https://github.com/JayWithBackPain/GSheet_Report.git
cd GSheet_Report
```

### 2. Download packages

```bash
go mod download
```

### 3. 環境變數設定

建立 `.env` 檔案：

```env
# 資料庫連接
RedshiftConnStr=postgresql://user:password@host:port/database

# Google Sheets API 認證
CLIENT_ID=your_client_id
CLIENT_SECRET=your_client_secret
FRESH_TOKEN=your_refresh_token
```

## 使用方式

### Lambda 環境

Lambda 函數接收 JSON 格式的請求：

```json
{
  "sql_dir": "dev_sql",
  "sheet_name": "report",
  "write_anchor": 11,
  "start_search_column": "K2",
  "query_parameter_range": "H:J",
  "spreadsheet_id": "your_spreadsheet_id"
}
```

### 本地測試

直接執行 `main.go`：

```bash
go run cmd/main.go
```

程式會自動判斷環境，本地環境會使用預設的測試請求。

## 配置說明

### LambdaRequest 參數

| 參數 | 類型 | 說明 | 範例 |
|------|------|------|------|
| `sql_dir` | string | SQL 檔案目錄名稱 | `"dev_sql"` |
| `sheet_name` | string | Google Sheet 工作表名稱 | `"report"` |
| `write_anchor` | int | 寫入起始欄位索引 | `11` |
| `start_search_column` | string | 日期搜尋起始儲存格 | `"K2"` |
| `query_parameter_range` | string | 查詢參數範圍 | `"H:J"` |
| `spreadsheet_id` | string | Google Spreadsheet ID | `"1jaq2OJKUio..."` |

### SQL 檔案格式

SQL 檔案應放在指定的目錄中（如 `dev_sql/`），檔案名稱（不含 `.sql` 副檔名）會作為 `SQLKey` 用於匹配 Sheet 中的查詢參數。

查詢結果必須包含以下欄位：
- `dt`: 日期欄位（time.Time 類型）
- `region`: 地區代碼（string 類型）
- 其他需要寫入的數值欄位

### Google Sheet 格式要求

Sheet 需要包含以下結構：

1. **日期標題列**：在指定的 `start_search_column` 行，包含日期欄位
2. **查詢參數範圍**：在 `query_parameter_range` 範圍內，每行包含：
   - 第 1 欄：SQL Key（對應 SQL 檔案名稱）
   - 第 2 欄：Country Code（可選）
   - 第 3 欄：Column Name（要寫入的欄位名稱）

## 部署

### 使用部署腳本

```bash
./deploy.sh
```

## 開發說明

### 模組職責

- **cmd/main.go**: 
  - Lambda Handler 入口
  - 請求解析和路由
  - 環境判斷

- **sys**: 
  - SQL 檔案載入
  - 欄位索引轉換（A1 格式 ↔ 數字索引）
  - 環境變數載入

- **dbquery**: 
  - 資料庫連接管理
  - SQL 查詢執行
  - 結果格式化

- **gsheet**: 
  - Google Sheets API 連接
  - Sheet 讀寫操作
  - 日期格式處理
  - 資料對齊邏輯

### 擴展建議

- 支援更多資料庫類型
- 支援增量更新
- 增加監控和日誌記錄
