"""
Notification Service - E-Commerce Platform
Handles email, SMS, and push notifications.

Exposes:
  - FastAPI REST API on port 8000 (external/client-facing)
  - gRPC server on port 50051 (internal service-to-service)
"""

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List
from enum import Enum
import os, logging, asyncpg, json
from contextlib import asynccontextmanager
import asyncio
from concurrent import futures

import grpc
from grpc_reflection.v1alpha import reflection
from src.generated import notification_pb2, notification_pb2_grpc

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("notification-service")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://notification_service:password@localhost:5432/notification_service")
GRPC_PORT = int(os.getenv("GRPC_PORT", "50051"))


class NotificationType(str, Enum):
    EMAIL = "email"
    SMS = "sms"
    PUSH = "push"


class NotificationStatus(str, Enum):
    PENDING = "pending"
    SENT = "sent"
    FAILED = "failed"


################################################################################
# gRPC Service Implementation
################################################################################

class NotificationGrpcServicer(notification_pb2_grpc.NotificationServiceServicer):
    """gRPC servicer for internal service-to-service notification dispatch."""

    def __init__(self, db_pool):
        self.db_pool = db_pool

    async def SendNotification(self, request, context):
        """Handle gRPC notification request from other microservices."""
        logger.info(f"[gRPC] Received notification for user {request.user_id} via {request.type}")

        try:
            metadata_dict = dict(request.metadata) if request.metadata else None
            async with self.db_pool.acquire() as conn:
                row = await conn.fetchrow(
                    """INSERT INTO notifications (user_id, type, subject, message, status, metadata, sent_at)
                       VALUES ($1, $2, $3, $4, 'sent', $5::jsonb, NOW())
                       RETURNING id, status, created_at""",
                    request.user_id,
                    request.type,
                    request.subject,
                    request.message,
                    json.dumps(metadata_dict) if metadata_dict else None,
                )
                logger.info(f"[gRPC] Notification sent: id={row['id']} for user {request.user_id}")
                return notification_pb2.NotificationResponse(
                    id=row["id"],
                    status=row["status"],
                    created_at=str(row["created_at"]),
                )
        except Exception as e:
            logger.error(f"[gRPC] Failed to send notification: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            context.set_details(f"Failed to send notification: {str(e)}")
            return notification_pb2.NotificationResponse()

    async def SendBulkNotification(self, request, context):
        """Handle bulk gRPC notification requests."""
        total_sent = 0
        total_failed = 0
        for notif in request.notifications:
            try:
                resp = await self.SendNotification(notif, context)
                if resp.id > 0:
                    total_sent += 1
                else:
                    total_failed += 1
            except Exception:
                total_failed += 1

        return notification_pb2.BulkNotificationResponse(
            total_sent=total_sent,
            total_failed=total_failed,
        )


async def start_grpc_server(db_pool):
    """Start the gRPC server for internal service-to-service communication."""
    server = grpc.aio.server(futures.ThreadPoolExecutor(max_workers=10))
    notification_pb2_grpc.add_NotificationServiceServicer_to_server(
        NotificationGrpcServicer(db_pool), server
    )

    # Enable gRPC reflection for debugging with grpcurl
    SERVICE_NAMES = (
        notification_pb2.DESCRIPTOR.services_by_name["NotificationService"].full_name,
        reflection.SERVICE_NAME,
    )
    reflection.enable_server_reflection(SERVICE_NAMES, server)

    server.add_insecure_port(f"[::]:{GRPC_PORT}")
    await server.start()
    logger.info(f"gRPC server started on port {GRPC_PORT}")
    return server


################################################################################
# FastAPI Application (external-facing REST API)
################################################################################

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.db_pool = await asyncpg.create_pool(DATABASE_URL, min_size=1, max_size=5, command_timeout=60)
    async with app.state.db_pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS notifications (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL,
                type VARCHAR(50) NOT NULL,
                subject VARCHAR(255),
                message TEXT NOT NULL,
                status VARCHAR(50) DEFAULT 'pending',
                metadata JSONB,
                created_at TIMESTAMP DEFAULT NOW(),
                sent_at TIMESTAMP
            )
        """)

    # Start gRPC server alongside FastAPI
    grpc_server = await start_grpc_server(app.state.db_pool)
    logger.info("Notification Service started successfully (HTTP + gRPC)")

    yield

    # Shutdown
    logger.info("Shutting down Notification Service...")
    await grpc_server.stop(grace=5)
    await app.state.db_pool.close()


app = FastAPI(title="Notification Service", version="1.0.0", root_path="/api/v1/notifications", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])


class NotificationCreate(BaseModel):
    user_id: int
    type: NotificationType
    subject: Optional[str] = None
    message: str
    metadata: Optional[dict] = None


class NotificationResponse(BaseModel):
    id: int
    user_id: int
    type: str
    subject: Optional[str]
    message: str
    status: str
    created_at: datetime


@app.get("/healthz", tags=["health"])
async def health_check():
    return {"status": "healthy", "service": "notification-service", "version": "1.0.0", "grpc_port": GRPC_PORT}


@app.get("/readyz", tags=["health"])
async def readiness_check():
    try:
        async with app.state.db_pool.acquire() as conn:
            await conn.execute("SELECT 1")
        return {"status": "ready"}
    except Exception:
        raise HTTPException(status_code=503, detail="Service not ready")


@app.post("/", response_model=NotificationResponse, status_code=status.HTTP_201_CREATED, tags=["notifications"])
async def send_notification(notification: NotificationCreate):
    async with app.state.db_pool.acquire() as conn:
        # Simulate sending notification
        row = await conn.fetchrow(
            """INSERT INTO notifications (user_id, type, subject, message, status, metadata, sent_at)
               VALUES ($1, $2, $3, $4, 'sent', $5::jsonb, NOW())
               RETURNING id, user_id, type, subject, message, status, created_at""",
            notification.user_id, notification.type.value, notification.subject, notification.message,
            json.dumps(notification.metadata) if notification.metadata else None,
        )
        logger.info(f"Notification sent to user {notification.user_id} via {notification.type.value}")
        return NotificationResponse(**dict(row))


@app.get("/user/{user_id}", tags=["notifications"])
async def get_user_notifications(user_id: int, skip: int = 0, limit: int = 20):
    async with app.state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, user_id, type, subject, message, status, created_at FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3",
            user_id, limit, skip,
        )
        return [NotificationResponse(**dict(row)) for row in rows]
