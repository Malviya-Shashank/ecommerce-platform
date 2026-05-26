"""
User Service - E-Commerce Platform
Handles user registration, authentication, and profile management.
"""

from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from datetime import datetime
from typing import Optional
import os
import logging
from contextlib import asynccontextmanager
import asyncpg
import hashlib
import httpx

# Helper: Hash passwords with SHA-256
def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

# Logging configuration
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(name)s - %(levelname)s - %(message)s")
logger = logging.getLogger("user-service")

# Database configuration
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://user_service:password@localhost:5432/user_service")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler for startup/shutdown events."""
    # Startup
    logger.info("Starting User Service...")
    app.state.db_pool = await asyncpg.create_pool(
        DATABASE_URL,
        min_size=1,
        max_size=5,
        command_timeout=60,
    )
    # Create tables if not exist
    async with app.state.db_pool.acquire() as conn:
        await conn.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                email VARCHAR(255) UNIQUE NOT NULL,
                username VARCHAR(100) UNIQUE NOT NULL,
                full_name VARCHAR(255),
                hashed_password VARCHAR(255) NOT NULL,
                is_active BOOLEAN DEFAULT TRUE,
                is_verified BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)
    logger.info("User Service started successfully")
    yield
    # Shutdown
    logger.info("Shutting down User Service...")
    await app.state.db_pool.close()


app = FastAPI(
    title="User Service",
    description="User management microservice for e-commerce platform",
    version="1.0.0",
    root_path="/api/v1/users",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── Models ──────────────────────────────────────────────────────────────────

class UserCreate(BaseModel):
    email: EmailStr
    username: str
    full_name: Optional[str] = None
    password: str


class UserResponse(BaseModel):
    id: int
    email: str
    username: str
    full_name: Optional[str]
    is_active: bool
    is_verified: bool
    created_at: datetime


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    email: Optional[EmailStr] = None


class LoginRequest(BaseModel):
    username_or_email: str
    password: str


class ForgotPasswordRequest(BaseModel):
    email: str


class HealthResponse(BaseModel):
    status: str
    service: str
    version: str
    timestamp: datetime


# ─── Health Check ────────────────────────────────────────────────────────────

@app.get("/healthz", response_model=HealthResponse, tags=["health"])
async def health_check():
    return HealthResponse(
        status="healthy",
        service="user-service",
        version="1.0.0",
        timestamp=datetime.utcnow(),
    )


@app.get("/readyz", tags=["health"])
async def readiness_check():
    """Readiness check - verifies database connectivity."""
    try:
        async with app.state.db_pool.acquire() as conn:
            await conn.execute("SELECT 1")
        return {"status": "ready"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        raise HTTPException(status_code=503, detail="Service not ready")


# ─── User Endpoints ─────────────────────────────────────────────────────────

@app.post("/", response_model=UserResponse, status_code=status.HTTP_201_CREATED, tags=["users"])
async def create_user(user: UserCreate):
    """Create a new user account."""
    try:
        hashed = hash_password(user.password)
        async with app.state.db_pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                INSERT INTO users (email, username, full_name, hashed_password)
                VALUES ($1, $2, $3, $4)
                RETURNING id, email, username, full_name, is_active, is_verified, created_at
                """,
                user.email, user.username, user.full_name, hashed
            )
            return UserResponse(**dict(row))
    except asyncpg.UniqueViolationError:
        raise HTTPException(status_code=409, detail="User with this email or username already exists")


@app.get("/{user_id}", response_model=UserResponse, tags=["users"])
async def get_user(user_id: int):
    """Get user by ID."""
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            "SELECT id, email, username, full_name, is_active, is_verified, created_at FROM users WHERE id = $1",
            user_id,
        )
        if not row:
            raise HTTPException(status_code=404, detail="User not found")
        return UserResponse(**dict(row))


@app.get("/", tags=["users"])
async def list_users(skip: int = 0, limit: int = 20):
    """List users with pagination."""
    async with app.state.db_pool.acquire() as conn:
        rows = await conn.fetch(
            "SELECT id, email, username, full_name, is_active, is_verified, created_at FROM users ORDER BY id LIMIT $1 OFFSET $2",
            limit, skip,
        )
        return [UserResponse(**dict(row)) for row in rows]


@app.put("/{user_id}", response_model=UserResponse, tags=["users"])
async def update_user(user_id: int, user_update: UserUpdate):
    """Update user profile."""
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            UPDATE users SET
                full_name = COALESCE($2, full_name),
                email = COALESCE($3, email),
                updated_at = NOW()
            WHERE id = $1
            RETURNING id, email, username, full_name, is_active, is_verified, created_at
            """,
            user_id, user_update.full_name, user_update.email,
        )
        if not row:
            raise HTTPException(status_code=404, detail="User not found")
        return UserResponse(**dict(row))


@app.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["users"])
async def delete_user(user_id: int):
    """Soft-delete a user."""
    async with app.state.db_pool.acquire() as conn:
        result = await conn.execute(
            "UPDATE users SET is_active = FALSE, updated_at = NOW() WHERE id = $1",
            user_id,
        )
        if result == "UPDATE 0":
            raise HTTPException(status_code=404, detail="User not found")


@app.post("/login", response_model=UserResponse, tags=["auth"])
async def login(credentials: LoginRequest):
    """Authenticate a user."""
    hashed = hash_password(credentials.password)
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT id, email, username, full_name, is_active, is_verified, created_at
            FROM users
            WHERE (email = $1 OR username = $1) AND hashed_password = $2
            """,
            credentials.username_or_email, hashed
        )
        if not row:
            raise HTTPException(status_code=401, detail="Invalid username/email or password")
        
        user_info = dict(row)
        if not user_info["is_active"]:
            raise HTTPException(status_code=403, detail="User account is deactivated")
            
        return UserResponse(**user_info)


NOTIFICATION_SERVICE_URL = os.getenv("NOTIFICATION_SERVICE_URL", "http://notification-service:8000")

@app.post("/forgot-password", tags=["auth"])
async def forgot_password(req: ForgotPasswordRequest):
    """Generate password reset token and dispatch microservice notification email."""
    async with app.state.db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT id, username, email FROM users WHERE email = $1 AND is_active = TRUE", req.email)
        if not row:
            raise HTTPException(status_code=404, detail="User with this email not found")
        
        user_data = dict(row)
        # Generate dummy reset token
        reset_token = f"rst_{hashlib.sha256(f'{req.email}-{datetime.utcnow()}'.encode()).hexdigest()[:16]}"
        
        # Microservice communication: call notification-service via HTTP
        try:
            async with httpx.AsyncClient() as client:
                await client.post(
                    f"{NOTIFICATION_SERVICE_URL}/",
                    json={
                        "user_id": user_data["id"],
                        "type": "email",
                        "subject": "Password Reset Instructions",
                        "message": f"Hello {user_data['username']}! We received a password reset request. Click this link to reset your credentials: http://localhost:8081/?action=reset-password&token={reset_token}",
                        "metadata": {"reset_token": reset_token}
                    },
                    timeout=5.0
                )
        except Exception as e:
            logger.error(f"Failed to dispatch reset notification: {e}")
            
        return {"message": "Password reset instructions sent to your email", "token": reset_token}
