package gsheet

import (
	"fmt"
	"regexp"
	"strconv"
	"time"
)

// min 函數實現
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// normalizeDate 將各種日期格式統一轉換為 yyyy-mm-dd 格式
// 支援的格式包括：
// - yyyy/mm/dd, yyyy/m/d, yyyy/mm/d, yyyy/m/dd
// - mm/dd/yyyy, m/d/yyyy, mm/d/yyyy, m/dd/yyyy
// - dd/mm/yyyy, d/m/yyyy, dd/m/yyyy, d/mm/yyyy
// - yyyy-mm-dd (已經是目標格式)
// - yyyy-m-d, yyyy-mm-d, yyyy-m-dd
func normalizeDate(dateStr string) string {
	if dateStr == "" {
		return ""
	}

	// 定義多種日期格式嘗試解析
	dateFormats := []string{
		"2006-01-02",  // yyyy-mm-dd (標準格式)
		"2006/01/02",  // yyyy/mm/dd
		"2006/1/2",    // yyyy/m/d
		"01/02/2006",  // mm/dd/yyyy (美式)
		"1/2/2006",    // m/d/yyyy
		"02/01/2006",  // dd/mm/yyyy (歐式)
		"2/1/2006",    // d/m/yyyy
		"2006年1月2日",   // 中文格式 (yyyy年m月d日)
		"2006年01月02日", // 中文格式 (yyyy年mm月dd日)
	}

	// 嘗試解析日期
	for _, format := range dateFormats {
		if t, err := time.Parse(format, dateStr); err == nil {
			// 成功解析，轉換為 yyyy-mm-dd 格式
			return t.Format("2006-01-02")
		}
	}

	// 如果所有格式都無法解析，嘗試手動處理常見的分隔符格式
	// 處理 yyyy/mm/dd 或 yyyy-mm-dd 格式
	if matched := regexp.MustCompile(`^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$`).FindStringSubmatch(dateStr); len(matched) == 4 {
		year := matched[1]
		monthNum, _ := strconv.Atoi(matched[2])
		dayNum, _ := strconv.Atoi(matched[3])
		return fmt.Sprintf("%s-%02d-%02d", year, monthNum, dayNum)
	}

	// 處理 mm/dd/yyyy 格式（假設是美式格式）
	if matched := regexp.MustCompile(`^(\d{1,2})/(\d{1,2})/(\d{4})$`).FindStringSubmatch(dateStr); len(matched) == 4 {
		monthNum, _ := strconv.Atoi(matched[1])
		dayNum, _ := strconv.Atoi(matched[2])
		year := matched[3]
		return fmt.Sprintf("%s-%02d-%02d", year, monthNum, dayNum)
	}

	// 如果無法解析，返回原始字串
	return dateStr
}

// parseCellReference 解析儲存格引用（如 "P3" 或 "M2"），返回欄位字母和行號
// 返回: (columnLetter, rowNumber, error)
func parseCellReference(cellRef string) (string, int, error) {
	// 使用正則表達式匹配儲存格引用格式：字母+數字（如 P3, M2, AA10）
	re := regexp.MustCompile(`^([A-Z]+)(\d+)$`)
	matches := re.FindStringSubmatch(cellRef)
	if len(matches) != 3 {
		return "", 0, fmt.Errorf("invalid cell reference format: %s (expected format like P3 or M2)", cellRef)
	}
	columnLetter := matches[1]
	rowNumber, err := strconv.Atoi(matches[2])
	if err != nil {
		return "", 0, fmt.Errorf("failed to parse row number from cell reference: %s", cellRef)
	}
	return columnLetter, rowNumber, nil
}

// QueriedDataAsserting 將各種類型的查詢結果轉換為 float64
func QueriedDataAsserting(value interface{}) float64 {
	switch v := value.(type) {
	case int:
		return float64(v)
	case int8:
		return float64(v)
	case int16:
		return float64(v)
	case int32:
		return float64(v)
	case int64:
		return float64(v)
	case float32:
		return float64(v)
	case float64:
		return v
	case []byte:
		s := string(v)
		output, _ := strconv.ParseFloat(s, 64)
		return output
	case string:
		// 嘗試解析 string 為 float64
		if num, err := strconv.ParseFloat(v, 64); err == nil {
			return num
		}
	default:
		return 0
	}
	return 0 // 預設返回 0，避免類型不匹配
}
