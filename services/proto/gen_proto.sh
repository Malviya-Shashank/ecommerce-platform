#!/bin/bash
################################################################################
# Generate Python gRPC stubs from .proto files
#
# Usage: ./gen_proto.sh
# Prerequisites: pip install grpcio-tools
#
# This generates:
#   - *_pb2.py      (protobuf message classes)
#   - *_pb2_grpc.py (gRPC service stubs and servicers)
#
# Generated files are placed in each service's src/generated/ directory.
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTO_DIR="$SCRIPT_DIR"
SERVICES_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔧 Generating gRPC Python stubs from proto files..."

# ── Notification Service stubs ────────────────────────────────────────────────
NOTIF_OUT="$SERVICES_DIR/notification-service/src/generated"
mkdir -p "$NOTIF_OUT"
touch "$NOTIF_OUT/__init__.py"

python3 -m grpc_tools.protoc \
  -I"$PROTO_DIR" \
  --python_out="$NOTIF_OUT" \
  --grpc_python_out="$NOTIF_OUT" \
  "$PROTO_DIR/notification.proto"

# Fix relative imports in generated gRPC file
sed -i.bak 's/^import notification_pb2/from . import notification_pb2/' "$NOTIF_OUT/notification_pb2_grpc.py" 2>/dev/null || \
sed -i '' 's/^import notification_pb2/from . import notification_pb2/' "$NOTIF_OUT/notification_pb2_grpc.py"
rm -f "$NOTIF_OUT/"*.bak

echo "  ✅ notification-service stubs generated"

# ── User Service stubs (notification client) ──────────────────────────────────
USER_OUT="$SERVICES_DIR/user-service/src/generated"
mkdir -p "$USER_OUT"
touch "$USER_OUT/__init__.py"

python3 -m grpc_tools.protoc \
  -I"$PROTO_DIR" \
  --python_out="$USER_OUT" \
  --grpc_python_out="$USER_OUT" \
  "$PROTO_DIR/notification.proto"

sed -i.bak 's/^import notification_pb2/from . import notification_pb2/' "$USER_OUT/notification_pb2_grpc.py" 2>/dev/null || \
sed -i '' 's/^import notification_pb2/from . import notification_pb2/' "$USER_OUT/notification_pb2_grpc.py"
rm -f "$USER_OUT/"*.bak

echo "  ✅ user-service stubs generated (notification client)"

# ── Product Service stubs ─────────────────────────────────────────────────────
PROD_OUT="$SERVICES_DIR/product-service/src/generated"
mkdir -p "$PROD_OUT"
touch "$PROD_OUT/__init__.py"

python3 -m grpc_tools.protoc \
  -I"$PROTO_DIR" \
  --python_out="$PROD_OUT" \
  --grpc_python_out="$PROD_OUT" \
  "$PROTO_DIR/product.proto"

sed -i.bak 's/^import product_pb2/from . import product_pb2/' "$PROD_OUT/product_pb2_grpc.py" 2>/dev/null || \
sed -i '' 's/^import product_pb2/from . import product_pb2/' "$PROD_OUT/product_pb2_grpc.py"
rm -f "$PROD_OUT/"*.bak

echo "  ✅ product-service stubs generated"

# ── Order Service stubs (product + notification clients) ──────────────────────
ORDER_OUT="$SERVICES_DIR/order-service/src/generated"
mkdir -p "$ORDER_OUT"
touch "$ORDER_OUT/__init__.py"

python3 -m grpc_tools.protoc \
  -I"$PROTO_DIR" \
  --python_out="$ORDER_OUT" \
  --grpc_python_out="$ORDER_OUT" \
  "$PROTO_DIR/product.proto" \
  "$PROTO_DIR/notification.proto"

sed -i.bak 's/^import product_pb2/from . import product_pb2/' "$ORDER_OUT/product_pb2_grpc.py" 2>/dev/null || \
sed -i '' 's/^import product_pb2/from . import product_pb2/' "$ORDER_OUT/product_pb2_grpc.py"
sed -i.bak 's/^import notification_pb2/from . import notification_pb2/' "$ORDER_OUT/notification_pb2_grpc.py" 2>/dev/null || \
sed -i '' 's/^import notification_pb2/from . import notification_pb2/' "$ORDER_OUT/notification_pb2_grpc.py"
rm -f "$ORDER_OUT/"*.bak

echo "  ✅ order-service stubs generated (product + notification clients)"

# ── Payment Service stubs (notification client) ──────────────────────────────
PAY_OUT="$SERVICES_DIR/payment-service/src/generated"
mkdir -p "$PAY_OUT"
touch "$PAY_OUT/__init__.py"

python3 -m grpc_tools.protoc \
  -I"$PROTO_DIR" \
  --python_out="$PAY_OUT" \
  --grpc_python_out="$PAY_OUT" \
  "$PROTO_DIR/notification.proto"

sed -i.bak 's/^import notification_pb2/from . import notification_pb2/' "$PAY_OUT/notification_pb2_grpc.py" 2>/dev/null || \
sed -i '' 's/^import notification_pb2/from . import notification_pb2/' "$PAY_OUT/notification_pb2_grpc.py"
rm -f "$PAY_OUT/"*.bak

echo "  ✅ payment-service stubs generated (notification client)"

echo ""
echo "🎉 All gRPC stubs generated successfully!"
echo ""
echo "Generated directories:"
echo "  - services/notification-service/src/generated/"
echo "  - services/user-service/src/generated/"
echo "  - services/product-service/src/generated/"
echo "  - services/order-service/src/generated/"
echo "  - services/payment-service/src/generated/"
