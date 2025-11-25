package gsheet

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"github.com/Paktor/Daily-Report-Update/sys"
	"google.golang.org/api/sheets/v4"
)

// findStartColumn 從指定的起始儲存格開始搜尋，找到與最小日期匹配的欄位
// START_SEARCH_COLUMN 環境變數應為儲存格引用格式（如 "P3" 或 "M2"）
func findStartColumn(GSheetService *sheets.Service, SpreadSheetID, CurrentSheet string, minDate time.Time) (int, int, error) {
	startSearchCell := os.Getenv("START_SEARCH_COLUMN")
	if startSearchCell == "" {
		return 0, 0, fmt.Errorf("START_SEARCH_COLUMN environment variable is not set")
	}

	// 解析儲存格引用（如 "P3" -> column="P", row=3）
	columnLetter, rowNumber, err := parseCellReference(startSearchCell)
	if err != nil {
		return 0, 0, fmt.Errorf("failed to parse START_SEARCH_COLUMN: %v", err)
	}

	// 從指定儲存格開始往右搜尋到 ZZ（可以根據需要調整終點欄位）
	searchRange := fmt.Sprintf("%s!%s%d:ZZ%d", CurrentSheet, columnLetter, rowNumber, rowNumber)
	searchResult, err := GSheetService.Spreadsheets.Values.Get(SpreadSheetID, searchRange).Do()
	if err != nil {
		return 0, 0, fmt.Errorf("failed to get search range: %v", err)
	}

	// 檢查是否有資料
	if len(searchResult.Values) == 0 || len(searchResult.Values[0]) == 0 {
		// 如果沒有找到資料，使用預設的 WRITEANCHOR
		d2ColumnIndex, _ := strconv.Atoi(os.Getenv("WRITEANCHOR"))
		return d2ColumnIndex, rowNumber, nil
	}

	startColIndex := sys.LetterToColumnIndex(columnLetter)

	// 搜尋匹配的日期
	for i, cell := range searchResult.Values[0] {
		if cellStr, ok := cell.(string); ok {
			// 統一轉換日期格式為 yyyy-mm-dd，然後比較
			normalizedDateStr := normalizeDate(cellStr)
			if parsedDate, err := time.Parse("2006-01-02", normalizedDateStr); err == nil {
				if parsedDate.Equal(minDate) {
					return startColIndex + i, rowNumber, nil
				}
			}
		}
	}

	// 如果沒有找到匹配的日期，使用預設的 WRITEANCHOR
	d2ColumnIndex, _ := strconv.Atoi(os.Getenv("WRITEANCHOR"))
	return d2ColumnIndex, rowNumber, nil
}

