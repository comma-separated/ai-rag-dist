# AI RAG Distribution

Public distribution repository for the AI RAG service.

This repository contains installation assets only:

- `install.sh`: Linux installer for the RAG service.
- `.env.example`: example runtime configuration.
- GitHub Release assets: macOS, Linux, and Windows binaries plus checksums.

The source code is private. Published binaries require a valid license key.

## Install

Download and run the installer on a Linux server:

```bash
curl -fsSL https://raw.githubusercontent.com/comma-separated/ai-rag-dist/main/install.sh -o install.sh
chmod +x install.sh
sudo ./install.sh
```

By default, the installer:

- downloads the latest release for the current CPU architecture;
- installs the binary to `/opt/rag/bin/rag`;
- creates the system user and group `rag`;
- writes configuration to `/etc/rag/default/rag.env`;
- creates data and knowledge directories under `/var/lib/rag/default` and `/opt/rag/knowledge/default`;
- starts the systemd service `rag@default.service`.

## Install With License

Pass the license key and API key through environment variables:

```bash
sudo RAG_LICENSE='paste-license-here' RAG_API_KEY='change-me' ./install.sh
```

The generated environment file is:

```text
/etc/rag/default/rag.env
```

Edit it after installation if you need to change LLM endpoints, models, Qdrant, retrieval, or API settings.

Restart the service after configuration changes:

```bash
sudo systemctl restart rag@default.service
```

## Install a Specific Version

Use `RAG_VERSION` to pin a release tag:

```bash
sudo RAG_VERSION=v1.2.3 ./install.sh
```

## Install a Named Instance

Multiple instances can run on the same host. Each instance needs its own name and HTTP port:

```bash
sudo RAG_INSTANCE=bible RAG_HTTP_ADDR=127.0.0.1:8081 RAG_LICENSE='paste-license-here' ./install.sh
sudo RAG_INSTANCE=insitech RAG_HTTP_ADDR=127.0.0.1:8082 RAG_LICENSE='paste-license-here' ./install.sh
```

This creates:

```text
/etc/rag/bible/rag.env
/etc/rag/insitech/rag.env
```

And services:

```text
rag@bible.service
rag@insitech.service
```

## Installer Variables

Common variables:

| Variable | Default | Description |
| --- | --- | --- |
| `RAG_VERSION` | `latest` | Release tag to install, or `latest`. |
| `RAG_INSTANCE` | `default` | Instance name for env, data, and systemd service. |
| `RAG_LICENSE` | empty | License token required by the service. |
| `RAG_API_KEY` | empty | Optional HTTP API key. Empty disables API key auth. |
| `RAG_HTTP_ADDR` | `127.0.0.1:8080` | HTTP bind address. |
| `LLM_EMBED_BASE_URL` | `http://localhost:11434/v1` | OpenAI-compatible embeddings endpoint. |
| `LLM_EMBED_MODEL` | `yxchia/multilingual-e5-base` | Embedding model name. |
| `LLM_ANSWER_BASE_URL` | `http://localhost:11434/v1` | OpenAI-compatible answers endpoint. |
| `LLM_ANSWER_MODEL` | `qwen2.5:7b` | Answer model name. |
| `LLM_ANSWER_API_KEY` | empty | API key for authenticated answer providers. |
| `RAG_OVERWRITE_ENV` | `false` | Set to `true` to replace an existing env file. |

## Release Assets

Each release should publish:

```text
rag_darwin_amd64
rag_darwin_arm64
rag_linux_amd64
rag_linux_arm64
rag_windows_amd64.exe
checksums.txt
```

The checksum file should use standard `sha256sum` format:

```text
<sha256>  rag_linux_amd64
<sha256>  rag_linux_arm64
```

## Service Management

Check status:

```bash
sudo systemctl status rag@default.service
```

View logs:

```bash
sudo journalctl -u rag@default.service -f
```

Restart:

```bash
sudo systemctl restart rag@default.service
```

Stop:

```bash
sudo systemctl stop rag@default.service
```
