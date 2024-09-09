ARG PYTHON_VERSION=3.9
ARG BASE_IMAGE=python:${PYTHON_VERSION}-slim-bullseye
ARG VENV_PATH=/prod_venv

FROM ${BASE_IMAGE} as builder

# Install Poetry
ARG POETRY_HOME=/opt/poetry
ARG POETRY_VERSION=1.7.1

# Install Poetry
ARG POETRY_HOME=/opt/poetry
ARG POETRY_VERSION=1.7.1
ARG CARGO_HOME=/opt/.cargo/

# Required for building packages for arm64 arch
RUN apt-get update -y && apt-get install -y --no-install-recommends python3-dev build-essential && \
    if [ "$(uname -m)" = "ppc64le" ]; then \
       echo "Installing packages and rust " && \
       apt-get install -y libopenblas-dev libssl-dev pkg-config curl libhdf5-dev cmake gfortran && \
       curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > sh.rustup.rs && \
       export CARGO_HOME=${CARGO_HOME} && sh ./sh.rustup.rs -y && export PATH=$PATH:${CARGO_HOME}/bin && . "${CARGO_HOME}/env"; \
    fi && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ENV PATH="$PATH:${POETRY_HOME}/bin:${CARGO_HOME}/bin"
RUN python3 -m venv ${POETRY_HOME} && ${POETRY_HOME}/bin/pip3 install poetry==${POETRY_VERSION}
ENV PIP_EXTRA_INDEX_URL=http://10.20.177.222:9000/
ENV PIP_TRUSTED_HOST=10.20.177.222

# Activate virtual env
ARG VENV_PATH
ENV VIRTUAL_ENV=${VENV_PATH}
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH:${POETRY_HOME}/bin"

COPY kserve/pyproject.toml kserve/poetry.lock kserve/
RUN cd kserve && \
    if [ "$(uname -m)" = "ppc64le" ]; then \
      export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true; \
    fi && \
    pip install --trusted-host 10.20.177.222 --extra-index-url http://10.20.177.222:9000/ ray==2.10.0 && \
    poetry source add --priority=primary local-index ${PIP_EXTRA_INDEX_URL} && poetry source add --priority=supplemental PyPI && poetry lock --no-update && poetry install --no-root --no-interaction --no-cache

COPY kserve kserve
RUN cd kserve && poetry source add --priority=primary local-index ${PIP_EXTRA_INDEX_URL} && poetry source add --priority=supplemental PyPI && poetry lock --no-update && poetry install --no-interaction --no-cache

COPY sklearnserver/pyproject.toml sklearnserver/poetry.lock sklearnserver/
RUN cd sklearnserver && poetry source add --priority=primary local-index ${PIP_EXTRA_INDEX_URL} && poetry source add --priority=supplemental PyPI && poetry lock --no-update && poetry install --no-root --no-interaction --no-cache

COPY sklearnserver sklearnserver
RUN cd sklearnserver && poetry source add --priority=primary local-index ${PIP_EXTRA_INDEX_URL} && poetry source add --priority=supplemental PyPI && poetry lock --no-update && poetry install --no-interaction --no-cache

FROM ${BASE_IMAGE} as prod
RUN apt-get update -y && apt-get install -y libopenblas-dev libgomp1
COPY third_party third_party

# Activate virtual env
ARG VENV_PATH
ENV VIRTUAL_ENV=${VENV_PATH}
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN useradd kserve -m -u 1000 -d /home/kserve

COPY --from=builder --chown=kserve:kserve $VIRTUAL_ENV $VIRTUAL_ENV
COPY --from=builder kserve kserve
COPY --from=builder sklearnserver sklearnserver

USER 1000
#ENTRYPOINT ["/bin/bash"]
ENTRYPOINT ["python", "-m", "sklearnserver"]