func WriteTargetDateData(SQLKey string, CurrentSheet string, QueryResults []map[string]interface{}) {
	// ----- 連接 google sheet server ------------------------------
	GSheetService, err := InitSheetService()
	if err != nil {
		log.Fatalf("Failed to initialize google sheet service: %v", err)
	}
	SpreadSheetID := os.Getenv("DAILY_REPORT_SPREADSHEET_ID")
	// ----- 定義 sheet name ------------------------------
	//CurrentSheet := os.Getenv("SHEET_NAME")
	// ----- 找到最小日期並確定起始欄位 ------------------------------
	var minDate time.Time
	if len(QueryResults) > 0 {
		minDate = QueryResults[0]["dt"].(time.Time)
		for _, row := range QueryResults {
			if dt := row["dt"].(time.Time); dt.Before(minDate) {
				minDate = dt
			}
		}
	}

	// 動態找到起始欄位
	d2ColumnIndex, dateRowNumber, err := findStartColumn(GSheetService, SpreadSheetID, CurrentSheet, minDate)
	if err != nil {
		log.Printf("Warning: Failed to find start column, using default: %v", err)
		d2ColumnIndex, _ = strconv.Atoi(os.Getenv("WRITEANCHOR"))
		// 如果解析失敗，嘗試從 START_SEARCH_COLUMN 獲取行號，否則預設為第3行
		startSearchCell := os.Getenv("START_SEARCH_COLUMN")
		if startSearchCell != "" {
			_, parsedRowNumber, parseErr := parseCellReference(startSearchCell)
			if parseErr != nil {
				dateRowNumber = 3 // 預設為第3行
			} else {
				dateRowNumber = parsedRowNumber
			}
		} else {
			dateRowNumber = 3 // 預設為第3行
		}
	}

	log.Printf("Using start column index: %d (min date: %s, date row: %d)", d2ColumnIndex, minDate.Format("2006-01-02"), dateRowNumber)

	// 讀取 Google Sheet 上的日期欄位（使用動態行號）
	dateRowRange := fmt.Sprintf("%s!%s%d:zz%d", CurrentSheet, sys.ColumnIndexToLetter(d2ColumnIndex), dateRowNumber, dateRowNumber)
	dateRow, err := GSheetService.Spreadsheets.Values.Get(SpreadSheetID, dateRowRange).Do()

	if err != nil || len(dateRow.Values) == 0 {
		log.Fatalf("Failed to read date row from sheet: %v", err)
	}
	var dateHeaders []string

	for _, cell := range dateRow.Values[0] {
		if s, ok := cell.(string); ok {
			// 自動識別並統一轉換日期格式為 yyyy-mm-dd
			normalizedDate := normalizeDate(s)
			dateHeaders = append(dateHeaders, normalizedDate)
		} else {
			dateHeaders = append(dateHeaders, "")
		}
	}

	// 調試：輸出讀取到的日期欄位
	//log.Printf("Read date headers from sheet: %v", dateHeaders)
	//log.Printf("Date headers count: %d", len(dateHeaders))

	// ----- 掃 Metrics Label ------------------------------
	queryParameterRange := os.Getenv("QUERY_PARAMETER_RANGE")
	if queryParameterRange == "" {
		log.Fatalf("QUERY_PARAMETER_RANGE environment variable is not set")
	}
	PointerRange := fmt.Sprintf("%s!%s", CurrentSheet, queryParameterRange)
	PointerMap, err := GSheetService.Spreadsheets.Values.Get(os.Getenv("DAILY_REPORT_SPREADSHEET_ID"), PointerRange).Do()
	// 存放批量寫入的數據
	var dataUpdates []*sheets.ValueRange
	// 存放批量清空的範圍（ClearRange）
	var clearRanges []string

	RowWritten := 0
	for i, row := range PointerMap.Values {
		if len(row) != 3 || row[0].(string) != SQLKey {
			continue
		}
		RowWritten++
		QueryParameters := make(map[string]string)
		if row[1] != "" {
			QueryParameters["CountryCode"] = row[1].(string)
		}
		if row[2] != "" {
			QueryParameters["ColumnName"] = row[2].(string)
		}

		GetValue := ExtractValue(QueryParameters, QueryResults, dateHeaders)

		// 找到有資料的起始與結束 index
		startIdx, endIdx := -1, -1
		for j, val := range GetValue {
			if val != "" && val != nil {
				if startIdx == -1 {
					startIdx = j
				}
				endIdx = j
			}
		}
		if startIdx == -1 || endIdx == -1 {
			log.Printf("Row %d: 無資料可寫入，跳過 UpdateRange", i+1)
			continue
		}
		// 只取有資料的那一段 slice
		writeValues := GetValue[startIdx : endIdx+1]
		// 計算對應的欄位
		writeColIndex := d2ColumnIndex + startIdx
		UpdateRange := fmt.Sprintf("%s!%s%d", CurrentSheet, sys.ColumnIndexToLetter(writeColIndex), i+1)

		// 準備清空範圍（從 writeColIndex 開始，長度為 dateHeaders）
		endClearColIndex := writeColIndex + len(dateHeaders) - 1
		ClearRange := fmt.Sprintf("%s!%s%d:%s%d", CurrentSheet, sys.ColumnIndexToLetter(writeColIndex), i+1, sys.ColumnIndexToLetter(endClearColIndex), i+1)
		clearRanges = append(clearRanges, ClearRange)
		//log.Printf("即將寫入 UpdateRange: %s, writeValues: %v", UpdateRange, writeValues)
		// 存入批量更新
		dataUpdates = append(dataUpdates, &sheets.ValueRange{
			Range:  UpdateRange,
			Values: [][]interface{}{writeValues},
		})
	}
	// 先批量清空目標範圍，再一次性批量寫入 Google Sheet
	if len(dataUpdates) > 0 {
		if len(clearRanges) > 0 {
			log.Printf("Preparing to batch clear %d ranges", len(clearRanges))
			_, err := GSheetService.Spreadsheets.Values.BatchClear(SpreadSheetID, &sheets.BatchClearValuesRequest{
				Ranges: clearRanges,
			}).Do()
			if err != nil {
				log.Fatalf("Failed to batch clear ranges: %v", err)
			}
			log.Printf("Batch clear completed successfully")
		}
		log.Printf("Preparing to batch update %d operations", len(dataUpdates))

		// 調試：輸出每個操作的詳細資訊
		for i, update := range dataUpdates {
			log.Printf("Operation %d: Range=%s, Values count=%d", i+1, update.Range, len(update.Values))
			if len(update.Values) > 0 {
				log.Printf("  First few values: %v", update.Values[0][:min(5, len(update.Values[0]))])
				if len(update.Values[0]) > 5 {
					log.Printf("  Last few values: %v", update.Values[0][len(update.Values[0])-5:])
				}
			}
		}

		batchRequest := &sheets.BatchUpdateValuesRequest{
			ValueInputOption: "USER_ENTERED",
			Data:             dataUpdates,
		}

		_, err = GSheetService.Spreadsheets.Values.BatchUpdate(SpreadSheetID, batchRequest).Do()
		if err != nil {
			log.Fatalf("Failed to batch update data: %v", err)
		}

		log.Printf("Batch update completed successfully")
	}

	log.Printf("Successfully wrote in %d rows\n", RowWritten)
}

// ExtractValue 依據 sheet 日期欄位順序對齊填值
func ExtractValue(QueryParameters map[string]string, QueryResults []map[string]interface{}, dateHeaders []string) []interface{} {
	// 先將查詢結果轉成 map[日期字串]value
	ColumnName := QueryParameters["ColumnName"]
	CountryCode := QueryParameters["CountryCode"]

	// 調試：輸出查詢參數
	//log.Printf("ExtractValue - CountryCode: %s, ColumnName: %s", CountryCode, ColumnName)
	//log.Printf("QueryResults count: %d", len(QueryResults))

	valueMap := make(map[string]interface{})
	for _, row := range QueryResults {
		regionVal, ok := row["region"].(string)
		if !ok || regionVal != CountryCode {
			continue
		}
		dt, ok := row["dt"].(time.Time)
		if !ok {
			continue
		}
		val, exists := row[ColumnName]
		if !exists {
			continue
		}
		dateStr := dt.Format("2006-01-02")
		valueMap[dateStr] = QueriedDataAsserting(val)
		//log.Printf("Found data for date %s: %v", dateStr, QueriedDataAsserting(val))
	}

	// 依照 dateHeaders 順序組成 slice
	result := make([]interface{}, len(dateHeaders))
	for i, d := range dateHeaders {
		if v, ok := valueMap[d]; ok {
			result[i] = v
		} else {
			result[i] = ""
		}
	}
	return result
}
