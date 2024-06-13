ARG PYTHON_VERSION=3.9
ARG BASE_IMAGE=python:${PYTHON_VERSION}-slim-bullseye
ARG VENV_PATH=/prod_venv

FROM ${BASE_IMAGE} as builder

# Install Poetry
ARG POETRY_HOME=/opt/poetry
ARG POETRY_VERSION=1.7.1
ARG CARGO_HOME=/opt/.cargo/

# Required for building packages for arm64 arch
RUN apt-get update && apt-get install -y --no-install-recommends python3-dev libopenblas-dev libssl-dev pkg-config curl build-essential libhdf5-dev cmake gfortran && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > sh.rustup.rs && \
    export CARGO_HOME=${CARGO_HOME} && sh ./sh.rustup.rs -y && export PATH=$PATH:${CARGO_HOME}/bin && . "${CARGO_HOME}/env" && \
    python3 -m venv ${POETRY_HOME} && ${POETRY_HOME}/bin/pip install poetry==${POETRY_VERSION}
ENV PATH="$PATH:${POETRY_HOME}/bin:${CARGO_HOME}/bin"

# Activate virtual env
ARG VENV_PATH
ENV VIRTUAL_ENV=${VENV_PATH}
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

COPY kserve/pyproject.toml kserve/poetry.lock kserve/
RUN cd kserve && GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true poetry install --no-root --no-interaction --no-cache
COPY kserve kserve
RUN cd kserve && poetry install --no-interaction --no-cache

COPY artexplainer/pyproject.toml artexplainer/poetry.lock artexplainer/
RUN cd artexplainer && poetry install --no-root --no-interaction --no-cache
COPY artexplainer artexplainer
RUN cd artexplainer && poetry install --no-interaction --no-cache


FROM ${BASE_IMAGE} as prod

COPY third_party third_party

# Activate virtual env
ARG VENV_PATH
ENV VIRTUAL_ENV=${VENV_PATH}
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN useradd kserve -m -u 1000 -d /home/kserve

COPY --from=builder --chown=kserve:kserve $VIRTUAL_ENV $VIRTUAL_ENV
COPY --from=builder kserve kserve
COPY --from=builder artexplainer artexplainer

USER 1000
ENTRYPOINT ["python", "-m", "artserver"]
