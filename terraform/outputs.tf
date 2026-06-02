output "api_endpoint" {
  description = "Endpoint da API Gateway HTTP (através do CloudFront + WAF)"
  value       = "https://${aws_cloudfront_distribution.api.domain_name}"
}

output "s3_frontend_bucket_name" {
  description = "Nome do bucket S3 do Frontend"
  value       = aws_s3_bucket.frontend.id
}

output "s3_frontend_website_url" {
  description = "URL pública para acessar a aplicação Web (através do CloudFront + WAF)"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "s3_raw_bucket_name" {
  description = "Nome do bucket S3 Raw"
  value       = aws_s3_bucket.raw.id
}

output "s3_imultavel_bucket_name" {
  description = "Nome do bucket S3 Imutável"
  value       = aws_s3_bucket.imultavel.id
}

output "sns_topic_arn" {
  description = "ARN do tópico SNS de notificações"
  value       = aws_sns_topic.notificacoes_cartorio.arn
}

output "cognito_user_pool_id" {
  description = "ID do Cognito User Pool"
  value       = aws_cognito_user_pool.pool.id
}

output "cognito_user_pool_client_id" {
  description = "ID do Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.client.id
}
