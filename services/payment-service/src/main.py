"""
Payment Service - E-Commerce Platform
Handles payment processing and refunds.

Inter-service communication (gRPC):
  - Calls notification-service via gRPC for payment confirmations
"""

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional
from decimal import Decimal
from enum import Enum
import os, logging, asyncpg, uuid
from contextlib import asynccontextmanager

import grpc
from src.generated import notification_pb2, notification_pb2_grpc

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("payment-service")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://payment_service:password@localhost:5432/payment_service")

# gRPC target for notification-service (internal service-to-service)
NOTIFICATION_SERVICE_GRPC = os.getenv("NOTIFICATION_SERVICE_GRPC", "notification-service:50051")


class PaymentStatus(str, Enum):
    PENDING = "pending"
    COMPLETED = "completed"
    FAILED = "failed"
    REFUNDED = "refunded"


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=5, command_timeout=60)
    async with app.state.db_pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS payments (
                id SERIAL PRIMARY KEY,
                payment_id VARCHAR(255) UNIQUE NOT NULL,
                order_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                amount DECIMAL(10,2) NOT NULL,
                currency VARCHAR(3) DEFAULT 'USD',
                status VARCHAR(50) DEFAULT 'pending',
                payment_method VARCHAR(50),
                transaction_id VARCHAR(255),
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)

    # Initialize gRPC channel for notification-service
    app.state.notification_channel = grpc.aio.insecure_channel(NOTIFICATION_SERVICE_GRPC)
    app.state.notification_stub = notification_pb2_grpc.NotificationServiceStub(app.state.notification_channel)
    logger.info(f"gRPC channel to notification-service: {NOTIFICATION_SERVICE_GRPC}")

    logger.info("Payment Service started successfully")
    yield

    logger.info("Shutting down Payment Service...")
    await app.state.notification_channel.close()
    await app.state.db_pool.close()


app = FastAPI(title="Payment Service", version="1.0.0", root_path="/api/v1/payments", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])


class PaymentCreate(BaseModel):
    order_id: int
    user_id: int
    amount: Decimal
    currency: str = "USD"
    payment_method: str


class PaymentResponse(BaseModel):
    id: int
    payment_id: str
    order_id: int
    user_id: int
    amount: Decimal
    currency: str
    status: str
    payment_method: str
    created_at: datetime


@app.get("/healthz", tags=["health"])
async def health_check():
    return {"status": "healthy", "service": "payment-service", "version": "1.0.0"}


@app.get("/readyz", tags=["health"])
async def readiness_check():
    try:
        async with app.state.db_pool.acquire() as conn:
            await conn.execute("SELECT 1")
        return {"status": "ready"}
    except Exception:
        raise HTTPException(status_code=503, detail="Service not ready")


@app.post("/", response_model=PaymentResponse, status_code=status.HTTP_201_CREATED, tags=["payments"])
async def create_payment(payment: PaymentCreate):
    payment_id = f"pay_{uuid.uuid4().hex[:16]}"
    async with app.state.db_pool.acquire() as conn:
        # Simulate payment processing
        row = await conn.fetchrow(
            """INSERT INTO payments (payment_id, order_id, user_id, amount, currency, status, payment_method)
               VALUES ($1, $2, $3, $4, $5, 'completed', $6)
               RETURNING id, payment_id, order_id, user_id, amount, currency, status, payment_method, created_at""",
            payment_id, payment.order_id, payment.user_id, payment.amount, payment.currency, payment.payment_method,
        )
        result = PaymentResponse(**dict(row))

        # Send payment confirmation notification via gRPC
        try:
            await app.state.notification_stub.SendNotification(
                notification_pb2.NotificationRequest(
                    user_id=payment.user_id,
                    type="email",
                    subject="Payment Confirmation",
                    message=f"Your payment of ${payment.amount:.2f} {payment.currency} "
                            f"for order #{payment.order_id} has been processed successfully. "
                            f"Payment ID: {payment_id}",
                    metadata={
                        "payment_id": payment_id,
                        "order_id": str(payment.order_id),
                        "amount": str(payment.amount),
                    },
                ),
                timeout=5.0,
            )
            logger.info(f"[gRPC] Payment confirmation sent for {payment_id}")
        except grpc.aio.AioRpcError as e:
            logger.error(f"[gRPC] Failed to send payment confirmation: {e.code()}")

        return result


@app.get("/{payment_id}", response_model=PaymentResponse, tags=["payments"])
async def get_payment(payment_id: str):
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT * FROM payments WHERE payment_id = $1", payment_id)
        if not row:
            raise HTTPException(status_code=404, detail="Payment not found")
        return PaymentResponse(**dict(row))


@app.post("/{payment_id}/refund", tags=["payments"])
async def refund_payment(payment_id: str):
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            "UPDATE payments SET status = 'refunded', updated_at = NOW() "
            "WHERE payment_id = $1 AND status = 'completed' RETURNING user_id, amount, currency, order_id",
            payment_id,
        )
        if not row:
            raise HTTPException(status_code=400, detail="Payment cannot be refunded")

        # Send refund notification via gRPC
        try:
            await app.state.notification_stub.SendNotification(
                notification_pb2.NotificationRequest(
                    user_id=row["user_id"],
                    type="email",
                    subject="Payment Refund Processed",
                    message=f"Your refund of ${row['amount']:.2f} {row['currency']} "
                            f"for order #{row['order_id']} has been processed. "
                            f"Payment ID: {payment_id}",
                    metadata={"payment_id": payment_id, "refund": "true"},
                ),
                timeout=5.0,
            )
        except grpc.aio.AioRpcError as e:
            logger.error(f"[gRPC] Failed to send refund notification: {e.code()}")

        return {"message": f"Payment {payment_id} refunded"}
