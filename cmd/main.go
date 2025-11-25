package main

import (
	"context"
	"log"

	"github.com/Paktor/Daily-Report-Update/dbquery"
	"github.com/Paktor/Daily-Report-Update/gsheet"
	"github.com/Paktor/Daily-Report-Update/sys"
	"github.com/aws/aws-lambda-go/lambda"
	_ "github.com/lib/pq"
)

func test_session() (string, error) {

	SQLCodes := map[string]string{}
	// -------------------------- Get redshift sql codes -----------------------------------
	/*
		SQLCodes, _ = sys.LoadSQLFiles("redshift_sql")
		for key, code := range SQLCodes {
			log.Printf("Processing sql file %s\n", key)
			QueryResult := dbquery.GetSingleQueryResult("RedshiftConnStr", code)
			log.Printf("Start writing sql")
			gsheet.WriteTargetDateData(key, "report", QueryResult)
		}
	*/
	// -------------------------- Get rds sql codes -----------------------------------
	SQLCodes, _ = sys.LoadSQLFiles("dev_sql")
	for key, code := range SQLCodes {
		log.Printf("Processing sql file %s\n", key)
		QueryResult := dbquery.GetSingleQueryResult("RedshiftConnStr", code)
		log.Printf("Start writing sql")
		gsheet.WriteTargetDateData(key, "report", QueryResult)
	}

	return "OK", nil
}

func Handler(ctx context.Context) (string, error) {
	// 1. 直接用 os.Getenv 取得 Lambda 設定的環境變數
	// 2. 不用再讀 .env 檔
	// 3. SQL 檔案直接讀本地（與 binary 同目錄）

	// -------------------------- Get redshift sql codes -----------------------------------
	/*
		SQLCodes, _ := sys.LoadSQLFiles("redshift_traffic_sql")
		for key, code := range SQLCodes {
			log.Printf("Processing sql file %s\n", key)
			QueryResult := dbquery.GetSingleQueryResult("RedshiftConnStr", code)
			log.Printf("Start writing sql")
			gsheet.WriteTargetDateData(key, "Traffic", QueryResult)
		}
	*/
	SQLCodes := map[string]string{}
	// -------------------------- Get rds sql codes -----------------------------------
	SQLCodes, _ = sys.LoadSQLFiles("dev_sql")
	for key, code := range SQLCodes {
		log.Printf("Processing sql file %s\n", key)
		QueryResult := dbquery.GetSingleQueryResult("RedshiftConnStr", code)
		log.Printf("Start writing sql")
		gsheet.WriteTargetDateData(key, "report", QueryResult)
	}
	return "OK", nil
}

func main() {
	// 載入 .env 文件
	if err := sys.LoadEnv(); err != nil {
		log.Printf("Warning: Failed to load .env file: %v", err)
	}

	lambda.Start(Handler)
	//test_session()
}
