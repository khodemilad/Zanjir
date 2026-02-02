ARG PYTHON_IMAGE=docker.arvancloud.ir/python:3.11-slim
FROM ${PYTHON_IMAGE}

WORKDIR /app

ARG PIP_INDEX_URL=https://pypi.ir/simple
ARG PIP_TRUSTED_HOST=pypi.ir
ARG PIP_EXTRA_INDEX_URL=https://pypi.org/simple

COPY requirements.txt .
RUN pip install --no-cache-dir \
    --index-url "${PIP_INDEX_URL}" \
    --extra-index-url "${PIP_EXTRA_INDEX_URL}" \
    --trusted-host "${PIP_TRUSTED_HOST}" \
    -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
