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
        min_size=5,
        max_size=20,
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
        async with app.state.db_pool.acquire() as conn:
            row = await conn.fetchrow(
                """
                INSERT INTO users (email, username, full_name, hashed_password)
                VALUES ($1, $2, $3, $4)
                RETURNING id, email, username, full_name, is_active, is_verified, created_at
                """,
                user.email, user.username, user.full_name, user.password  # Hash in production
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
