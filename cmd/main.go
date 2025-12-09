package main

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"github.com/Paktor/Daily-Report-Update/dbquery"
	"github.com/Paktor/Daily-Report-Update/gsheet"
	"github.com/Paktor/Daily-Report-Update/sys"
	"github.com/aws/aws-lambda-go/lambda"
	_ "github.com/lib/pq"
)

type LambdaRequest struct {
	SQLDir              string `json:"sql_dir"`               // SQL 檔案目錄名稱，例如 "dev_sql"
	SheetName           string `json:"sheet_name"`            // Google Sheet 名稱，例如 "report"
	WriteAnchor         int    `json:"write_anchor"`          // Google Sheet 寫入位置
	StartSearchColumn   string `json:"start_search_column"`   // Google Sheet 寫入位置
	QueryParameterRange string `json:"query_parameter_range"` // Google Sheet 寫入位置
	SpreadSheetID       string `json:"spreadsheet_id"`        // Google Sheet ID
}

type LambdaResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
}

func Handler(ctx context.Context, request json.RawMessage) (LambdaResponse, error) {

	var req LambdaRequest
	if err := json.Unmarshal(request, &req); err != nil {
		return LambdaResponse{
			Success: false,
			Message: "Invalid request",
		}, err
	}

	sheetConfig := gsheet.SheetConfig{
		SheetName:           req.SheetName,
		SpreadSheetID:       req.SpreadSheetID,
		WriteAnchor:         req.WriteAnchor,
		StartSearchColumn:   req.StartSearchColumn,
		QueryParameterRange: req.QueryParameterRange,
	}

	SQLCodes := map[string]string{}
	// -------------------------- Get rds sql codes -----------------------------------
	SQLCodes, _ = sys.LoadSQLFiles(req.SQLDir)
	for key, code := range SQLCodes {
		log.Printf("Processing sql file %s\n", key)
		QueryResult := dbquery.GetSingleQueryResult("RedshiftConnStr", code)
		log.Printf("Start writing sql")
		gsheet.WriteTargetDateData(key, sheetConfig, QueryResult)
	}

	response := LambdaResponse{
		Success: true,
		Message: "Sheet Updating Success",
	}
	return response, nil
}

func main() {
	// 載入 .env 文件
	if err := sys.LoadEnv(); err != nil {
		log.Printf("Warning: Failed to load .env file: %v", err)
	}

	// 自動判斷執行環境：檢查是否在 Lambda 環境中
	// Lambda 環境會有 AWS_LAMBDA_FUNCTION_NAME 或 LAMBDA_TASK_ROOT 環境變數
	if os.Getenv("LAMBDA_TASK_ROOT") != "" {
		// Lambda 環境：使用 Lambda handler
		log.Println("Running in Lambda environment")
		lambda.Start(Handler)
	} else {
		// 本地環境：直接執行測試
		log.Println("Running in local environment")

		test_request := json.RawMessage(`
		{
			"sql_dir":               "dev_sql",
			"sheet_name":            "report",
			"write_anchor":          11,
			"start_search_column":   "K2",
			"query_parameter_range": "H:J",
			"spreadsheet_id":        "1jaq2OJKUioWb0Q6t_ft-ZEB6G60ykdXx8ryBJ3sICFs"
		}`)
		response, err := Handler(context.Background(), test_request)
		if err != nil {
			log.Fatalf("Error in local test: %v", err)
		}
		log.Printf("Local test completed: %s", response.Message)
	}
}
