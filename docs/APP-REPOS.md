# The app repos

The infra repo only pins images; each app repo builds its own. This page lists what every app repo has, and what's still to do.

**Status:** the changes below are on a `chore/standardisation` branch in each app repo, cut from the branch staging follows (develop for client and server, main for the rest). Nothing is committed yet. rawgraphs-charts is unchanged.

## What every app repo has

| File | What it's for |
|---|---|
| `Makefile` | The standard commands: `make setup` (dependencies and `.env`), `make dev` (run it on this machine), `make build` (the Docker image, as CI builds it), plus `logs`, `migrate`, `charts`, `lint` where they apply |
| `.env.example` | Every setting, with values that work on this machine when the repos sit side by side (infra.dx's README shows the layout). In Docker, infra.dx sets them instead |
| `.nvmrc` or `.python-version` | The Node or Python version (server and client: Node 22, CMS: Node 18, backend: Python 3.11; the AI API ignores `.python-version`, so its Makefile pins 3.11) |
| `Dockerfile`, `.dockerignore` | The production image. No secrets go into it: `.env`, key files and local data are ignored |
| `.github/workflows/image.yaml` | On every push: build the image, tag it with the commit SHA, push it to `ghcr.io/zimmerman-team/dx-<service>`, and tell infra.dx (`update-tag`), which deploys it wherever that branch is followed |

| Repo | Image | `service` input | Active branch (test and staging follow `chore/standardisation` until production moves) |
|---|---|---|---|
| dataxplorer.client (`dx.client/`) | `dx-client` | `client` | `develop` |
| dataxplorer.server (`dx.server/`) | `dx-server` | `server` | `develop` |
| dx.backend | `dx-backend` | `backend` | `main` |
| general-ai-api | `dx-ai-api` | `ai-api` | `main` |
| cms.dataxplorer (`CMS-DX/`) | `dx-cms` | `cms` | `main` |

Before the image workflows can run, each repo needs:

- `DX_INFRA_TOKEN`: a secret holding a token (fine-grained PAT or GitHub App) allowed to run workflows (`actions: write`) in the infra repo, zimmerman-team/dataxplorer. Without it the image is still pushed, with a warning that infra.dx wasn't told.
- After the first push, in each package's settings on GitHub: give the DX repo read access, so its deploy workflow can pull with its own `GITHUB_TOKEN`.

Production runs exactly the image staging tested when its PR copies staging's tag.

## Per repo

### dataxplorer.client (dx.client)

Done:
- Its own `Dockerfile`: builds rawgraphs-charts from a pinned commit (`RAWGRAPHS_REF`, the same one the server pins), links it in, builds the app, and serves `build/` with nginx on port 80, falling back to `index.html` for client-side routes.
- Settings when the container starts, not at build time: for Docker builds a small Vite plugin (`vite.config.ts`) turns every `import.meta.env.VITE_*` into a read from `window.__DX_ENV__`, and `docker/40-env-js.sh` writes the container's `VITE_*` variables to `env.js` when it starts. No app code changed; `yarn dev` still reads `.env`.

### dataxplorer.server (dx.server)

Done (on top of develop's Node 22 migration):
- `Dockerfile` on Node 22, without pm2: it runs `node .`. The server already migrates its schema when it boots; `make migrate` does it on its own.
- The chart renderer runs inside the server (`src/utils/renderChart.ts`) and imports `rawgraphs-charts/lib` from the repo root. The image builds rawgraphs-charts there from a pinned commit (`RAWGRAPHS_REF`, the same one the client pins), with only the runtime dependencies. Locally, `make setup` and `make charts` build the same commit, or your checkout with `RAWGRAPHS_DIR=../rawgraphs-charts`.
- No secrets in the image: `.env` and `google_keys` are ignored. Compose mounts `$SECRETS_DIR/server` at `/app/secrets`; set `GOOGLE_CALENDAR_KEY_FILE=/app/secrets/<file>`.
- `Dockerfile.dev` and the `initialise-server` / `rebuild-ssr` scripts, which built the old renderer, are gone; infra.dx's development setup uses the main Dockerfile.
- Logs go to stdout as well as `logging/dx_server.log` (a winston `Console` transport on both loggers in `src/config/logger/winston-logger.ts`); browser logs posted to `/logging` are marked `[client]`.
- The backend and AI API addresses come from `DX_BACKEND_URL` and `AIAPI_URL` (`src/config/services.ts`), which compose and `.env.example` set. The controllers used to build them from `ENV_TYPE`, calling the old setup's container names (`dx-backend-dev`, `dx-backend-staging`), which broke uploads and every other backend call outside production. Without the variables, the old rule still applies, so servers on the old setup keep working. Errors from an unreachable backend now return its message instead of crashing on `e.response.data`.

Still to do:
- Without pm2's cluster mode it's one Node process per container. If that's not enough, run replicas behind the host's nginx.
- `/ping` should return 200 only when the database is reachable.
- Story rendering (`renderStory` in `stories.controller.ts`) posts to `http://<host>:4400/render/story/<id>`, a service nothing provides any more (dx.backend has no such route), so it fails wherever it's called.

### dx.backend

Done:
- The `Dockerfile` no longer copies `kaggle.json` and `.hdx_configuration.yaml` in; compose mounts them from `$SECRETS_DIR/backend`.
- It's on `python:3.11-bookworm`. The old base, `python:3.11-bullseye` (Debian 11), is end-of-life: its security packages are gone, so the old Dockerfile no longer builds at all.
- Locally, `make setup` makes a `.venv` (with uv when available) and `make dev` runs Flask with reloading. The backend needs `MONGO_USERNAME` and friends set, even to nothing, which `.env.example` does.
- Logs go to stdout as well as `logging/backend.log`: `app.py` adds a stdout handler next to rb-core's file handler. `LOG_LEVEL` sets the stdout level (default INFO; unknown values such as winston's `verbose` fall back to INFO); the file still gets everything from DEBUG up.

Still to do:
- Pin rb-core.backend to a release tag instead of commit `bde8d59`.
- `/health-check` should check MongoDB.

### general-ai-api

Done:
- Makefile, `.env.example` pointing at `../dx.backend/parsed-data-files/`, image workflow. Its `docker-compose.yml` now sets the container path itself.
- Its `/health-check/` sits behind the API key, so compose's health check sends `AIAPI_API_KEY`.

Note: dx.server calls it on port 5000, which macOS's AirPlay Receiver can hold.

### cms.dataxplorer (CMS-DX)

Done:
- Makefile (`make dev` runs Strapi on SQLite, nothing to install), `.env.example`, image workflow. Its Dockerfile is unchanged.

Decided: the live CMS stays where it is (its own compose, its own Postgres) while test and staging move to infra.dx. The `cms` profile stays off on that server, and the client keeps pointing at the existing CMS.

Still to do, as a later step of its own:
- Decide which environment owns the CMS. If one Strapi serves both test and staging, it belongs to neither alone: keep it separate, or give it an environment of its own.
- Move its data: a `pg_dump` from the existing Postgres, restored into `dx-<env>_cms_db_data`, and `public/uploads` copied into `dx-<env>_cms_uploads`. `make import-legacy` doesn't do this yet.
- Keep its database credentials (`CMS_DATABASE_*` must match the existing users), then switch on `cms` in `COMPOSE_PROFILES` and point `VITE_CMS_API` at it.

### rawgraphs-charts

Unchanged, and not a service: the client and server build it in. Both Dockerfiles pin the same commit on `feat/DX-137` (`RAWGRAPHS_REF`); to update the charts, change both. Locally, the client links `../rawgraphs-charts`, and the server's `make charts` builds the pinned commit (or `../rawgraphs-charts` with `RAWGRAPHS_DIR`). rawgraphs-charts' own `yarn build` also still copies itself into `../dx.client` and `../dx.server/rawgraphs-charts`, which is where the server reads it.

### Central monitoring (separate server, planned)

Monitoring moves to one server for all projects, so infra.dx runs none of it. When that server is built (likely from the monitoring repo, formerly Central-Logging), each DX server needs one agent, set up by the monitoring side rather than by infra.dx:

- **Grafana Alloy**, as one container per server, whatever environments run there. It reads all container logs through the Docker socket (labelled with the compose project and service, so `dx-test` and `dx-staging` stay apart), and nginx's logs from `/var/log/nginx`. The server and backend log to stdout, so their log files don't need reading. It pushes logs to the central Loki and metrics to the central Prometheus, over HTTPS with credentials per server.
- **Host and container metrics** from Alloy too (its built-in node and cAdvisor exporters), replacing node-exporter and cAdvisor.
- Only outgoing connections from the DX servers: nothing new is published on them.

Points from the old per-server stack to carry over or drop:
- Promtail is deprecated; Alloy replaces it.
- The backend log is `logging/backend.log`; the old config's `dx_backend.log` path is stale.
- `minio/minio` can no longer be pulled from Docker Hub or Quay, so the central Loki needs other storage (filesystem, or S3-compatible object storage).
- The old stack on each server (`/root/DX/monitoring`) can keep running until the central one is ready.

## Branches while migrating

The old servers keep deploying from the submodule setup until they're cut over (MIGRATION.md), building each repo's `Dockerfile` from `main` and `develop`. So the `chore/standardisation` branches can't all merge straight away:

- **Safe to merge into the active branch any time:** dx.client, general-ai-api and CMS-DX. The old setup doesn't use their new files.
- **Hold until the servers are cut over:** dx.server and dx.backend. The old setup builds their Dockerfiles, and the new ones work differently. Until then, treat these branches as your temp-develop: point the test environment at them with `switch-branch`, merge `develop` (or `main`) into them regularly, and merge them in when staging is cut over.

The infra repo doesn't care what the branches are called, so moving every repo to standard names (`main` and `develop`, plus `staging` if wanted) later is a one-line change per environment in the versions files.
