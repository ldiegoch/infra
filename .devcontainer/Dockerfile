# .devcontainer/Dockerfile
# Herramientas del proyecto con versiones fijadas. Cada descarga se verifica
# contra el archivo de checksums de su release (age no publica uno).
# Las líneas "renovate:" permiten que Renovate abra PRs al salir versiones nuevas.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG TARGETARCH
# renovate: datasource=github-releases depName=opentofu/opentofu
ARG TOFU_VERSION=1.12.6
# renovate: datasource=github-releases depName=getsops/sops
ARG SOPS_VERSION=3.13.3
# renovate: datasource=github-releases depName=FiloSottile/age
ARG AGE_VERSION=1.3.2
# renovate: datasource=github-releases depName=aquasecurity/trivy
ARG TRIVY_VERSION=0.76.1
# renovate: datasource=github-releases depName=gitleaks/gitleaks
ARG GITLEAKS_VERSION=8.30.1
# renovate: datasource=github-releases depName=terraform-linters/tflint
ARG TFLINT_VERSION=0.64.0

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates jq unzip pre-commit python3-jsonschema python3-yaml \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/tools
RUN ARCH="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$ARCH" in \
      amd64) TRIVY_ARCH=64bit; GL_ARCH=x64 ;; \
      arm64) TRIVY_ARCH=ARM64; GL_ARCH=arm64 ;; \
      *) echo "Arquitectura no soportada: $ARCH" >&2; exit 1 ;; \
    esac; \
    gh=https://github.com; \
    fetch() { curl -fsSLO --retry 3 "$1"; }; \
    # OpenTofu
    mkdir tofu && cd tofu; \
    fetch "$gh/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${ARCH}.tar.gz"; \
    fetch "$gh/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_SHA256SUMS"; \
    sha256sum --check --ignore-missing "tofu_${TOFU_VERSION}_SHA256SUMS"; \
    tar -xzf "tofu_${TOFU_VERSION}_linux_${ARCH}.tar.gz"; install -m 0755 tofu /usr/local/bin/tofu; cd ..; \
    # SOPS
    mkdir sops && cd sops; \
    fetch "$gh/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${ARCH}"; \
    fetch "$gh/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.checksums.txt"; \
    sha256sum --check --ignore-missing "sops-v${SOPS_VERSION}.checksums.txt"; \
    install -m 0755 "sops-v${SOPS_VERSION}.linux.${ARCH}" /usr/local/bin/sops; cd ..; \
    # age (sin archivo de checksums; descarga por HTTPS desde el release oficial)
    mkdir age && cd age; \
    fetch "$gh/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-${ARCH}.tar.gz"; \
    tar -xzf "age-v${AGE_VERSION}-linux-${ARCH}.tar.gz"; \
    install -m 0755 age/age age/age-keygen /usr/local/bin/; cd ..; \
    # Trivy
    mkdir trivy && cd trivy; \
    fetch "$gh/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz"; \
    fetch "$gh/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_checksums.txt"; \
    sha256sum --check --ignore-missing "trivy_${TRIVY_VERSION}_checksums.txt"; \
    tar -xzf "trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" trivy; install -m 0755 trivy /usr/local/bin/trivy; cd ..; \
    # gitleaks
    mkdir gitleaks && cd gitleaks; \
    fetch "$gh/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz"; \
    fetch "$gh/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_checksums.txt"; \
    sha256sum --check --ignore-missing "gitleaks_${GITLEAKS_VERSION}_checksums.txt"; \
    tar -xzf "gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" gitleaks; install -m 0755 gitleaks /usr/local/bin/gitleaks; cd ..; \
    # tflint
    mkdir tflint && cd tflint; \
    fetch "$gh/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${ARCH}.zip"; \
    fetch "$gh/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/checksums.txt"; \
    sha256sum --check --ignore-missing checksums.txt; \
    unzip -q "tflint_linux_${ARCH}.zip"; install -m 0755 tflint /usr/local/bin/tflint; cd ..; \
    rm -rf /tmp/tools

WORKDIR /
# El volumen de la sesión de Claude hereda este dueño; sin esto queda como root.
RUN mkdir -p /home/vscode/.claude && chown -R vscode:vscode /home/vscode/.claude

# Sin root por defecto (Trivy DS-0002); devcontainer.json ya usa remoteUser vscode.
USER vscode
