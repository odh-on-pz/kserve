ARG PYTHON_VERSION=3.9
ARG VENV_PATH=/prod_venv

FROM registry.access.redhat.com/ubi8/ubi-minimal:latest as builder

# Install Python and dependencies

# Install Poetry
ARG POETRY_HOME=/opt/poetry
ARG POETRY_VERSION=1.7.1
ARG CARGO_HOME=/opt/.cargo/

# Install Python and dependencies
RUN microdnf install -y python39 python39-devel gcc libffi-devel openssl-devel krb5-libs && \
    if [ "$(uname -m)" = "ppc64le" ]; then \
       echo "Installing packages and rust " && \
       microdnf install -y openblas* gcc-c++ make krb5-workstation libcurl wget cmake libgfortran && \
       wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
       rpm --import http://download.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-8 && \
       rpm -ivh ./epel-release-latest-8.noarch.rpm && \
       microdnf install -y hdf5-devel && \ 
       curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs > sh.rustup.rs && \
       export CARGO_HOME=${CARGO_HOME} && sh ./sh.rustup.rs -y && export PATH=$PATH:${CARGO_HOME}/bin && . "${CARGO_HOME}/env"; \
    fi && \
    microdnf clean all

ENV PATH="$PATH:${POETRY_HOME}/bin:${CARGO_HOME}/bin"
RUN python3 -m venv ${POETRY_HOME} && ${POETRY_HOME}/bin/pip3 install poetry==${POETRY_VERSION}

# Activate virtual env
ARG VENV_PATH
ENV VIRTUAL_ENV=${VENV_PATH}
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

COPY kserve/pyproject.toml kserve/poetry.lock kserve/
RUN cd kserve && \
    if [[ $(uname -m) = "ppc64le" ]]; then \
      export GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=true; \
    fi && \
    poetry install --no-root --no-interaction --no-cache --extras "storage"

COPY kserve kserve
RUN cd kserve && poetry install --no-interaction --no-cache --extras "storage"

RUN pip install --no-cache-dir krbcontext==0.10 hdfs~=2.6.0 requests-kerberos==0.14.0
# Fixes Quay alert GHSA-2jv5-9r88-3w3p https://github.com/Kludex/python-multipart/security/advisories/GHSA-2jv5-9r88-3w3p
RUN pip install --no-cache-dir starlette==0.36.2

FROM registry.access.redhat.com/ubi8/ubi-minimal:latest as prod

COPY third_party third_party

# Activate virtual env
ARG VENV_PATH
ENV VIRTUAL_ENV=${VENV_PATH}
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN microdnf install -y shadow-utils python39 python39-devel && \
    microdnf clean all
RUN useradd kserve -m -u 1000 -d /home/kserve

COPY --from=builder --chown=kserve:kserve $VIRTUAL_ENV $VIRTUAL_ENV
COPY --from=builder kserve kserve
COPY ./storage-initializer /storage-initializer

RUN chmod +x /storage-initializer/scripts/initializer-entrypoint
RUN mkdir /work
WORKDIR /work

USER 1000
ENTRYPOINT ["/storage-initializer/scripts/initializer-entrypoint"]
