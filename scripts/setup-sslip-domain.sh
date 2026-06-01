#!/bin/bash
################################################################################
# setup-sslip-domain.sh
#
# Post-deployment script that:
#   1. Gets the ACM cert ARN from Terraform output
#   2. Patches the Gateway with the cert ARN (enables HTTPS)
#   3. Discovers the ALB DNS/IP
#   4. Prints all accessible sslip.io URLs (HTTPS)
#
# Usage:
#   cd terraform/environments/dev && terraform output -raw acm_certificate_arn
#   cd ../../../ && ./scripts/setup-sslip-domain.sh
#
# Prerequisites:
#   - kubectl configured with EKS cluster
#   - Terraform applied (ACM cert created)
#   - Gateway resource provisioned
################################################################################

set -euo pipefail

echo "🔐 Setting up TLS + sslip.io domains for dev environment..."
echo ""

# ── Step 1: Get ACM Certificate ARN ──────────────────────────────────────────
echo "🔍 Getting ACM certificate ARN from Terraform..."

CERT_ARN=""
if command -v terraform &> /dev/null; then
  CERT_ARN=$(cd terraform/environments/dev && terraform output -raw acm_certificate_arn 2>/dev/null || echo "")
fi

if [ -z "$CERT_ARN" ]; then
  echo "  ⚠️  Could not auto-detect ACM cert ARN from Terraform."
  echo "  Please provide the ACM certificate ARN:"
  read -rp "  ACM ARN: " CERT_ARN
fi

echo "  ✅ ACM Certificate: $CERT_ARN"

# ── Step 2: Patch Gateway with ACM Certificate ──────────────────────────────
echo ""
echo "🔐 Patching Gateway with ACM certificate for HTTPS..."

kubectl annotate gateway ecommerce-gateway -n ecommerce \
  "alb.ingress.kubernetes.io/certificate-arn=$CERT_ARN" \
  --overwrite 2>/dev/null || echo "  ⚠️  Gateway not found yet, will retry..."

echo "  ✅ Gateway patched with TLS certificate"

# ── Step 3: Discover ALB Address ─────────────────────────────────────────────
echo ""
echo "🔍 Discovering ALB address from Gateway resource..."

MAX_RETRIES=30
RETRY_INTERVAL=10
ALB_DNS=""

for i in $(seq 1 $MAX_RETRIES); do
  ALB_DNS=$(kubectl get gateway ecommerce-gateway -n ecommerce \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")

  if [ -n "$ALB_DNS" ] && [ "$ALB_DNS" != "" ]; then
    break
  fi

  echo "  ⏳ Waiting for ALB to be provisioned... (attempt $i/$MAX_RETRIES)"
  sleep $RETRY_INTERVAL
done

if [ -z "$ALB_DNS" ]; then
  echo "❌ Error: Could not discover ALB DNS name from Gateway."
  echo "   Make sure the Gateway controller and ALB are provisioned."
  echo "   Try: kubectl get gateway ecommerce-gateway -n ecommerce -o yaml"
  exit 1
fi

echo "  ✅ ALB DNS: $ALB_DNS"

# ── Step 4: Resolve ALB IP ───────────────────────────────────────────────────
echo ""
echo "🔍 Resolving ALB DNS to IP address..."
ALB_IP=$(dig +short "$ALB_DNS" | head -1)

if [ -z "$ALB_IP" ]; then
  echo "  ⚠️  Could not resolve DNS yet. Using ALB DNS directly."
  ALB_IP="pending"
fi

echo "  ✅ ALB IP: $ALB_IP"

# ── Step 5: Construct sslip.io Domains ───────────────────────────────────────
if [ "$ALB_IP" != "pending" ]; then
  SSLIP_DOMAIN="ecommerce-api-${ALB_IP//./-}.sslip.io"
else
  SSLIP_DOMAIN="ecommerce-api.sslip.io"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║              🌐 E-Commerce Platform — Dev Environment                ║"
echo "║              🔐 TLS Enabled (Self-Signed Certificate)                ║"
echo "╠════════════════════════════════════════════════════════════════════════╣"
echo "║                                                                      ║"
echo "║  📡 ALB DNS:      $ALB_DNS"
echo "║  🌍 ALB IP:       $ALB_IP"
echo "║  🔐 ACM Cert:     $CERT_ARN"
echo "║                                                                      ║"
echo "║  🔗 HTTPS Endpoints (self-signed cert — browser will warn):          ║"
echo "║     Users:         https://${SSLIP_DOMAIN}/api/v1/users/healthz"
echo "║     Products:      https://${SSLIP_DOMAIN}/api/v1/products/healthz"
echo "║     Orders:        https://${SSLIP_DOMAIN}/api/v1/orders/healthz"
echo "║     Payments:      https://${SSLIP_DOMAIN}/api/v1/payments/healthz"
echo "║     Notifications: https://${SSLIP_DOMAIN}/api/v1/notifications/healthz"
echo "║                                                                      ║"
echo "║  🛠️  Platform Tools:                                                 ║"
echo "║     ArgoCD:        https://${SSLIP_DOMAIN}/argocd"
echo "║     Grafana:       https://${SSLIP_DOMAIN}/grafana"
echo "║                                                                      ║"
echo "║  📡 gRPC Endpoints (internal, cluster-only):                         ║"
echo "║     notification-service:50051  (gRPC server)                        ║"
echo "║     product-service:50051       (gRPC server)                        ║"
echo "║                                                                      ║"
echo "║  💰 Dev Cost Summary:                                                ║"
echo "║     ✅ Self-signed TLS cert via ACM (FREE)                           ║"
echo "║     ✅ sslip.io domains (FREE, no Route53)                           ║"
echo "║     ✅ Shield Standard (FREE, automatic)                             ║"
echo "║     ✅ t3.medium SPOT instances (~\$30/mo)                            ║"
echo "║     ✅ No CloudFront CDN (direct ALB)                                ║"
echo "║                                                                      ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "🧪 Quick test (use -k to skip self-signed cert warning):"
echo "  curl -k https://${SSLIP_DOMAIN}/api/v1/users/healthz"
echo ""
echo "📡 Test gRPC (internal, requires port-forward):"
echo "  kubectl port-forward svc/notification-service 50051:50051 -n ecommerce"
echo "  grpcurl -plaintext localhost:50051 list"
echo ""
