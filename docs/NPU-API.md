# NPU LLM API Guide

This guide covers the rkllama API service for running LLM inference on the RK3588 NPU.

## Overview

Each node runs an rkllama Flask server as a systemd service, providing an OpenAI-compatible API for LLM inference on the NPU.

| Node | IP | API Endpoint |
|------|-----|--------------|
| node1 | 10.10.88.73 | http://10.10.88.73:8080 |
| node2 | 10.10.88.74 | http://10.10.88.74:8080 |
| node3 | 10.10.88.75 | http://10.10.88.75:8080 |
| node4 | 10.10.88.76 | http://10.10.88.76:8080 |

**Performance:** ~7-8 tokens/second per node with DeepSeek 1.5B model.

## Service Management

```bash
# Check service status
systemctl status rkllama

# View logs
journalctl -u rkllama -f

# Restart service
systemctl restart rkllama

# Stop/Start
systemctl stop rkllama
systemctl start rkllama
```

## API Endpoints

### GET / - Health Check

```bash
curl http://10.10.88.73:8080/
```

Response:
```json
{"message": "Welcome to RKLLama !", "github": "https://github.com/notpunhnox/rkllama"}
```

### GET /models - List Available Models

```bash
curl http://10.10.88.73:8080/models
```

Response:
```json
{"models": ["DeepSeek-R1-1.5B", "tinyllama-1.1b", "Qwen-1_8B-Chat"]}
```

### GET /current_model - Show Loaded Model

```bash
curl http://10.10.88.73:8080/current_model
```

Response (no model loaded):
```json
{"error": "No models are currently loaded."}
```

Response (model loaded):
```json
{"model": "DeepSeek-R1-1.5B"}
```

### POST /load_model - Load a Model

Load a model into NPU memory. Only one model can be loaded at a time.

```bash
curl -X POST http://10.10.88.73:8080/load_model \
  -H "Content-Type: application/json" \
  -d '{"model_name": "DeepSeek-R1-1.5B"}'
```

Response:
```json
{"message": "Model DeepSeek-R1-1.5B loaded successfully."}
```

### POST /unload_model - Unload Current Model

```bash
curl -X POST http://10.10.88.73:8080/unload_model
```

Response:
```json
{"message": "Model unloaded successfully."}
```

### POST /generate - Run Inference

Generate a response from the loaded model. Requires a model to be loaded first.

**Request Format:**
```json
{
  "messages": [
    {"role": "user", "content": "Your prompt here"}
  ],
  "stream": false
}
```

**Example - Non-streaming:**
```bash
curl -X POST http://10.10.88.73:8080/generate \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "What is the capital of France?"}]
  }'
```

Response:
```json
{
  "id": "rkllm_chat",
  "object": "rkllm_chat",
  "created": null,
  "choices": [{
    "role": "assistant",
    "content": "The capital of France is Paris.",
    "logprobs": null,
    "finish_reason": "stop"
  }],
  "usage": {
    "prompt_tokens": 28,
    "completion_tokens": 15,
    "tokens_per_second": 7.5,
    "total_tokens": 43
  }
}
```

**Example - Streaming:**
```bash
curl -X POST http://10.10.88.73:8080/generate \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [{"role": "user", "content": "Count to 5"}],
    "stream": true
  }'
```

Streaming returns newline-delimited JSON chunks.

**Multi-turn Conversation:**
```bash
curl -X POST http://10.10.88.73:8080/generate \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "My name is Alice."},
      {"role": "assistant", "content": "Hello Alice! Nice to meet you."},
      {"role": "user", "content": "What is my name?"}
    ]
  }'
```

## Python Client Example

```python
import requests

BASE_URL = "http://10.10.88.73:8080"

# Load model
requests.post(f"{BASE_URL}/load_model", json={"model_name": "DeepSeek-R1-1.5B"})

# Generate response
response = requests.post(f"{BASE_URL}/generate", json={
    "messages": [{"role": "user", "content": "Hello!"}]
})

data = response.json()
print(data["choices"][0]["content"])
print(f"Speed: {data['usage']['tokens_per_second']:.1f} tok/s")
```

## Load Balancing Across Nodes

Distribute requests across all 4 nodes for higher throughput:

