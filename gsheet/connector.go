package gsheet

import (
	"context"
	"fmt"
	"os"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/option"
	"google.golang.org/api/sheets/v4"
)

// GetSheetService initializes the Google Sheets API client
func InitSheetService() (*sheets.Service, error) {
	config := &oauth2.Config{
		ClientID:     os.Getenv("CLIENT_ID"),
		ClientSecret: os.Getenv("CLIENT_SECRET"),
		Endpoint:     google.Endpoint,
	}

	token := &oauth2.Token{
		RefreshToken: os.Getenv("FRESH_TOKEN"),
	}

	client := config.Client(context.Background(), token)
	service, err := sheets.NewService(context.Background(), option.WithHTTPClient(client))
	if err != nil {
		return nil, fmt.Errorf("failed to create Sheets service: %w", err)
	}

	return service, nil
}
