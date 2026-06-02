# 1. Bucket Raw (Entrada de PDFs originais)
resource "aws_s3_bucket" "raw" {
  bucket        = "${var.project_name}-raw-${random_id.bucket_suffix.hex}"
  force_destroy = true # Facilita a limpeza do ambiente de demonstração
}

# Configuração de CORS no Bucket Raw para permitir PUT do navegador via pre-signed URL
resource "aws_s3_bucket_cors_configuration" "raw_cors" {
  bucket = aws_s3_bucket.raw.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "HEAD"]
    allowed_origins = ["*"] # Em produção, restrinja à URL do frontend
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# 2. Bucket Imutável (Armazenamento em conformidade com Provimento 213/2026)
resource "aws_s3_bucket" "imultavel" {
  bucket              = "${var.project_name}-imultavel-${random_id.bucket_suffix.hex}"
  object_lock_enabled = true
  force_destroy       = false # Não permite deletar o bucket se houver objetos bloqueados pelo Object Lock
}

# O Versionamento é obrigatório para o funcionamento do S3 Object Lock
resource "aws_s3_bucket_versioning" "imultavel_versioning" {
  bucket = aws_s3_bucket.imultavel.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Regra padrão do Object Lock: Modo COMPLIANCE por 1 dia (para fins de demonstração)
# IMPORTANTE: No modo COMPLIANCE, nem mesmo o usuário root da AWS pode burlar ou deletar o arquivo antes do prazo
resource "aws_s3_bucket_object_lock_configuration" "imultavel_lock" {
  bucket = aws_s3_bucket.imultavel.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.imultavel_versioning]
}

# 3. Bucket Frontend (Privado - Acessado apenas via CloudFront CDN)
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_name}-frontend-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

# Bloqueia todo o acesso público direto ao bucket
resource "aws_s3_bucket_public_access_block" "frontend_public" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Política do Bucket para permitir leitura apenas ao CloudFront OAC
resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket     = aws_s3_bucket.frontend.id
  depends_on = [aws_s3_bucket_public_access_block.frontend_public]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipalReadOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}
