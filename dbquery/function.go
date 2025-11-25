package dbquery

import (
	"database/sql"
	"log"
	"os"

	"github.com/JayWithBackPain/etl_tool_box/query"
)

func GetNumbers(DB *sql.DB, QueryCodes map[string]string) QueriedData {
	Output := make(QueriedData)
	for k, q := range QueryCodes {
		log.Printf("Traffic Query %s\n", k)
		ThisResult, err := query.Query(DB, q)
		if err != nil {
			log.Fatalf("Fail to query %s\n", k)
		}
		Output[k] = ThisResult
	}
	return Output
}

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
