# ==============================================================================
# Amazon CloudWatch & AWS CloudTrail - Auditoria e Alertas de Segurança
# ==============================================================================

# 1. Grupo de Logs no CloudWatch para armazenamento de logs do CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail_logs" {
  name              = "/aws/cloudtrail/${var.project_name}-audit-logs"
  retention_in_days = 7
}

# 2. Configuração do AWS CloudTrail para registrar eventos de dados no Bucket Imutável
resource "aws_cloudtrail" "s3_audit_trail" {
  name                          = "${var.project_name}-s3-audit-trail"
  s3_bucket_name                = aws_s3_bucket.trail_logs.id
  include_global_service_events = false
  enable_log_file_validation    = true
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_to_cloudwatch.arn
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail_logs.arn}:*"

  # Habilita o monitoramento dos eventos de dados (escrita e deleção) no Bucket Imutável
  event_selector {
    read_write_type           = "WriteOnly" # Captura apenas gravações e tentativas de exclusão
    include_management_events = false

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.imultavel.arn}/*"]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.trail_logs_policy,
    aws_iam_role_policy.cloudtrail_policy
  ]
}

# 3. Filtro de Métrica do CloudWatch Logs para detectar AccessDenied em Delete
resource "aws_cloudwatch_log_metric_filter" "access_denied_filter" {
  name           = "S3AccessDeniedDeleteAttempts"
  pattern        = "{ ($.eventSource = \"s3.amazonaws.com\") && ($.eventName = \"Delete*\" || $.eventName = \"PutBucketPolicy\") && ($.errorCode = \"AccessDenied\") }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail_logs.name

  metric_transformation {
    name      = "AccessDeniedDeleteCount"
    namespace = "CartorioDigital/Security"
    value     = "1"
  }
}

# 4. Alarme do CloudWatch para disparar alertas via SNS
resource "aws_cloudwatch_metric_alarm" "security_alert_alarm" {
  alarm_name          = "${var.project_name}-unauthorized-delete-alert"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.access_denied_filter.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.access_denied_filter.metric_transformation[0].namespace
  period              = 300 # 5 minutos
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alerta disparado ao detectar tentativas não autorizadas de excluir arquivos ou alterar políticas no Bucket Imutável."
  alarm_actions       = [aws_sns_topic.notificacoes_cartorio.arn]
}
