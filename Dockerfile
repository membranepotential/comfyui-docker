FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV CUDA_HOME=/usr/local/cuda
ENV PATH=${CUDA_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

# Install system dependencies
RUN apt-get update && apt-get install -y \
  python3 \
  python3-pip \
  python3-dev \
  git \
  wget \
  curl \
  libgl1-mesa-glx \
  libglib2.0-0 \
  libsm6 \
  libxext6 \
  libxrender-dev \
  libgomp1 \
  libgoogle-perftools4 \
  libtcmalloc-minimal4 \
  && rm -rf /var/lib/apt/lists/*

# Create symbolic link for python
RUN ln -s /usr/bin/python3 /usr/bin/python

# Set working directory
WORKDIR /app

# Clone ComfyUI repository
RUN git clone https://github.com/comfyanonymous/ComfyUI.git .

# Upgrade pip and install Python dependencies
RUN python -m pip install --no-cache-dir --upgrade pip

# Install PyTorch with CUDA 12.8 support
RUN pip install --no-cache-dir torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu128

# Install ComfyUI requirements
RUN pip install --no-cache-dir -r requirements.txt && \
  pip --no-cache-dir install \
  xformers \
  opencv-python \
  pillow \
  numpy \
  scipy \
  transformers \
  accelerate \
  safetensors

# Set permissions
RUN chmod -R 755 /app

# Expose port
EXPOSE 8188

# Set environment variable for ComfyUI
ENV COMFYUI_PATH=/app

# Create entrypoint script
RUN echo '#!/bin/bash\n\
  echo "Starting ComfyUI..."\n\
  echo "CUDA Version: $(nvcc --version)"\n\
  echo "GPU Info:"\n\
  nvidia-smi\n\
  echo "Starting ComfyUI server on 0.0.0.0:8188"\n\
  python main.py --listen 0.0.0.0 --port 8188 "$@"' > /app/entrypoint.sh

RUN chmod +x /app/entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
