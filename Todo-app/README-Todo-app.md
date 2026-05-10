# Todo App — Cloud Native

A simple Todo application built for Kubernetes deployment on AWS.

## Stack
- **Frontend**: HTML/CSS/JS served by Nginx
- **Backend**: Python Flask REST API
- **Database**: PostgreSQL
- **Cache**: Redis

## Project Structure
```
todo-app/
├── backend/
│   ├── app.py              # Flask API
│   ├── models.py           # SQLAlchemy models
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/
│   ├── index.html          # UI
│   └── Dockerfile
│   └──nginx.conf
└── docker-compose.yml      # Local dev only
```

## API Endpoints
| Method | Path | Description |
|--------|------|-------------|
| GET | /health | Health check |
| GET | /api/todos | List all todos (Redis cached) |
| POST | /api/todos | Create a todo |
| PATCH | /api/todos/:id | Update (toggle complete) |
| DELETE | /api/todos/:id | Delete a todo |

## Environment Variables (injected by DevOps)
```
DATABASE_URL=postgresql://user:pass@postgres-service:5432/tododb
REDIS_HOST=redis-service
REDIS_PORT=6379
REDIS_PASSWORD=secret
```

## Run Locally
```bash
docker-compose up --build
```
- Frontend: http://localhost:3000
- Backend:  http://localhost:5000
