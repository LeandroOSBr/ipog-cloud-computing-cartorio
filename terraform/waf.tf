# ==============================================================================
# AWS WAFv2 - Web Application Firewall (Global para CloudFront)
# ==============================================================================

resource "aws_wafv2_web_acl" "cloudfront_waf" {
  name        = "${var.project_name}-cf-waf"
  description = "WAF para protecao do Frontend S3 e Backend API Gateway via CloudFront"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Regra 1: AWS Core Rule Set (CRS - Protege contra OWASP Top 10)
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Regra 2: Proteção contra injeção de SQL (SQLi)
  rule {
    name     = "AWS-AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesSQLiRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  # Configurações de visibilidade no CloudWatch Metrics
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CloudFrontWAFGeneralMetric"
    sampled_requests_enabled   = true
  }
}
