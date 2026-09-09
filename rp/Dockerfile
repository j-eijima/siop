# The RP is static files plus a server that does nothing but hand them over, so
# the image is the base image and the sources. Verification happens in the
# browser, which is why there is nothing here to run it with.
FROM python:3.13-slim

WORKDIR /app
COPY serve.py ./
COPY public ./public

# The host assigns the port through $PORT; 8080 is the usual default.
ENV PORT=8080
EXPOSE 8080

CMD ["python3", "-u", "serve.py"]
