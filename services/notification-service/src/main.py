"""
Notification Service - E-Commerce Platform
Handles email, SMS, and push notifications.
"""

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List
from enum import Enum
import os, logging, asyncpg, json
from contextlib import asynccontextmanager

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("notification-service")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://notification_service:password@localhost:5432/notification_service")


class NotificationType(str, Enum):
    EMAIL = "email"
    SMS = "sms"
    PUSH = "push"


class NotificationStatus(str, Enum):
    PENDING = "pending"
    SENT = "sent"
    FAILED = "failed"


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
    logger.info("Notification Service started successfully")
    yield
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
    return {"status": "healthy", "service": "notification-service", "version": "1.0.0"}


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
