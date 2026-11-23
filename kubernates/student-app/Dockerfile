FROM python:3.12-slim
WORKDIR /app

# 1) install libraries
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2) copy the app
COPY app.py .
COPY templates/ templates/
COPY static/ static/

# run as a normal user, not root
RUN useradd --create-home appuser
USER appuser

EXPOSE 8000
# --preload: create the table once before starting 2 workers
CMD ["gunicorn", "--preload", "--workers", "2", "--bind", "0.0.0.0:8000", "--access-logfile", "-", "app:app"]
