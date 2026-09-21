# searxng-ollama-web-search

A [SearXNG](https://github.com/searxng/searxng) engine for **Ollama's web search API**
(the official, key-authenticated `POST https://ollama.com/api/web_search` endpoint).

SearXNG ships an `ollama.py` engine, but that one searches Ollama's **model**
catalog at `ollama.com/search` by scraping HTML — it is a model/repo search, not
a web search. This project adds the actual web search API as a first-class
general-purpose engine.

Because the API is authenticated rather than scraped, the engine is not
subject to the CAPTCHA/access-denied suspensions that Google-, Bing-,
DuckDuckGo- and Startpage-based engines routinely hit. For an instance whose
scrapers mostly return `429 Too Many Requests`, that makes it a dependable
general engine — see [Rate limits](#rate-limits) for the caveats.

## Requirements

- A running SearXNG instance (the Docker image is easiest; see below).
- An Ollama API key: <https://ollama.com/settings/keys>. Web search is a cloud
  service — it needs Ollama Pro/Max/Team or pay-as-you-go credits.

## Install

### Docker Compose

```sh
git clone https://github.com/pooh-bear/searxng-ollama-web-search.git
cd searxng-ollama-web-search

mkdir -p searxng
cp settings.example.yml searxng/settings.yml

# SearXNG refuses to boot with the placeholder secret. Generate a real one:
sed -i "s/CHANGE-ME/$(openssl rand -hex 32)/" searxng/settings.yml

# Put your API key in the env file that compose feeds to the container:
cp searxng.env.example searxng.env
chmod 600 searxng.env
$EDITOR searxng.env        # set OLLAMA_API_KEY=...

docker compose up -d
```

Then open <http://localhost:8080/> and search — or check the engine directly:

```sh
curl -s 'http://localhost:8080/search?q=ollama+web+search&format=json' \
  | jq -c '{n: (.results|length), engines: ([.results[].engine]|unique), failed: .unresponsive_engines}'
```

### Existing instance (no compose)

Copy the engine module into your SearXNG tree and restart:

```sh
# Docker:
docker cp engines/ollama_web.py <container>:/usr/local/searxng/searx/engines/ollama_web.py
docker restart <container>

# Bare-metal install, from the SearXNG source root:
cp engines/ollama_web.py searx/engines/ollama_web.py
```

Then add the engine to `settings.yml`:

```yaml
engines:
  - name: ollama web
    engine: ollama_web
    shortcut: oll
    results_per_page: 10   # optional, 1..10; engine default is 10
```

## Configuration

| Setting | Required | Description |
| --- | --- | --- |
| `api_key` | no | Ollama API key. Falls back to the `OLLAMA_API_KEY` environment variable. |
| `results_per_page` | no | Results to request, `1`–`10`. Clamped; engine default `10`. |

The key is resolved in this order: `api_key` in `settings.yml`, then
`OLLAMA_API_KEY` in the process environment. The environment variable is the
recommended option — it keeps the secret out of a file that may be committed.

If neither is set, engine initialization raises and SearXNG logs
`ollama web: engine INIT failed, exception: No API key provided`, followed by
`can't register engines processor (init engine failed)`. The rest of the
instance keeps working and other engines are unaffected; only `ollama web` is
left without a request processor.

> **`max_results` default.** The engine always sends an explicit
> `max_results`, because omitting the field does not fall back to the
> documented default of 5 — in testing, the API returned **3** results for
> every query with the field omitted. Sending `max_results: 5` returns 5 and
> `max_results: 10` returns 10.

> **Docker Compose gotcha.** Values under `environment:` take precedence over
> `env_file:`. Defining `OLLAMA_API_KEY=${OLLAMA_API_KEY:-}` in `environment:`
> resolves to an *empty string* on a host without that variable exported, and
> that empty value silently clobbers the key supplied by `env_file:`. Declare
> the variable in exactly one of the two places. The bundled compose file uses
> only `env_file:`.

## What this engine does not support

Ollama's web search API is a single-shot query, so the engine reports these as
unsupported rather than silently ignoring them:

- **Paging** — one request, at most 10 results.
- **Time ranges** — no date filtering.
- **Safe search** — no safe-search parameter.
- **Language selection** — no language parameter.

Results are mapped to SearXNG's `MainResult` (`title`, `url`, `content`). The API
returns no publication date, so `publishedDate` is left unset. Note that the API
occasionally returns an entry with an empty `title`; the engine passes it
through as-is rather than dropping the result.

## Rate limits

The API is not scraped, so no CAPTCHA suspension applies. In testing, 12 rapid
sequential queries all returned HTTP 200, and the response carried no
`ratelimit`/`retry-after` headers — but Ollama publishes no request-per-minute
figure for web search, and calls do draw on your plan's usage. Treat upstream
quotas as your own responsibility.

## Layout

```
engines/ollama_web.py     the engine, loaded by SearXNG as "ollama_web"
settings.example.yml      minimal settings.yml wiring the engine up
docker-compose.yml        example stack: mounts the engine + env file
searxng.env.example       template for the API key (copy to searxng.env)
scripts/smoke-test.sh     end-to-end check against a running instance
buildkite/pipeline.yml    OpenCodeReview step for Buildkite PR builds (see CI)
buildkite/*.js            adapters that post review findings back to GitHub
```

## Development

The engine follows the conventions of SearXNG's own engine modules, so it can
be dropped into a source checkout and linted/type-checked alongside them. The
smoke test only talks to a running instance over HTTP, so it needs just curl
and jq — point it at any instance with the engine installed:

```sh
./scripts/smoke-test.sh http://localhost:8080
```

## CI: automated PR review

`buildkite/pipeline.yml` runs [OpenCodeReview](https://github.com/alibaba/open-code-review)
on every pull request and posts its findings back to GitHub: a sticky summary
comment plus inline review comments. Re-review on demand by commenting a word
containing `open-code-review` on the PR.

Everything below is one-time pipeline setup. `buildkite/pipeline.yml` only
needs the two secrets and the environment variables described in its header.

### 1. Pipeline

Create a pipeline for this repository in the **Default** cluster, with a
single bootstrap step:

```yaml
steps:
  - command: "buildkite-agent pipeline upload"
```

The steps that actually do the review live in `buildkite/pipeline.yml` and are
uploaded at build time.

### 2. Environment

The review step reads `OCR_LLM_URL` and `OCR_LLM_MODEL`, so the pipeline needs
them in its **pipeline-level** environment (dashboard: *Pipeline Settings →
Environment*, or the `env` key of the pipeline configuration):

```yaml
env:
  OCR_LLM_URL: "https://your-gateway/v1"
  OCR_LLM_MODEL: "your-model"
```

The REST API cannot set pipeline environment: `POST`/`PATCH` on
`/v2/organizations/{org}/pipelines` ignore an `env` body field, and neither
the REST nor the GraphQL pipeline update input exposes one. Set `env` as part
of the pipeline **configuration** (as above) or in the dashboard.

### 3. Secrets

Buildkite secrets are cluster-scoped and are not visible to unclustered
agents, so the pipeline must be in a cluster. Secret **keys are unique per
cluster**; if the cluster already defines `OCR_LLM_TOKEN` / `OCR_GITHUB_TOKEN`
for another pipeline, store this pipeline's own keys and map them onto the env
var names the scripts read (the hash form is `ENV_VAR: SECRET_KEY`):

```yaml
secrets:
  OCR_LLM_TOKEN: SEARXNG_OCR_LLM_TOKEN
  OCR_GITHUB_TOKEN: SEARXNG_OCR_GITHUB_TOKEN
```

Policy-restrict both to this pipeline:

```yaml
- pipeline_slug: <this-pipeline-slug>
  cluster_queue_key: <queue-key>
```

`OCR_GITHUB_TOKEN` is a GitHub token with `pull-requests: write` on this
repository; `OCR_LLM_TOKEN` authenticates to the LLM gateway.

### 4. GitHub triggers

Enable **Build pull requests** and an **Issue comment trigger** with command
word `open-code-review` and match mode *contains*, mirroring the settings in
`buildkite/pipeline.yml`.

Creating a pipeline through the REST API does **not** register a repository
webhook — the dashboard does it for you, the API does not. Without it no
webhook events arrive at all and the pipeline only ever builds when triggered
manually. Register it explicitly:

```sh
curl -X POST \
  -H "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  "https://api.buildkite.com/v2/organizations/{org}/pipelines/{slug}/webhook"
```

`201` means the webhook was created. Verify end-to-end by opening a PR: a
build should appear within seconds, and its `:mag: OpenCodeReview` step should
post the summary comment.

If the pipeline was created through the REST API or the dashboard with the
defaults, also check **Skip pull request builds for existing commits**
(`skip_pull_request_builds_for_existing_commits`). While it is on, a PR whose
branch head already has a successful branch build is not built again when the
PR is opened, so a freshly opened PR gets no review until the next push. Turn
it off for review-on-open:

```sh
curl -X PATCH \
  -H "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"provider_settings":{"skip_pull_request_builds_for_existing_commits":false}}' \
  "https://api.buildkite.com/v2/organizations/{org}/pipelines/{slug}"
```

## Contributions

Contributions welcome — please submit a PR and tag @pooh-bear.

## License

AGPL-3.0-or-later, matching SearXNG itself. See [LICENSE](LICENSE).
