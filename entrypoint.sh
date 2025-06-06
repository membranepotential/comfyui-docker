#!/bin/bash
set -e

# ComfyUI Docker Entrypoint Script
# This script handles initialization and startup of ComfyUI in Docker

echo "=========================================="
echo "🎨 ComfyUI Docker Container Starting..."
echo "=========================================="

# Function to copy default contents from ComfyUI repository
copy_defaults() {
	local target_dir="$1"
	local source_dir="$2"

	echo "📁 Checking $target_dir ..."

	if [ -d "$source_dir" ] && [ -d "$target_dir" ]; then
		# Check if target directory is empty or only contains subdirectories we created
		local file_count=$(find "$target_dir" -mindepth 1 -type f 2>/dev/null | wc -l)

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
				local owner=$(stat -c '%u:%g' "$target_dir")
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
			yq -r "try .models.$model_type[]" "$config_file" | while read -r url; do
				if [ -n "$url" ] && [ "$url" != "null" ]; then
					local filename=$(basename "$url")
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
				local repo_name=$(basename "$url" .git)
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

# Function to display system information
show_system_info() {
	echo ""
	echo "💻 System Information:"
	echo "   📦 Container User: $(whoami) (UID: $(id -u), GID: $(id -g))"
	echo "   🐍 Python Version: $(python --version 2>&1)"
	echo "   🔥 PyTorch Version: $(python -c 'import torch; print(torch.__version__)' 2>/dev/null || echo 'Not available')"

	# Check CUDA availability
	if command -v nvidia-smi >/dev/null 2>&1; then
		echo "   🚀 NVIDIA Driver Info:"
		nvidia-smi --query-gpu=name,memory.total,memory.used --format=csv,noheader,nounits 2>/dev/null |
			while IFS=, read -r name memory_total memory_used; do
				echo "      └── GPU: ${name// /} (${memory_used}MB/${memory_total}MB used)"
			done

		echo "   🎯 CUDA Version: $(nvcc --version 2>/dev/null | grep 'release' | awk '{print $6}' | cut -c2- || echo 'Not available')"

		# Check PyTorch CUDA
		local cuda_available=$(python -c 'import torch; print(torch.cuda.is_available())' 2>/dev/null || echo 'false')
		if [ "$cuda_available" = "True" ]; then
			local gpu_count=$(python -c 'import torch; print(torch.cuda.device_count())' 2>/dev/null || echo '0')
			echo "   ⚡ PyTorch CUDA: Available ($gpu_count GPU(s) detected)"
		else
			echo "   ⚠️  PyTorch CUDA: Not available (will use CPU)"
		fi
	else
		echo "   ⚠️  NVIDIA GPU: Not detected or nvidia-smi not available"
		echo "   💾 Will run in CPU mode"
	fi
}

main() {
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

	# Show system information
	show_system_info

	# Parse command line arguments for special handling
	local comfyui_args=("$@")
	local cpu_mode=false

	for arg in "$@"; do
		case $arg in
		--cpu)
			cpu_mode=true
			;;
		esac
	done

	echo ""
	echo "🚀 Starting ComfyUI Server..."
	echo "   🌐 Server will be available at: http://localhost:8188"
	echo "   📁 Models directory: /app/models"
	echo "   📸 Output directory: /app/output"
	echo "   🔧 Custom nodes: /app/custom_nodes"

	if [ "$cpu_mode" = true ]; then
		echo "   💾 Mode: CPU (GPU disabled)"
	else
		echo "   ⚡ Mode: GPU accelerated"
	fi

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
