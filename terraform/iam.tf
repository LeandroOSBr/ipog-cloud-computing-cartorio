data "aws_caller_identity" "current" {}

# ==============================================================================
# 1. Tópico SNS e Inscrição (Notificação por E-mail)
# ==============================================================================
resource "aws_sns_topic" "notificacoes_cartorio" {
  name = "${var.project_name}-notifications"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.notificacoes_cartorio.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# 2. Roles e Políticas para as Lambdas do Backend (API e Leitura)
# ==============================================================================
resource "aws_iam_role" "lambda_api_role" {
  name = "${var.project_name}-lambda-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_api_policy" {
  name = "${var.project_name}-lambda-api-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Permissões de escrita e leitura de logs no CloudWatch
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      # Permissão no S3 para gerar URL Assinada de Upload (PutObject no Raw)
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.raw.arn}/*"
      },
      # Permissões no S3 para listagem e leitura de retenção (List, GetObject, GetObjectRetention)
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw.arn,
          aws_s3_bucket.imultavel.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectRetention"
        ]
        Resource = [
          "${aws_s3_bucket.raw.arn}/*",
          "${aws_s3_bucket.imultavel.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_api_attach" {
  role       = aws_iam_role.lambda_api_role.name
  policy_arn = aws_iam_policy.lambda_api_policy.arn
}

# ==============================================================================
# 3. Roles e Políticas para a Lambda de Processamento (PDF + SNS)
# ==============================================================================
resource "aws_iam_role" "lambda_processor_role" {
  name = "${var.project_name}-lambda-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "lambda_processor_policy" {
  name = "${var.project_name}-lambda-processor-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Logs no CloudWatch
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      # Ler do Bucket RAW
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.raw.arn}/*"
      },
      # Gravar e travar retenção no Bucket Imutável
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectRetention",
          "s3:GetObjectRetention"
        ]
        Resource = "${aws_s3_bucket.imultavel.arn}/*"
      },
      # Disparar alertas via SNS
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.notificacoes_cartorio.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_processor_attach" {
  role       = aws_iam_role.lambda_processor_role.name
  policy_arn = aws_iam_policy.lambda_processor_policy.arn
}

# Role para permitir que o CloudTrail envie logs para o CloudWatch Logs
resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  name = "${var.project_name}-cloudtrail-to-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Política vinculada à Role para gravação de logs
resource "aws_iam_role_policy" "cloudtrail_policy" {
  name = "${var.project_name}-cloudtrail-policy"
  role = aws_iam_role.cloudtrail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailCreateLogStream"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        # Referencia o Log Group do CloudTrail que será criado em monitoring.tf
        Resource = "arn:aws:logs:*:*:log-group:/aws/cloudtrail/${var.project_name}-audit-logs:*"
      }
    ]
  })
}

# A Role 'cartorio-digital-github-actions-deploy-role' é um pré-requisito manual
# para o GitHub OIDC funcionar e deve ser gerenciada fora deste arquivo Terraform
# para evitar dependência circular na pipeline.

