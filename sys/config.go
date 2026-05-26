package sys

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"

	"gopkg.in/yaml.v3"
)

// ProductConfig 對應一個產品的整體設定。
// 每個產品下可包含多個報表（reports），共用同一份 GSheet OAuth、DB 與部署設定。
type ProductConfig struct {
	Product string                  `yaml:"product"`
	GSheet  GSheetSection           `yaml:"gsheet"`
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

// GSheetSection 是 Google Sheets API 的 OAuth 憑證。
// 直接寫在 config.yaml 裡，因此 config.yaml 應透過 .gitignore 排除，避免 secret 入 git。
type GSheetSection struct {
	ClientID     string `yaml:"client_id"`
	ClientSecret string `yaml:"client_secret"`
	RefreshToken string `yaml:"refresh_token"`
}

// DBSection 描述 DB 連線設定。
//
//	driver:   sql.Open() 用的 driver 名稱，例如 "postgres"、"mysql"、"sqlserver"。
//	          未指定時預設 "postgres"。
//	conn_str: DB 連線字串（含使用者帳密），直接寫在 config.yaml 裡。
type DBSection struct {
	Driver  string `yaml:"driver"`
	ConnStr string `yaml:"conn_str"`
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

	if cfg.GSheet.ClientID == "" || cfg.GSheet.ClientSecret == "" || cfg.GSheet.RefreshToken == "" {
		return nil, fmt.Errorf("gsheet.{client_id, client_secret, refresh_token} are all required in %s", path)
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
		if cfg.resolveDB(&r).ConnStr == "" {
			return nil, fmt.Errorf("reports.%s: db.conn_str not set and no product-level fallback in %s", name, path)
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
		if report.DB.ConnStr != "" {
			db.ConnStr = report.DB.ConnStr
		}
	}
	if db.Driver == "" {
		db.Driver = "postgres"
	}
	return db
}
