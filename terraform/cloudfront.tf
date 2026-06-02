# ==============================================================================
# Amazon CloudFront - CDN e Distribuição Global
# ==============================================================================

# Origin Access Control (OAC) para tráfego seguro entre CloudFront e S3
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.project_name}-s3-oac"
  description                       = "OAC para o bucket privado do frontend S3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 1. Distribuição CloudFront para o Frontend S3 (Interface Gráfica)
resource "aws_cloudfront_distribution" "frontend" {
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-Frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  web_acl_id          = aws_wafv2_web_acl.cloudfront_waf.arn

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-Frontend"

    # Encaminha para o cache padrão (caching ativo)
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Configurações de restrição geográfica (opcional, sem restrição)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Certificado SSL/TLS padrão do CloudFront (*.cloudfront.net)
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# 2. Distribuição CloudFront para a API Gateway (HTTP API Backend)
resource "aws_cloudfront_distribution" "api" {
  origin {
    # Remove o prefixo https:// da URL da API do API Gateway para obter apenas o domínio
    domain_name = replace(aws_apigatewayv2_api.http_api.api_endpoint, "/^https?:\\/\\//", "")
    origin_id   = "APIGateway-Backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  web_acl_id      = aws_wafv2_web_acl.cloudfront_waf.arn

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "APIGateway-Backend"

    # IMPORTANTE: Desativamos o cache para a API para que as requisições cheguem sempre nas Lambdas
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    # Encaminha todas as query strings, cabeçalhos HTTP (Headers) e cookies necessários
    forwarded_values {
      query_string = true
      headers      = ["*"] # Necessário para passar headers do cliente (Auth, Content-Type, CORS, etc.)

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
