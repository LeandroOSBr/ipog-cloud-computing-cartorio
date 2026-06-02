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

    viewer_protocol_policy = "redirect-to-https"
    
    # Usa a política de cache padrão otimizada da AWS para sites estáticos
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
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

    viewer_protocol_policy = "redirect-to-https"

    # Desativa cache na API e encaminha todos os headers, EXCETO o 'Host' para evitar erro 403 no API Gateway
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
    origin_request_policy_id = "b689b0a8-53d0-40b8-8a0a-3450e5539059" # Managed-AllViewerExceptHostHeader
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
