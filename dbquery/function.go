package dbquery

import (
	"database/sql"
	"log"
	"os"

	"github.com/JayWithBackPain/etl_tool_box/query"
)

func GetSingleQueryResult(DB, QueryCodes string) SingleQueriedData {
	DBConnector, err := sql.Open("postgres", os.Getenv(DB))
	if err != nil {
		log.Fatalf("Failed to connect to RedshiftDB: %v", err)
	}
	defer DBConnector.Close()

	ThisResult, err := query.Query(DBConnector, QueryCodes)
	if err != nil {
		log.Fatalf("Fail to query \n")
	}
	return ThisResult
}
