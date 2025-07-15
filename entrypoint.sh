#!/bin/bash
set -e

# ComfyUI Docker Entrypoint Script
# This script handles initialization and startup of ComfyUI in Docker

echo "=========================================="
echo "🎨 ComfyUI Docker Container Starting..."
echo "=========================================="

# Function to copy default contents from ComfyUI repository
copy_defaults() {
	local file_count
	local owner

	local target_dir="$1"
	local source_dir="$2"

	echo "📁 Checking $target_dir ..."

	if [ -d "$source_dir" ] && [ -d "$target_dir" ]; then
		# Check if target directory is empty or only contains subdirectories we created
		file_count=$(find "$target_dir" -mindepth 1 -type f 2>/dev/null | wc -l)

		if [ "$file_count" -eq 0 ]; then
			echo "   └── Empty directory detected, copying ComfyUI defaults..."

			# Copy all contents from source to target, don't overwrite existing files
			if cp -rn "$source_dir"/* "$target_dir/" 2>/dev/null; then
				echo "   ✅ Successfully copied default $source_dir"
			else
				echo "   ⚠️  No default $source_dir found or failed to copy"
			fi

			# Set proper permissions
			if [ -w "$target_dir" ]; then
				owner=$(stat -c '%u:%g' "$target_dir")
				chown -R "$owner" "$target_dir" 2>/dev/null || true
				chmod -R 755 "$target_dir" 2>/dev/null || true
				echo "   ✅ Permissions updated"
			fi
		else
			echo "   ✅ Directory contains files, preserving existing content"
		fi
	else
		echo "   ⚠️  Source or target directory not found"
	fi
}

# Function to fetch external resources from config.yaml
fetch_external() {
	local filename
	local repo_name

	local config_file="/app/config.yaml"

	echo ""
	echo "🌐 Checking for external downloads configuration..."

	if [ ! -f "$config_file" ]; then
		echo "   ℹ️  No config.yaml found, skipping external downloads"
		return 0
	fi

	echo "   📋 Found config.yaml, processing external downloads..."

	# Process models section
	if yq '.models' "$config_file" >/dev/null 2>&1 && [ "$(yq '.models' "$config_file")" != "null" ]; then
		echo "   📁 Processing models downloads..."

		# Get all keys under models
		yq -r '.models | keys | .[]' "$config_file" | while read -r model_type; do
			echo "      └── Processing $model_type..."

			# Create directory if it doesn't exist
			mkdir -p "/app/models/$model_type"

			# Get URLs for this model type
			yq -r "try .models.${model_type}[]" "$config_file" | while read -r url; do
				if [ -n "$url" ] && [ "$url" != "null" ]; then
					filename=$(basename "$url")
					local filepath="/app/models/$model_type/$filename"

					echo "         ⬇️  Downloading: $filename"
					if wget -q --show-progress --progres=dot:giga -c -O "$filepath" "$url"; then
						echo "         ✅ Downloaded: $filename"
					else
						echo "         ❌ Failed to download: $filename"
						rm -f "$filepath" 2>/dev/null || true
					fi
				fi
			done
		done
	fi

	# Process custom_nodes section
	if yq '.custom_nodes' "$config_file" >/dev/null 2>&1 && [ "$(yq '.custom_nodes' "$config_file")" != "null" ]; then
		echo "   🔧 Processing custom nodes downloads..."

		yq -r 'try .custom_nodes[]' "$config_file" | while read -r url; do
			if [ -n "$url" ] && [ "$url" != "null" ]; then
				repo_name=$(basename "$url" .git)
				local clone_path="/app/custom_nodes/$repo_name"

				if [ ! -d "$clone_path" ]; then
					echo "      ⬇️  Cloning: $repo_name"
					if git clone "$url" "$clone_path"; then
						echo "      ✅ Cloned: $repo_name"
					else
						echo "      ❌ Failed to clone: $repo_name"
						rm -rf "$clone_path" 2>/dev/null || true
					fi
				else
					echo "      ✅ Already exists: $repo_name"
				fi
			fi
		done
	fi

	echo "   🎯 External downloads processing complete"
}

# Setup Python virtual environment
setup_venv() {
	echo ""
	echo "🐍 Setting up Python virtual environment..."

	local venv_dir="/app/venv"

	if [ ! -f "$venv_dir/bin/activate" ]; then
		echo "   📁 Creating virtual environment at $venv_dir..."
		mkdir -p "$venv_dir"
		python -m venv --system-site-packages "$venv_dir"
	else
		echo "   ✅ Virtual environment already exists at $venv_dir"
	fi

	source "$venv_dir/bin/activate"
}

install_requirements() {
	local requirements="$1"
	local name="$2"

	echo ""
	echo "📦 Installing requirements for $name..."

	# Check if requirements.txt exists
	if pip install -r "$requirements"; then
		echo "   ✅ Successfully installed requirements for $name"
	else
		echo "   ❌ Failed to install requirements for $name"
		exit 1
	fi
}

# Function to install requirements for custom nodes
install_custom_node_requirements() {
	local node_name

	echo ""
	echo "📦 Installing custom node requirements..."

	local custom_nodes_dir="/app/custom_nodes"

	if [ ! -d "$custom_nodes_dir" ]; then
		echo "   ℹ️  No custom_nodes directory found, skipping requirements installation"
		return 0
	fi

	local found_requirements=false

	# Iterate through all subdirectories in custom_nodes
	for node_dir in "$custom_nodes_dir"/*; do
		if [ -d "$node_dir" ]; then
			node_name=$(basename "$node_dir")
			local requirements_file="$node_dir/requirements.txt"

			if [ -f "$requirements_file" ]; then
				found_requirements=true
				install_requirements "$requirements_file" "$node_name"
			fi
		fi
	done

	if [ "$found_requirements" = false ]; then
		echo "   ℹ️  No requirements.txt files found in custom nodes"
	fi

	echo "   🎯 Requirements installation complete"
}

# Exit with error if CUDA is not available
validate_cuda() {
	if command -v nvidia-smi >/dev/null 2>&1; then
		echo "   🚀 NVIDIA Driver Info:"
		nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits 2>/dev/null |
			while IFS=, read -r name memory_total memory_used; do
				echo "      └── GPU: ${name// /} (${memory_used}MB/${memory_total}MB used)"
			done

		echo "   🎯 CUDA Version: $(nvcc --version 2>/dev/null | grep 'release' | awk '{print $6}' | cut -c2- || echo 'Not available')"
	else
		echo "   ❌ NVIDIA GPU not detected or nvidia-smi command not available"
		exit 1
	fi
}

# Exit with error if torch has no CUDA support
validate_torch_cuda() {
	local cuda_available
	local gpu_count

	cuda_available=$(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'false')
	if [ "$cuda_available" = "True" ]; then
		gpu_count=$(python -c 'import torch; print(torch.cuda.device_count())' 2>/dev/null || echo '0')
		echo "   ⚡ PyTorch CUDA: Available ($gpu_count GPU(s) detected)"
	else
		echo "   ❌ PyTorch CUDA: Not available (will use CPU)"
		exit 1
	fi
}

main() {
	# Check CUDA availability
	validate_cuda

	# Change to ComfyUI directory
	cd /app

	# Copy defaults for mounted volumes
	echo ""
	echo "🔄 Initializing mounted directories..."

	local dirs=(
		"custom_nodes"
		"input"
		"models"
		"output"
	)

	for dir in "${dirs[@]}"; do
		if [ ! -d "/app/$dir" ]; then
			mkdir -p "/app/$dir"
		fi

		copy_defaults "/app/$dir" "/app/${dir}_default"
	done

	# Fetch external resources
	fetch_external

	# Install requirements for custom nodes
	setup_venv
	install_requirements "/app/requirements.txt" "mounted requirements.txt"
	install_custom_node_requirements

	# Validate PyTorch CUDA support
	validate_torch_cuda

	# Parse command line arguments for special handling
	local comfyui_args=("$@")

	echo ""
	echo "🚀 Starting ComfyUI Server..."
	echo "   🌐 Server will be available at: http://localhost:8188"
	echo "   📁 Models directory: /app/models"
	echo "   📸 Output directory: /app/output"
	echo "   🔧 Custom nodes: /app/custom_nodes"

	echo "   📋 Arguments: ${comfyui_args[*]:-'(default)'}"
	echo ""
	echo "=========================================="
	echo "✨ ComfyUI is ready! Happy generating! ✨"
	echo "=========================================="
	echo ""

	# Execute ComfyUI with all passed arguments
	# Use exec to replace the shell process with ComfyUI
	exec python main.py --listen 0.0.0.0 "${comfyui_args[@]}"
}

main "$@"
