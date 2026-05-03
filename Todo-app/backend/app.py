import os
import json
from flask import Flask, request, jsonify
from flask_cors import CORS
from models import db, Todo
import redis
import time

app = Flask(__name__)
CORS(app)

# PostgreSQL - injected by DevOps
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
    "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/tododb"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
db.init_app(app)

# Redis - injected by DevOps
cache = redis.Redis(
    host=os.environ.get("REDIS_HOST", "localhost"),
    port=int(os.environ.get("REDIS_PORT", 6379)),
    password=os.environ.get("REDIS_PASSWORD", None),
    decode_responses=True
)

CACHE_TTL = 60  # seconds


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/api/todos", methods=["GET"])
def get_todos():
    cached = cache.get("todos:all")
    if cached:
        return jsonify(json.loads(cached))
    todos = Todo.query.order_by(Todo.id.desc()).all()
    result = [t.to_dict() for t in todos]
    cache.set("todos:all", json.dumps(result), ex=CACHE_TTL)
    return jsonify(result)


@app.route("/api/todos", methods=["POST"])
def create_todo():
    data = request.get_json()
    todo = Todo(title=data["title"], completed=False)
    db.session.add(todo)
    db.session.commit()
    cache.delete("todos:all")
    return jsonify(todo.to_dict()), 201


@app.route("/api/todos/<int:todo_id>", methods=["PATCH"])
def update_todo(todo_id):
    todo = Todo.query.get_or_404(todo_id)
    data = request.get_json()
    if "completed" in data:
        todo.completed = data["completed"]
    if "title" in data:
        todo.title = data["title"]
    db.session.commit()
    cache.delete("todos:all")
    return jsonify(todo.to_dict())


@app.route("/api/todos/<int:todo_id>", methods=["DELETE"])
def delete_todo(todo_id):
    todo = Todo.query.get_or_404(todo_id)
    db.session.delete(todo)
    db.session.commit()
    cache.delete("todos:all")
    return jsonify({"deleted": todo_id})


# create tables on startup with retry
with app.app_context():
    retries = 5
    while retries > 0:
        try:
            db.create_all()
            print("Database tables created successfully")
            break
        except Exception as e:
            retries -= 1
            print(f"Database not ready, retrying... ({retries} left)")
            time.sleep(3)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)