```python
import requests
import random

NODES = [
    "http://10.10.88.73:8080",
    "http://10.10.88.74:8080",
    "http://10.10.88.75:8080",
    "http://10.10.88.76:8080",
]

def generate(prompt):
    node = random.choice(NODES)
    response = requests.post(f"{node}/generate", json={
        "messages": [{"role": "user", "content": prompt}]
    })
    return response.json()
```

For production, consider:
- Kubernetes Service with LoadBalancer
- HAProxy or nginx for health-checked load balancing
- Request queuing for parallel inference

## Model Management

### Pre-installed Model

The DeepSeek-R1-1.5B model is automatically downloaded and configured:

| Model | Size | Path |
|-------|------|------|
| DeepSeek-R1-1.5B | 1.9 GB | /opt/rkllama/models/deepseek-1.5b.rkllm |

### Adding Custom Models

1. Download an RKLLM-format model from HuggingFace
2. Create a model directory and Modelfile:

```bash
# On each node
mkdir -p ~/RKLLAMA/models/MyModel

cat > ~/RKLLAMA/models/MyModel/Modelfile << 'EOF'
FROM="mymodel.rkllm"
HUGGINGFACE_PATH="username/tokenizer-repo"
SYSTEM=""
TEMPERATURE=1.0
EOF

# Copy or symlink the model file
ln -s /path/to/mymodel.rkllm ~/RKLLAMA/models/MyModel/mymodel.rkllm
```

3. Restart rkllama and load the model:

```bash
systemctl restart rkllama
curl -X POST http://localhost:8080/load_model -H "Content-Type: application/json" -d '{"model_name": "MyModel"}'
```

### Compatible Models

Models must be in RKLLM format (converted using rknn-toolkit2). Pre-converted models:

- [DeepSeek-R1-Distill-Qwen-1.5B](https://huggingface.co/kautism/DeepSeek-R1-Distill-Qwen-1.5B-RK3588S-RKLLM1.1.4)
- Search HuggingFace for "rkllm" format models

## NPU Monitoring

Check NPU status while running inference:

```bash
# Driver version
cat /sys/kernel/debug/rknpu/version
# Output: RKNPU driver: v0.9.8

# Core utilization
cat /sys/kernel/debug/rknpu/load
# Output: NPU load:  Core0: 45%, Core1: 42%, Core2: 44%,
```

Watch NPU load in real-time:
```bash
watch -n 0.5 cat /sys/kernel/debug/rknpu/load
```

## Troubleshooting

### Model fails to load

```bash
# Check service logs
journalctl -u rkllama -n 50

# Verify model file exists
ls -la ~/RKLLAMA/models/DeepSeek-R1-1.5B/

# Check Modelfile syntax
cat ~/RKLLAMA/models/DeepSeek-R1-1.5B/Modelfile
```

### API returns 400 Bad Request

Ensure you're using the correct request format:
- Use `messages` array, not `prompt` string
- Include `Content-Type: application/json` header

### NPU device not found

```bash
# Check device exists
ls -la /dev/dri/renderD129

# Check kernel driver loaded
dmesg | grep -i rknpu

# Verify using vendor kernel (6.1.x)
uname -r
```

### Service won't start

```bash
# Check for port conflicts
ss -tlnp | grep 8080

# Verify Python venv
/opt/rkllama/venv/bin/python3 --version

# Test manually
/opt/rkllama/venv/bin/python3 /opt/rkllama/server.py --target_platform rk3588 --port 8080
```

## Configuration

Service configuration is in `/etc/systemd/system/rkllama.service`:

| Setting | Default | Description |
|---------|---------|-------------|
| Port | 8080 | API listen port |
| Platform | rk3588 | Target NPU platform |
| WorkingDirectory | /opt/rkllama | Server directory |

To change the port:

```bash
# Edit defaults in Ansible
# ansible/roles/rknn/defaults/main.yml
rkllama_service_port: 8081

# Or edit service file directly
sudo systemctl edit rkllama
# Add: Environment="PORT=8081"
sudo systemctl daemon-reload
sudo systemctl restart rkllama
```

## Related Documentation

- [RKNN-LLM Repository](https://github.com/airockchip/rknn-llm)
- [rkllama Server](https://github.com/jfreed-dev/rkllama)
- [RKNN Toolkit2](https://github.com/airockchip/rknn-toolkit2) (for model conversion)
