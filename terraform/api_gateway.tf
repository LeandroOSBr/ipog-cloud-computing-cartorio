# ==============================================================================
# 1. Configuração do API Gateway (HTTP API)
# ==============================================================================
resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  # Configuração global de CORS para permitir requisições seguras do Frontend S3
  cors_configuration {
    allow_headers = ["content-type", "authorization"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"] # Em produção, restrinja à URL do bucket de frontend
    max_age       = 300
  }
}

# Stage default (implantação automática de alterações)
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# ==============================================================================
# 2. Integrações de Proxy com AWS Lambda
# ==============================================================================

# Integração para a Lambda get_presigned_url
resource "aws_apigatewayv2_integration" "presigned_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"

  integration_uri        = aws_lambda_function.get_presigned_url.arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Integração para a Lambda list_files
resource "aws_apigatewayv2_integration" "list_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"

  integration_uri        = aws_lambda_function.list_files.arn
  integration_method     = "POST" # O método interno de integração para Lambdas sempre é POST
  payload_format_version = "2.0"
}

# ==============================================================================
# 3. Rotas da API
# ==============================================================================

# Rota POST /presigned-url
resource "aws_apigatewayv2_route" "presigned_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /presigned-url"
  target    = "integrations/${aws_apigatewayv2_integration.presigned_integration.id}"
}

# Rota GET /files
resource "aws_apigatewayv2_route" "list_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /files"
  target    = "integrations/${aws_apigatewayv2_integration.list_integration.id}"
}

# ==============================================================================
# 4. Permissões de Execução (API Gateway -> Lambda)
# ==============================================================================

# Permite o API Gateway invocar a Lambda get_presigned_url
resource "aws_lambda_permission" "allow_api_gw_presigned" {
  statement_id  = "AllowAPIGatewayToInvokePresigned"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*/presigned-url"
}

# Permite o API Gateway invocar a Lambda list_files
resource "aws_lambda_permission" "allow_api_gw_list" {
  statement_id  = "AllowAPIGatewayToInvokeList"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_files.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*/files"
}
