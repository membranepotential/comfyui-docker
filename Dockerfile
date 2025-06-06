FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

# Install system dependencies
RUN apt-get update && apt-get install -y \
  python3.12 \
  python3-pip \
  python3.12-dev \
  git \
  wget \
  curl \
  ffmpeg \
  python3-opencv \
  yq \
  && rm -rf /var/lib/apt/lists/*

# Create symbolic link for python
RUN ln -s /usr/bin/python3 /usr/bin/python

# Set working directory
WORKDIR /app

# Clone ComfyUI repository
RUN git clone https://github.com/comfyanonymous/ComfyUI.git .

RUN rm /usr/lib/python*/EXTERNALLY-MANAGED && \
  pip install --no-cache-dir torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu128 && \
  pip install --no-cache-dir -r requirements.txt 

# Backup original ComfyUI directories before mounting
RUN cp -r custom_nodes custom_nodes_default && \
  cp -r input input_default && \
  cp -r models models_default && \
  cp -r output output_default

# Set permissions
RUN chmod -R 755 /app

# Expose port
EXPOSE 8188

# Set environment variable for ComfyUI
ENV COMFYUI_PATH=/app

# Copy entrypoint script
COPY --chmod=755 entrypoint.sh /app/entrypoint.sh

CMD ["/app/entrypoint.sh"]
