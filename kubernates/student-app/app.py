"""
Student Records: a tiny website to practise database work (CRUD).

  C = Create  -> INSERT   (Add student form)
  R = Read    -> SELECT   (the table + search)
  U = Update  -> UPDATE   (Edit page)
  D = Delete  -> DELETE   (Delete button)

Database settings come from environment variables that Kubernetes fills in
from the ConfigMap "db-config" and the Secret "db-secret" (see app.yaml).
"""
import os
import socket

import psycopg
from flask import Flask, redirect, render_template, request, url_for

app = Flask(__name__)

# 1) How to reach the database (values come from app.yaml)
DB_CONNINFO = (
    f"host={os.environ['DB_HOST']} "
    f"port={os.environ['DB_PORT']} "
    f"dbname={os.environ['DB_NAME']} "
    f"user={os.environ['DB_USER']} "
    f"password={os.environ['DB_PASSWORD']} "
    f"sslmode={os.environ.get('DB_SSLMODE', 'disable')}"
)
POD_NAME = socket.gethostname()  # which pod answered (shown at the bottom of the page)


def db():
    """Open a connection to PostgreSQL."""
    return psycopg.connect(DB_CONNINFO)


# 2) Create the table the first time the app starts
def create_table():
    with db() as conn:
        conn.execute("SELECT pg_advisory_lock(1)")  # 3 pods start together: one at a time
        conn.execute("""
            CREATE TABLE IF NOT EXISTS students (
                id         SERIAL PRIMARY KEY,           -- 1, 2, 3... automatic
                name       VARCHAR(80)  NOT NULL,
                email      VARCHAR(120) NOT NULL UNIQUE, -- no two students with same email
                course     VARCHAR(80)  NOT NULL,
                marks      INT CHECK (marks BETWEEN 0 AND 100),
                created_at TIMESTAMPTZ  NOT NULL DEFAULT now()
            )
        """)
        # add 3 sample rows, only if the table is empty
        count = conn.execute("SELECT COUNT(*) FROM students").fetchone()[0]
        if count == 0:
            conn.execute("""
                INSERT INTO students (name, email, course, marks) VALUES
                ('Aarav Sharma', 'aarav@example.com', 'Computer Science', 88),
                ('Priya Singh',  'priya@example.com', 'Electronics',      92),
                ('Rohan Gupta',  'rohan@example.com', 'Computer Science', 75)
            """)
        conn.execute("SELECT pg_advisory_unlock(1)")


def read_form():
    """Read the form fields. Returns (values, error_message)."""
    name = request.form.get("name", "").strip()
    email = request.form.get("email", "").strip().lower()
    course = request.form.get("course", "").strip()
    marks = request.form.get("marks", "").strip()
    if not name or not email or not course:
        return None, "Name, email and course are required."
    if marks and (not marks.isdigit() or int(marks) > 100):
        return None, "Marks must be a number from 0 to 100."
    return (name, email, course, int(marks) if marks else None), None


# ---------------- READ: list + search ----------------
@app.get("/")
def index():
    search = request.args.get("q", "").strip()
    with db() as conn:
        if search:
            # ILIKE = case-insensitive match, %text% = "contains text"
            students = conn.execute(
                "SELECT id, name, email, course, marks FROM students "
                "WHERE name ILIKE %s OR course ILIKE %s ORDER BY id",
                (f"%{search}%", f"%{search}%"),
            ).fetchall()
        else:
            students = conn.execute(
                "SELECT id, name, email, course, marks FROM students ORDER BY id"
            ).fetchall()
        # COUNT and AVG: one row of totals
        total, average = conn.execute(
            "SELECT COUNT(*), ROUND(AVG(marks), 1) FROM students"
        ).fetchone()
    return render_template(
        "index.html",
        students=students, search=search, total=total, average=average,
        message=request.args.get("msg", ""), pod=POD_NAME,
    )


# ---------------- CREATE ----------------
@app.post("/add")
def add():
    values, error = read_form()
    if error:
        return redirect(url_for("index", msg=error))
    try:
        with db() as conn:
            conn.execute(
                # %s = placeholder: psycopg fills it in safely (no SQL injection)
                "INSERT INTO students (name, email, course, marks) VALUES (%s, %s, %s, %s)",
                values,
            )
    except psycopg.errors.UniqueViolation:
        return redirect(url_for("index", msg="That email already exists."))
    return redirect(url_for("index", msg=f"Added {values[0]}."))


# ---------------- UPDATE ----------------
@app.get("/edit/<int:student_id>")
def edit_page(student_id):
    with db() as conn:
        student = conn.execute(
            "SELECT id, name, email, course, marks FROM students WHERE id = %s",
            (student_id,),
        ).fetchone()
    if student is None:
        return redirect(url_for("index", msg="Student not found."))
    return render_template("edit.html", s=student, error=request.args.get("error", ""))


@app.post("/edit/<int:student_id>")
def edit(student_id):
    values, error = read_form()
    if error:
        return redirect(url_for("edit_page", student_id=student_id, error=error))
    try:
        with db() as conn:
            conn.execute(
                "UPDATE students SET name = %s, email = %s, course = %s, marks = %s "
                "WHERE id = %s",
                (*values, student_id),
            )
    except psycopg.errors.UniqueViolation:
        return redirect(url_for("edit_page", student_id=student_id, error="That email already exists."))
    return redirect(url_for("index", msg=f"Updated {values[0]}."))


# ---------------- DELETE ----------------
@app.post("/delete/<int:student_id>")
def delete(student_id):
    with db() as conn:
        conn.execute("DELETE FROM students WHERE id = %s", (student_id,))
    return redirect(url_for("index", msg=f"Deleted student #{student_id}."))


# ---------------- Health check for Kubernetes ----------------
@app.get("/healthz")
def healthz():
    return "ok"


create_table()
