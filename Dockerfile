# Build stage.
# Using a lightweight Alpine Linux base image for a minimal final image size.
FROM alpine:3.24 AS build

# The target platform, set by Docker Buildx.
ARG TARGETPLATFORM

# The LLaMA.cpp git ref to compile: a branch or a full commit SHA.
# The GitHub Action passes the SHA of the current master, so builds are traceable.
ARG LLAMA_GIT_REF=master

# Set the working directory.
WORKDIR /opt/llama.cpp

# Compile the official LLaMA.cpp HTTP Server.
RUN \
    # Never use GGML_NATIVE=ON: it would tie the binary to the CPU of the build machine.
    # On ARM64, the CPU architecture is "armv8-a", the one used by the Raspberry Pi 3+.
    # On AMD64, target the instructions shared by the Core Ultra 7 265K and the Intel N100.
    # There is no AVX-512 on these CPUs. A CPU without AVX2 or AVX-VNNI will crash (SIGILL).
    if [ "$TARGETPLATFORM" = "linux/arm64" ]; then \
        CPU_FLAGS="-DGGML_CPU_ARM_ARCH=armv8-a"; \
    else \
        CPU_FLAGS="-DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_AVX_VNNI=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_BMI2=ON"; \
    fi && \
    # Install build dependencies.
    # Using --no-cache to avoid caching the Alpine packages index.
    apk add --no-cache \
    git \
    g++ \
    make \
    cmake \
    linux-headers \
    openssl-dev && \
    # Checkout the llama.cpp repository to the wanted ref.
    # A shallow fetch (--depth 1) is used to minimize the data transfer.
    git init && \
    git remote add origin https://github.com/ggml-org/llama.cpp && \
    git fetch --depth 1 origin "$LLAMA_GIT_REF" && \
    git checkout FETCH_HEAD && \
    # Configure the CMake build system.
    cmake -B build \
    -DCMAKE_BUILD_TYPE=Release \
    # Disable the native build, then set the CPU flags. See the note above.
    -DGGML_NATIVE=OFF \
    $CPU_FLAGS \
    # Build only the llama-server executable.
    -DLLAMA_BUILD_SERVER=ON \
    # Embed the web interface: its prebuilt assets are downloaded from a Hugging Face bucket.
    -DLLAMA_USE_PREBUILT_UI=ON \
    # musl libc hardcodes thread stacks at 128KB, which causes std::regex stack overflows
    # when cpp-httplib parses long redirect URLs (e.g. HuggingFace Xet storage).
    # musl raises its default thread stack size from this value (PT_GNU_STACK).
    -DCMAKE_EXE_LINKER_FLAGS=-Wl,-z,stack-size=8388608 \
    # Include the GGML lib inside this executable to ease deployment...
    -DBUILD_SHARED_LIBS=OFF && \
    # Compile the llama-server target.
    cmake --build build --target llama-server -j"$(nproc)" && \
    # A failed web interface download is only a CMake warning, so fail the build here.
    grep -aqE 'bundle\.[A-Za-z0-9_-]+\.js' build/bin/llama-server && \
    # Remove non-essential symbols from this executable to save space.
    strip build/bin/llama-server && \
    # Copy this executable in a safe place.
    cp build/bin/llama-server /opt

# Final stage.
# Starting a new stage to create a smaller, cleaner image containing only the runtime env.
FROM alpine:3.24

# Set the working directory.
WORKDIR /opt/llama.cpp

# Install runtime dependencies: C++, OpenSSL & OpenMP.
# Then create an unprivileged user and its models directory.
RUN apk add --no-cache \
    libstdc++ \
    libssl3 \
    libcrypto3 \
    libgomp && \
    adduser -D -u 1000 llama && \
    mkdir /models && \
    chown llama:llama /models

# Copy the compiled llama-server executable from the build stage.
COPY --from=build /opt/llama-server ./

# Models downloaded by the server are stored here. Mount a volume to keep them.
ENV LLAMA_CACHE=/models
VOLUME /models

# 0.0.0.0 allows the server to be accessible from outside the container.
ENV LLAMA_ARG_HOST=0.0.0.0

# Server will listen on 8080. It must be explicit: LLaMA.cpp now defaults to 9931.
ENV LLAMA_ARG_PORT=8080
EXPOSE 8080

# The start period leaves time to download and load a model.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10m --retries=3 \
    CMD wget -qO /dev/null "http://127.0.0.1:${LLAMA_ARG_PORT}/health"

USER llama

# Run the LLaMA.cpp HTTP Server. Arguments of "docker run" are passed to it.
ENTRYPOINT [ "/opt/llama.cpp/llama-server" ]
