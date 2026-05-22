package dbquery

import (
	"database/sql"
	"log"
	"os"

	"github.com/JayWithBackPain/etl_tool_box/query"
)

// GetSingleQueryResult 用指定的 driver 與環境變數中的連線字串連 DB 並執行查詢。
//
//	driver:  sql.Open() 的 driver 名稱（"postgres"、"mysql" 等）。
//	         若為空字串，會 fallback 為 "postgres"。
//	connEnv: 連線字串對應的環境變數名稱（連線字串本體由該環境變數提供）。
//
// 注意：若要新增 driver，需在 main 套件 import 對應的 driver package，例如：
//
//	import _ "github.com/go-sql-driver/mysql"   // for "mysql"
//	import _ "github.com/denisenkom/go-mssqldb" // for "sqlserver"
func GetSingleQueryResult(driver, connEnv, QueryCodes string) SingleQueriedData {
	if driver == "" {
		driver = "postgres"
	}
	DBConnector, err := sql.Open(driver, os.Getenv(connEnv))
	if err != nil {
		log.Fatalf("Failed to connect to DB (driver=%s, env=%s): %v", driver, connEnv, err)
	}
	defer DBConnector.Close()

	ThisResult, err := query.Query(DBConnector, QueryCodes)
	if err != nil {
		log.Fatalf("Failed to query data from DB: %v", err)
	}
	return ThisResult
}
