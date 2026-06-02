output "api_endpoint" {
  description = "Endpoint da API Gateway HTTP"
  value       = aws_apigatewayv2_stage.default_stage.invoke_url
}

output "s3_frontend_bucket_name" {
  description = "Nome do bucket S3 do Frontend"
  value       = aws_s3_bucket.frontend.id
}

output "s3_frontend_website_url" {
  description = "URL pública para acessar a aplicação Web"
  value       = "http://${aws_s3_bucket_website_configuration.frontend_website.website_endpoint}"
}

output "s3_raw_bucket_name" {
  description = "Nome do bucket S3 Raw"
  value       = aws_s3_bucket.raw.id
}

output "s3_imultavel_bucket_name" {
  description = "Nome do bucket S3 Imutável"
  value       = aws_s3_bucket.imultavel.id
}

output "github_actions_role_arn" {
  description = "ARN da Role IAM federada que o GitHub Actions deve assumir para fazer deploy"
  value       = aws_iam_role.github_actions_role.arn
}

output "sns_topic_arn" {
  description = "ARN do tópico SNS de notificações"
  value       = aws_sns_topic.notificacoes_cartorio.arn
}
