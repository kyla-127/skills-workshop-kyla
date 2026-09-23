FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

CMD ["chainlit", "run", "app.py", "--host", "0.0.0.0", "--port", "8080"]
