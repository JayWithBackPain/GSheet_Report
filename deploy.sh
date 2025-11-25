#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Starting deployment process..."

echo "📦 Step 1/3: Building bootstrap binary for AWS Lambda (linux/arm64)..."
GOOS=linux GOARCH=arm64 go build -tags lambda.norpc -o bootstrap ./cmd/main.go
echo "✅ Build completed successfully"

echo "📦 Step 2/3: Packaging artifacts (bootstrap, dev_sql, .env)..."
# 先刪除舊的 zip 檔案，避免包含舊內容
rm -f deployed_package.zip
# 明確只打包需要的檔案和目錄
zip -r deployed_package.zip bootstrap .env dev_sql/
echo "✅ Package created: deployed_package.zip"

echo "📤 Step 3/3: Updating Lambda function code..."
aws lambda update-function-code \
  --function-name daily_kpi_report_by_locale \
  --zip-file fileb://deployed_package.zip \
  --profile younow
echo "✅ Lambda function updated successfully"

echo "🎉 Deployment completed!"