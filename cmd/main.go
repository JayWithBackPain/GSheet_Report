package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/Paktor/Daily-Report-Update/dbquery"
	"github.com/Paktor/Daily-Report-Update/gsheet"
	"github.com/Paktor/Daily-Report-Update/sys"
	"github.com/aws/aws-lambda-go/lambda"

	// Database drivers — 要新增其他 driver，加在這裡並在 config.yaml 設定 db.driver。
	//   _ "github.com/go-sql-driver/mysql"   // driver 名稱: "mysql"
	//   _ "github.com/denisenkom/go-mssqldb" // driver 名稱: "sqlserver"
	_ "github.com/lib/pq" // driver 名稱: "postgres"
)

// LambdaRequest 指定要執行哪一個產品（product）下的哪一份報表（report）。
// 細部參數一律由 config/<product>/config.yaml 內 reports.<report> 提供。
type LambdaRequest struct {
	Product string `json:"product"`
	Report  string `json:"report"`
}

type LambdaResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

func Handler(ctx context.Context, request json.RawMessage) (LambdaResponse, error) {
	var req LambdaRequest
	if err := json.Unmarshal(request, &req); err != nil {
		return LambdaResponse{Success: false, Message: "Invalid request"}, err
	}

	cfg, err := sys.LoadProductConfig(req.Product)
	if err != nil {
		return LambdaResponse{Success: false, Message: "Failed to load product config"}, err
	}
	report, err := cfg.GetReport(req.Report)
	if err != nil {
		return LambdaResponse{Success: false, Message: "Failed to load report config"}, err
	}
	db := cfg.ResolveDB(report)
	log.Printf("[%s/%s] sql_dir=%s, sheet=%s, db.driver=%s, db.conn_env=%s",
		cfg.Product, req.Report, report.SQL.Dir, report.Sheet.Name, db.Driver, db.ConnEnv)

	sheetConfig := gsheet.SheetConfig{
		SheetName:           report.Sheet.Name,
		SpreadSheetID:       report.Sheet.SpreadsheetID,
		WriteAnchor:         report.Sheet.WriteAnchor,
		StartSearchColumn:   report.Sheet.StartSearchColumn,
		QueryParameterRange: report.Sheet.QueryParameterRange,
	}

	SQLCodes, err := sys.LoadSQLFiles(report.SQL.Dir)
	if err != nil {
		return LambdaResponse{Success: false, Message: "Failed to load SQL files"}, err
	}
	if len(SQLCodes) == 0 {
		return LambdaResponse{Success: false, Message: fmt.Sprintf("no SQL files found in %s", report.SQL.Dir)}, nil
	}

	for key, code := range SQLCodes {
		log.Printf("[%s/%s] Processing sql file %s", cfg.Product, req.Report, key)
		QueryResult := dbquery.GetSingleQueryResult(db.Driver, db.ConnEnv, code)
		log.Printf("[%s/%s] Start writing sql %s", cfg.Product, req.Report, key)
		gsheet.WriteTargetDateData(key, sheetConfig, QueryResult)
	}

	return LambdaResponse{
		Success: true,
		Message: fmt.Sprintf("[%s/%s] Sheet Updating Success", cfg.Product, req.Report),
	}, nil
}

func main() {
	if err := sys.LoadEnv(); err != nil {
		log.Printf("Warning: Failed to load .env file: %v", err)
	}

	if os.Getenv("LAMBDA_TASK_ROOT") != "" {
		log.Println("Running in Lambda environment")
		lambda.Start(Handler)
		return
	}

	log.Println("Running in local environment")
	product := os.Getenv("PRODUCT")
	if product == "" {
		product = "younow"
	}
	report := os.Getenv("REPORT")
	if report == "" {
		report = "daily"
	}
	testRequest, _ := json.Marshal(LambdaRequest{Product: product, Report: report})

	response, err := Handler(context.Background(), testRequest)
	if err != nil {
		log.Fatalf("Error in local test: %v", err)
	}
	log.Printf("Local test completed: %s", response.Message)
}
