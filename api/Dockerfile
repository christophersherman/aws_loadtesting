FROM python:3.9-slim

WORKDIR /app

RUN pip install fastapi gunicorn uvicorn python-multipart asyncio

COPY app.py .

#CMD ["gunicorn", "app:app", "-w", "4","-k", "uvicorn.workers.UvicornWorker", "-b", "0.0.0.0:8000"]
CMD ["gunicorn", "app:app", "-w", "2", "-k", "uvicorn.workers.UvicornWorker", "--threads", "4", "-b", "0.0.0.0:8000"]