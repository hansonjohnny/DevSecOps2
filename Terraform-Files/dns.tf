# ─────────────────────────────────────────
# ROUTE 53 HOSTED ZONE
# ─────────────────────────────────────────
resource "aws_route53_zone" "main" {
  name = "johnnycloudops.xyz"

  tags = {
    Name        = "${var.project_name}-hosted-zone"
    Environment = var.environment
  }
}


# ─────────────────────────────────────────
# DATA SOURCE — ALB from Ingress
# ─────────────────────────────────────────
data "aws_lb" "app" {
  tags = {
    "elbv2.k8s.aws/cluster"    = "${var.project_name}-cluster"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }
}


# ─────────────────────────────────────────
# ACM CERTIFICATE
# ─────────────────────────────────────────
resource "aws_acm_certificate" "main" {
  domain_name               = "johnnycloudops.xyz"
  subject_alternative_names = ["www.johnnycloudops.xyz"]
  validation_method         = "DNS"

  tags = {
    Name        = "${var.project_name}-certificate"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}


# ─────────────────────────────────────────
# DNS VALIDATION RECORDS
# ─────────────────────────────────────────
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}


# ─────────────────────────────────────────
# CERTIFICATE VALIDATION
# ─────────────────────────────────────────
resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


# ─────────────────────────────────────────
# ROUTE 53 RECORD — root domain
# ─────────────────────────────────────────
resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "johnnycloudops.xyz"
  type    = "A"

  alias {
    name                   = data.aws_lb.app.dns_name
    zone_id                = data.aws_lb.app.zone_id
    evaluate_target_health = true
  }
}


# ─────────────────────────────────────────
# ROUTE 53 RECORD — www subdomain
# ─────────────────────────────────────────
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.johnnycloudops.xyz"
  type    = "A"

  alias {
    name                   = data.aws_lb.app.dns_name
    zone_id                = data.aws_lb.app.zone_id
    evaluate_target_health = true
  }
}


# ─────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────
output "route53_nameservers" {
  description = "Add these to Namecheap DNS settings"
  value       = aws_route53_zone.main.name_servers
}

output "acm_certificate_arn" {
  description = "Use this ARN in ingress.yaml annotation"
  value       = aws_acm_certificate.main.arn
}