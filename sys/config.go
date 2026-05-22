package sys

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"

	"gopkg.in/yaml.v3"
)

// ProductConfig 對應一個產品的整體設定。
// 每個產品下可包含多個報表（reports），共用同一份 DB 與部署設定。
type ProductConfig struct {
	Product string                  `yaml:"product"`
	DB      DBSection               `yaml:"db"`
	Deploy  DeploySection           `yaml:"deploy"`
	Reports map[string]ReportConfig `yaml:"reports"`
}

// ReportConfig 對應一個報表（report）的設定，例如 daily / weekly / monthly。
// DB 為選填；未指定時會 fallback 到 ProductConfig.DB。
type ReportConfig struct {
	Sheet SheetSection `yaml:"sheet"`
	SQL   SQLSection   `yaml:"sql"`
	DB    *DBSection   `yaml:"db,omitempty"`
}

type SheetSection struct {
	Name                string `yaml:"name"`
	SpreadsheetID       string `yaml:"spreadsheet_id"`
	WriteAnchor         int    `yaml:"write_anchor"`
	StartSearchColumn   string `yaml:"start_search_column"`
	QueryParameterRange string `yaml:"query_parameter_range"`
}

type SQLSection struct {
	Dir string `yaml:"dir"`
}

// DBSection 描述 DB 連線設定。
//
//	driver:   sql.Open() 用的 driver 名稱，例如 "postgres"、"mysql"、"sqlserver"。
//	          未指定時預設 "postgres"。
//	conn_env: 從哪個環境變數讀取連線字串（連線字串本體不入 git）。
type DBSection struct {
	Driver  string `yaml:"driver"`
	ConnEnv string `yaml:"conn_env"`
}

// DeploySection 僅供 deploy.sh / 部署工具使用，Lambda runtime 可忽略
type DeploySection struct {
	FunctionName string `yaml:"function_name"`
	LambdaRole   string `yaml:"lambda_role"`
	Architecture string `yaml:"architecture"`
	Timeout      int    `yaml:"timeout"`
	MemorySize   int    `yaml:"memory_size"`
	Region       string `yaml:"region"`
	AWSProfile   string `yaml:"aws_profile"`
}

var safeNamePattern = regexp.MustCompile(`^[A-Za-z0-9_-]+$`)

// LoadProductConfig 依產品名稱載入 config/<product>/config.yaml。
// 為避免 path traversal，product 僅允許英數字、底線與連字號。
func LoadProductConfig(product string) (*ProductConfig, error) {
	if product == "" {
		return nil, fmt.Errorf("product is required")
	}
	if !safeNamePattern.MatchString(product) {
		return nil, fmt.Errorf("invalid product name: %q", product)
	}

	path := filepath.Join("config", product, "config.yaml")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read config %s: %w", path, err)
	}

	var cfg ProductConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config %s: %w", path, err)
	}
	if cfg.Product == "" {
		cfg.Product = product
	}
	if len(cfg.Reports) == 0 {
		return nil, fmt.Errorf("no reports defined in %s", path)
	}
	for name, r := range cfg.Reports {
		if r.SQL.Dir == "" {
			return nil, fmt.Errorf("reports.%s.sql.dir missing in %s", name, path)
		}
		if r.Sheet.SpreadsheetID == "" {
			return nil, fmt.Errorf("reports.%s.sheet.spreadsheet_id missing in %s", name, path)
		}
		// 確保至少能 resolve 出 conn_env（report > product fallback）
		if cfg.resolveDB(&r).ConnEnv == "" {
			return nil, fmt.Errorf("reports.%s: db.conn_env not set and no product-level fallback in %s", name, path)
		}
	}
	return &cfg, nil
}

// GetReport 依名稱取出對應的 ReportConfig，找不到時回傳錯誤。
func (c *ProductConfig) GetReport(name string) (*ReportConfig, error) {
	if name == "" {
		return nil, fmt.Errorf("report is required")
	}
	if !safeNamePattern.MatchString(name) {
		return nil, fmt.Errorf("invalid report name: %q", name)
	}
	r, ok := c.Reports[name]
	if !ok {
		return nil, fmt.Errorf("report %q not found in product %q", name, c.Product)
	}
	return &r, nil
}

// ResolveDB 依「report 層級 > product 層級 > 預設值」決定該 report 實際要使用的 DB 設定。
// driver 預設為 "postgres"。
func (c *ProductConfig) ResolveDB(report *ReportConfig) DBSection {
	return c.resolveDB(report)
}

func (c *ProductConfig) resolveDB(report *ReportConfig) DBSection {
	db := c.DB
	if report != nil && report.DB != nil {
		if report.DB.Driver != "" {
			db.Driver = report.DB.Driver
		}
		if report.DB.ConnEnv != "" {
			db.ConnEnv = report.DB.ConnEnv
		}
	}
	if db.Driver == "" {
		db.Driver = "postgres"
	}
	return db
}
