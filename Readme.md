# ComfyUI Docker

A complete Docker setup for [ComfyUI](https://github.com/comfyanonymous/ComfyUI), a powerful and modular stable diffusion GUI and backend.

## Prerequisites

- **Docker** and **Docker Compose** installed
- **NVIDIA GPU** with recent drivers
- **NVIDIA Container Toolkit** for GPU support in Docker

### Install NVIDIA Container Toolkit (Ubuntu/Debian)

```bash
# Add NVIDIA package repository
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

# Install nvidia-container-toolkit
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit

# Restart Docker
sudo systemctl restart docker
```

## Quick Start

1. **Clone or download this repository:**

```bash
git clone <this-repo-url>
cd comfyui-docker
```

2. **Create required directories:**

```bash
mkdir -p models output custom_nodes input workflows
```

3. **Start ComfyUI:**

```bash
docker-compose up -d
```

4. **Access ComfyUI:**

   - Open your browser to: **http://localhost:8188**

5. **View logs (optional):**

```bash
docker-compose logs -f comfyui
```

## Usage

### Basic Commands

```bash
# Start ComfyUI
docker-compose up -d

# Stop ComfyUI
docker-compose down

# View logs
docker-compose logs -f comfyui

# Restart ComfyUI
docker-compose restart comfyui

# Update ComfyUI (rebuild container)
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Adding Models

1. **Download models** to the appropriate directory:

   ```bash
   # Example: Add a Stable Diffusion checkpoint
   wget -P models/checkpoints/ "https://example.com/model.safetensors"

   # Example: Add a LoRA
   wget -P models/loras/ "https://example.com/lora.safetensors"
   ```

2. **Refresh ComfyUI** (usually automatic, or restart if needed):
   ```bash
   docker-compose restart comfyui
   ```

### Installing Custom Nodes

1. **Navigate to custom_nodes directory:**

   ```bash
   cd custom_nodes
   ```

2. **Clone the custom node repository:**

   ```bash
   git clone https://github.com/example/comfyui-custom-node.git
   ```

3. **Restart ComfyUI:**
   ```bash
   cd ..
   docker-compose restart comfyui
   ```

## Configuration

### Environment Variables

Modify the `environment` section in `docker-compose.yml`:

```yaml
environment:
  - NVIDIA_VISIBLE_DEVICES=all # Use all GPUs
  - NVIDIA_DRIVER_CAPABILITIES=compute,utility
  - PYTHONUNBUFFERED=1
  # Add custom flags:
  - COMFYUI_FLAGS=--listen 0.0.0.0 --port 8188
```

### Custom Arguments

Pass arguments to ComfyUI by modifying the `command` in `docker-compose.yml`:

```yaml
# Example: Run with CPU only
command: ["--cpu"]

# Example: Custom memory settings
command: ["--lowvram"]

# Example: Multiple arguments
command: ["--listen", "0.0.0.0", "--port", "8188", "--lowvram"]
```

### Port Configuration

Change the port by modifying `docker-compose.yml`:

```yaml
ports:
  - "3000:8188" # Access via localhost:3000
```
