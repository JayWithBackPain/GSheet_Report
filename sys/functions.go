package sys

import (
	"fmt"
	"io/ioutil"
	"log"
	"path/filepath"
	"strings"

	"github.com/joho/godotenv"
)

// LoadEnv loads environment variables from a .env file
func LoadEnv() error {
	err := godotenv.Load()
	if err != nil {
		return fmt.Errorf("failed to load .env file: %w", err)
	}
	return nil
}

// 數字索引轉換成 A1 格式 (例: 1 -> A, 2 -> B, 27 -> AA)
func ColumnIndexToLetter(index int) string {
	column := ""
	for index > 0 {
		index-- // Google Sheets 是 1-based，但 A-Z 是 0-based
		column = string(rune('A'+(index%26))) + column
		index /= 26
	}
	return column
}

// A1 格式轉換成數字索引 (例: A -> 1, B -> 2, AA -> 27)
func LetterToColumnIndex(letter string) int {
	result := 0
	for _, char := range letter {
		if char >= 'A' && char <= 'Z' {
			result = result*26 + int(char-'A'+1)
		}
	}
	return result
}

func LoadSQLFiles(dir string) (map[string]string, error) {

	sqlMap := make(map[string]string)
	// 讀取目錄內所有檔案
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	for _, file := range files {
		// 確保是 .sql 檔案
		if strings.HasSuffix(file.Name(), ".sql") {
			// 讀取檔案內容
			content, err := ioutil.ReadFile(filepath.Join(dir, file.Name()))
			if err != nil {
				log.Printf("Failed to read file %s: %v", file.Name(), err)
				continue
			}

			// 移除 .sql 副檔名作為 key
			filenameWithoutExt := strings.TrimSuffix(file.Name(), ".sql")
			sqlMap[filenameWithoutExt] = string(content)
		}
	}

	return sqlMap, nil
}
