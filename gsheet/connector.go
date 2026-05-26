package gsheet

import (
	"context"
	"fmt"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/option"
	"google.golang.org/api/sheets/v4"
)

// InitSheetService 用呼叫端提供的 OAuth client/refresh token 初始化 Google Sheets API 客戶端。
// 不再從環境變數讀取，避免 secret 透過全域狀態擴散；secret 由 ProductConfig 統一管理。
func InitSheetService(clientID, clientSecret, refreshToken string) (*sheets.Service, error) {
	if clientID == "" || clientSecret == "" || refreshToken == "" {
		return nil, fmt.Errorf("missing Google OAuth credentials (client_id/client_secret/refresh_token)")
	}

	cfg := &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		Endpoint:     google.Endpoint,
	}
	token := &oauth2.Token{RefreshToken: refreshToken}

	ctx := context.Background()
	client := cfg.Client(ctx, token)
	service, err := sheets.NewService(ctx, option.WithHTTPClient(client))
	if err != nil {
		return nil, fmt.Errorf("failed to create Sheets service: %w", err)
	}
	return service, nil
}
