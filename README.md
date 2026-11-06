<div align="center">

  <img width="250px" height="auto" src="https://raw.githubusercontent.com/loorisr/alpine-llama-cpp-server/refs/heads/main/assets/alpine-llama-image-size-rounded-with-bubbles-500px.png">
  
  Alpine LLaMA is a compact Docker image (about 46 MB, web interface included), providing a [LLaMA.cpp](https://github.com/ggml-org/llama.cpp) HTTP server for language model inference.

</div>

<div align="center">

  [![Available on GHCR](https://img.shields.io/badge/available_on-ghcr.io-181717?style=flat&logo=github&logoColor=white)](https://github.com/loorisr/alpine-llama-cpp-server/pkgs/container/alpine-llama-cpp-server)

</div>

This is a fork of [SamuelTallet/alpine-llama-cpp-server](https://github.com/SamuelTallet/alpine-llama-cpp-server).

## Image tags

This image is built every week from the `master` branch of LLaMA.cpp, not from a release:

- `edge` is the latest build.
- `sha-<commit>` is the build of a given LLaMA.cpp commit.

## CPU requirements

The image is `linux/amd64` only and targets the Intel Core Ultra 7 265K and N100 CPUs. Your CPU needs AVX2 and AVX-VNNI, otherwise the server crashes with an illegal instruction error (`SIGILL`). To check your CPU:

```bash
grep -m1 -o -w avx_vnni /proc/cpuinfo
```


## Use cases

This Docker image is particularly suited for:
- Environments with limited disk space or low bandwidth.
- Servers that cannot do GPU-accelerated inference, e.g. a CPU-only Intel N100 mini PC.

## Examples

### Standalone

You can start a local standalone HTTP inference server who listens at the port 50000 and leverages a [Qwen3 0.6B quantized model](https://huggingface.co/unsloth/Qwen3-0.6B-GGUF) available on Hugging Face (HF) with:

```bash
docker run --name alpine-llama --publish 50000:8080 \
  --volume alpine-llama-models:/models \
  --env LLAMA_ARG_HF_REPO=unsloth/Qwen3-0.6B-GGUF \
  --env LLAMA_API_KEY=sk-xxxx \
  --env LLAMA_ARG_ALIAS=qwen3-0.6b \
  ghcr.io/loorisr/alpine-llama-cpp-server:edge
```

Once the GGUF model file is downloaded from HF (and cached in the `alpine-llama-models` volume), you can use the built-in web interface at [http://localhost:50000](http://localhost:50000), or query your local endpoint using the official [OpenAI TS & JS API library](https://www.npmjs.com/package/openai).

To check this model's structured output capabilities, execute the following Node.js script who extracts metadata from a product description according to a predefined JSON schema:

```js
import OpenAI from "openai";

const inferenceClient = new OpenAI({
  // In a real project, you should use environment variables
  // instead of these hardcoded values:
  apiKey: "sk-xxxx",
  baseURL: "http://127.0.0.1:50000/v1",
});

const productDescription = `UrbanShoes 3.0: These brown and green shoes,
suitable for casual wear, are made of apple leather and recycled rubber.
They are priced at only €2499.90.`; // 👈😄 This is not a typo.

const productSchema = {
  properties: {
    name: { type: "string" },
    materials: { type: "array", items: { type: "string" } },
    colors: { type: "array", items: { type: "string" } },
    price: { type: "number" },
    currency: { type: "string", enum: ["USD", "EUR", "GBP"] },
  },
  required: ["name", "materials", "colors", "price", "currency"],
};

async function extractProductMeta() {
  const response = await inferenceClient.chat.completions.create({
    messages: [
      { role: "user", content: productDescription }
    ],
    model: "qwen3-0.6b",
    temperature: 0.2,
    response_format: {
      type: "json_schema",
      json_schema: {
        strict: true,
        schema: productSchema,
      },
    },
  });

  console.log(response.choices[0].message.content);
}

extractProductMeta();
// > { "name": "UrbanShoes 3.0", "materials": ["apple leather", "recycled rubber"], "colors": ["brown", "green"], "price": 2499.90, "currency": "EUR" }
```

### With a GUI

If you want a fully-featured AI chat GUI, you can use this *docker-compose.yml* file who combines the Alpine LLaMA server with the [LobeChat](https://github.com/lobehub/lobe-chat) interface:

```yaml
services:
  alpine-llama:
    image: ghcr.io/loorisr/alpine-llama-cpp-server:edge
    container_name: alpine-llama
    volumes:
      - ./models/HuggingFaceTB/smollm2-1.7b-instruct-q4_k_m.gguf:/opt/smollm2-1.7b.gguf:ro
    environment:
      - LLAMA_ARG_MODEL=/opt/smollm2-1.7b.gguf
      - LLAMA_ARG_ALIAS=smollm2-1.7b
      - LLAMA_API_KEY=sk-xxxx # In production, be sure to use your own strong secret key.

  lobe-chat:
    image: lobehub/lobe-chat
    container_name: lobe-chat
    depends_on:
      - alpine-llama
    environment:
      - OPENAI_PROXY_URL=http://alpine-llama:8080/v1
      - OPENAI_API_KEY=sk-xxxx
      - OPENAI_MODEL_LIST=smollm2-1.7b
    ports:
      - "3210:3210"
```

Prior to run `docker compose up`, you will need to:

Download the [smollm2-1.7b-instruct-q4_k_m.gguf](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/blob/main/smollm2-1.7b-instruct-q4_k_m.gguf) model file then put it in your *models/HuggingFaceTB* directory (next to the *docker-compose.yml* file). The server runs as the unprivileged user with UID 1000, so this file must be readable by this user.

Once the two services are started, you can optionally configure an AI assistant at [http://localhost:3210](http://localhost:3210) and begin to chat with the SmolLM2-1.7B model:

<img width="600px" height="auto" src="https://github.com/loorisr/alpine-llama-cpp-server/blob/main/assets/alpine-llama-with-lobe-chat.png?raw=true">

## Configuration

You can pass environment variables to the Docker container to configure the Alpine LLaMA server:

| **Environment Variable**  | **Description**                               | **Example Value**                       |
|---------------------------|-----------------------------------------------|-----------------------------------------|
| `LLAMA_ARG_HF_REPO`       | Hugging Face (HF) repository of a model       | `bartowski/Llama-3.2-1B-Instruct-GGUF`  |
| `LLAMA_ARG_HF_FILE`       | and model file to use in this HF repository   | `Llama-3.2-1B-Instruct-Q4_K_M.gguf`     |
| `LLAMA_ARG_MODEL`         | or path to a model file in your hard disk     | `/home/you/LLMs/Llama-3.2-1B.gguf`      |
| `LLAMA_ARG_MODEL_URL`     | or URL to download the model file from.       | `https://your.host/Llama-3.2-1B.gguf`   |
| `LLAMA_API_KEY`           | Key for authenticating HTTP API requests.     | `sk-n5V9UAJt6wRFfZQ4eDYk37uGzbKXdpNj`   |
| `LLAMA_ARG_ALIAS`         | Alias of the model in HTTP API requests.      | `Llama-3.2-1B`                          |
| `LLAMA_CACHE`             | Directory of downloaded models.               | `/models` (default in this image)       |

An exhaustive list of these variables can be found in the official [LLaMA.cpp server documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md#usage).

You can also pass the server's command-line arguments directly, e.g. `docker run ghcr.io/loorisr/alpine-llama-cpp-server:edge --help`.

## License

Project licensed under MIT. See the [LICENSE](LICENSE) file for details.

## Copyright

© 2026 Samuel Tallet
