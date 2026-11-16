# DX infra

The infra repo for DataXplorer, an AI-powered data exploration platform.

Clone this repo and you can run the whole DX stack. It holds no application code: it says **which image of each service runs in each environment** and how they run together. That covers one compose file, an env template, a Makefile, and a versions file per environment. Each app keeps its own repo, and that repo's CI builds and pushes its image.

| Service | Image (`ghcr.io/zimmerman-team/…`) | App repo | Port in the container |
|---|---|---|---|
| client | `dx-client` | [dataxplorer.client](https://github.com/zimmerman-team/dataxplorer.client) | 80 |
| server | `dx-server` | [dataxplorer.server](https://github.com/zimmerman-team/dataxplorer.server) | 4200 |
| backend | `dx-backend` | [dx.backend](https://github.com/zimmerman-team/dx.backend) | 4004 |
| ai-api | `dx-ai-api` | [general-ai-api](https://github.com/zimmerman-team/general-ai-api) | 5000 |
| cms (profile) | `dx-cms` | [cms.dataxplorer](https://github.com/zimmerman-team/cms.dataxplorer) | 1337 |
| mongo, redis | `mongo:8.0`, `redis:8.0` | | |

[rawgraphs-charts](https://github.com/zimmerman-team/rawgraphs-charts) isn't a service: the client and server build it in, at a commit both Dockerfiles pin. Monitoring isn't here either: it runs on its own server for all projects (see [Logs and monitoring](#logs-and-monitoring)).

## New to the team

Everything here works on macOS and Linux. You need git and make (macOS: `xcode-select --install`; Ubuntu/Debian: `sudo apt install git make`), and Docker to run the stack in containers: [Docker Desktop](https://docs.docker.com/desktop/) on macOS, or [Docker Engine with the Compose plugin](https://docs.docker.com/engine/install/) on Linux, with your user in the `docker` group.

### 1. Set up the folders

Keep everything DX in one folder: this repo, plus the app repos next to it. Call the outer folder what you like; it isn't a git repo.

```bash
mkdir Central-DX && cd Central-DX
```

```bash
git clone https://github.com/zimmerman-team/dataxplorer.git infra.dx
```

```bash
cd infra.dx && make repos
```

You end up with:

```
Central-DX/                  any name, not a git repo
├── infra.dx/                this repo: run every make command here
├── dx.client/               zimmerman-team/dataxplorer.client
├── dx.server/               zimmerman-team/dataxplorer.server
├── dx.backend/              zimmerman-team/dx.backend
├── general-ai-api/          zimmerman-team/general-ai-api
├── CMS-DX/                  zimmerman-team/cms.dataxplorer
└── rawgraphs-charts/        zimmerman-team/rawgraphs-charts, on feat/DX-137 (the client links it locally)
```

- **Keep the folder names.** `make dev` builds each image from `../dx.server` and so on, and the client links `../rawgraphs-charts`. If you already have a clone somewhere else, move it in.
- **`make repos` only clones what's missing**, each repo on the branch staging follows (`versions.staging.env`). It never touches a folder that's already there, so it's safe to run again when a repo is added to `repos.txt`. After that, switch branches inside each repo as usual.

### 2. Run the stack, in Docker or without it

**In Docker.**

```bash
make dev
```

That builds every app image from your checkouts and starts the whole stack; no registry or GitHub token is involved. The first build takes a few minutes; after that Docker reuses what hasn't changed, and each `make dev` rebuilds only what you changed. The first run also creates `.env.development` from `.env.example`. Load the sample data with `make seed`.

**With the CMS.** It's off by default. To run it too:

1. In `.env.development`, set `COMPOSE_PROFILES=cms`, then `make dev`. That builds CMS-DX from `../CMS-DX` and starts it with its own Postgres.
2. Open http://localhost:1337/admin (`CMS_PORT`) and create the first admin user. It starts empty: content isn't copied from the live CMS.
3. To let the client read it, create an API token in Strapi (Settings > API Tokens) and set `VITE_CMS_API=http://localhost:1337/api` and `VITE_CMS_TOKEN=<the token>` in `.env.development`, then `make dev` again.

In Docker the CMS runs in production mode, so its content-type builder is off. To change content types, run `make dev` in `../CMS-DX` instead (no Docker, SQLite). To switch the CMS off again, run `make down` while `cms` is still in `COMPOSE_PROFILES`, then remove it and `make dev`.

**Without Docker.** Every app repo runs on your machine instead. Install once:

| | macOS (Homebrew) | Linux (Ubuntu/Debian) |
|---|---|---|
| Node, through [nvm](https://github.com/nvm-sh/nvm) | the nvm install script | the nvm install script |
| Python 3.11, through [uv](https://docs.astral.sh/uv/) | `brew install uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| MongoDB 8.0 | `brew tap mongodb/brew && brew install mongodb-community@8.0` | `mongodb-org` from [MongoDB's apt repository](https://www.mongodb.com/docs/manual/administration/install-on-linux/) |
| Redis | `brew install redis` | `sudo apt install redis-server` |
| Mongo tools, for `make seed` and backups | `brew install mongosh mongodb/brew/mongodb-database-tools` | `sudo apt install mongodb-mongosh mongodb-database-tools` (MongoDB's apt repository) |

Each repo's `.nvmrc` says which Node it needs (server and client 22, CMS 18) and `make native` switches for you. uv downloads Python 3.11 itself if you don't have it. If MongoDB and Redis already run (as Linux system services usually do after `apt install`), they're used; otherwise `make native` starts them, with their data in `.native/`.

```bash
make native-setup
```

```bash
make native
```

`make native-setup` runs `make setup` in each app repo once (dependencies, and a `.env` from its `.env.example` with values that work in this folder layout). `make native` then runs the backend, AI API, server and client together, each labelled in the output; Ctrl-C stops them all. Use `only="server backend"` to run some of them, and add `cms` to run the CMS too. The client is on http://localhost:3000, the server on 4200, the backend on 4004, the AI API on 5000. Load the sample data with `make seed NATIVE=1`.

### 3. Work on a service

Every app repo has the same Makefile commands, so you can run any one of them on its own:

| In an app repo | What it does |
|---|---|
| `make setup` | Install dependencies, create `.env` from `.env.example` |
| `make dev` | Run the service on this machine, reloading on changes |
| `make build` | Build its Docker image, as CI does |
| `make logs`, `make migrate`, `make charts`, `make lint` | Where they apply |

To mix the two, run one service with `make dev` in its repo and the rest in Docker: in `compose.override.yaml` (copy `compose.override.example.yaml`), switch that service's container off and publish Mongo and Redis, then put the database credentials from `.env.development` into the service's `.env`. The same file adds hot reloading inside Docker, by mounting your source into the container.

## Environments follow branches

Each server environment has a versions file. For every service, it records the branch the environment follows and the image tag it runs:

```
# versions.staging.env
SERVER_BRANCH=develop
SERVER_TAG=9cbe973fa622fae644003e9ce51efe4ec7c56c6b
```

1. A PR is merged in an app repo. Its CI builds the image, tags it with the commit SHA, pushes it to GitHub Container Registry, and runs this repo's `update-tag` workflow with the branch name.
2. `update-tag` writes the new tag into **every** environment that follows that branch for that service, commits it to `main` and deploys those environments. No second PR. If no environment follows the branch, nothing happens.
3. **Production follows no branch.** To release, open a PR that copies the tags you want into `versions.production.env`; merging it deploys production. Copy staging's tags to ship exactly what staging tested.
4. To roll back, open a PR that restores the previous tag. Nothing is rebuilt; the server pulls the old image again.

Branch names live only in the versions files. When the app repos change branches (standard names, or temporary branches during a migration), it's a one-line change per environment.

### Servers that run other branches

- **Point a service at another branch:** run the `switch-branch` workflow (environment, service, branch). It looks up the branch's latest commit, sets `<SERVICE>_BRANCH` and `<SERVICE>_TAG`, and deploys. From then on, every push to that branch deploys there. The branch needs an image first: push to it, or run the app repo's image workflow on it.
- **Add an environment for a feature**, for example `versions.dx-137.env`:
  1. Copy `versions.test.env` to `versions.<name>.env` and set the branches it follows.
  2. On its server: an env file at `/opt/dx/.env.<name>` (see `.env.example`) with ports no other environment on that server uses, and `RUNNER=` in the new versions file set to the label of the self-hosted runner on that server.
  3. Merge the new versions file. It deploys, and from then on follows its branches.

  To remove the environment, run `make down ENV=<name> ENV_DIR=/opt/dx` on the server and delete its versions file.

## Commands

Every command takes `ENV=<environment>` (default `development`). `make help` lists them all.

| Command | What it does |
|---|---|
| `make dev` | Build every app image from your checkouts and start the stack in Docker |
| `make native-setup`, `make native` | Set up, then run, every service on this machine without Docker |
| `make repos` | Clone the app repos next to this one, on the branches the environment follows |
| `make build` | Build every app image from your checkouts, without starting anything |
| `make up ENV=staging` | Pull and start the services with that environment's settings, and wait until they're healthy |
| `make down` | Stop the services (data volumes are kept) |
| `make logs svc=server` | Follow one service's logs |
| `make shell svc=server` | Open a shell in a running container |
| `make migrate` | Run the server's database migrations |
| `make seed` | Load the sample data in `prepopulate-data/` into the database |
| `make backup` / `make restore snapshot=<name>` | Dump the database to `snapshots/`, or restore a dump |
| `make script name=patchCharts` | Run a maintenance script from `scripts/` |
| `make check` | Check the compose files render for every environment |

## How environments run

| | Env file | Versions file | Compose files | Project |
|---|---|---|---|---|
| development | `./.env.development` | `versions.staging.env` | `compose.yaml` + `compose.dev.yaml` (+ `compose.override.yaml`) | `dx-development` |
| any server environment | `/opt/dx/.env.<env>` | `versions.<env>.env` | `compose.yaml` + `compose.prod.yaml` | `dx-<env>` |

Today the server environments are `test`, `staging` and `production`.

- **Env files** hold values that differ per environment, secrets included. Only `.env.example` is committed. On servers they live in `/opt/dx`, owned by the deploy user with `chmod 600`, and every command there takes `ENV_DIR=/opt/dx`.
- **The project name** (`-p dx-<env>`) keeps environments that share a server apart. Services keep one name (`server`, not `server-staging`), and only host ports differ, set in the env file.
- **Ports** are published on `127.0.0.1` only; the host's nginx proxies to them. Databases are never published.
- **Profiles**: `COMPOSE_PROFILES=cms` in the env file runs CMS-DX and its Postgres too.

## Servers

`bash scripts/setup.sh` prepares a server: Docker, the env files and key folder in `/opt/dx`, nginx, nightly backups. Each server also needs:

- **A self-hosted GitHub runner**, running as a user in the `docker` group. Each versions file's `RUNNER=` line names the runner label its environment deploys on (`staging` for test and staging, `prod` for production), so no runner needs relabelling.
- **A one-time `docker login ghcr.io`** as that user, with a classic GitHub token that has only the `read:packages` scope, because the images are private. `make up` and the deploy workflow both pull with it. Run `echo <token> | docker login ghcr.io -u <github user> --password-stdin`, and log in again when the token expires.

### Several environments on one server

Test and staging share a server. Nothing extra is needed beyond what each environment has anyway:

- **One runner.** Both versions files say `RUNNER=staging`, so both environments deploy on the server's existing staging runner, one after the other.
- **One env file each**, `/opt/dx/.env.test` and `/opt/dx/.env.staging`, with their own ports (the defaults in `.env.example` already differ) and `BACKEND_MEMORY_LIMIT` set so the two backends fit the server's memory, for example `4G` each. They can share `/opt/dx/secrets`.
- **Everything else is separate already**: each environment is its own compose project (`dx-test`, `dx-staging`) with its own containers, network and data volumes. Deploying, stopping or restoring one never touches the other.
- **nginx**: `scripts/setup/install_nginx.sh` sets up a site per environment, each pointing at that environment's ports.
- **The CMS** keeps running there as before, outside infra.dx, for now: leave `COMPOSE_PROFILES` empty and point `VITE_CMS_API` at it ([docs/MIGRATION.md](docs/MIGRATION.md), step 7).

## Logs and monitoring

Monitoring runs on a separate server for all projects, so nothing in this repo runs Grafana, Loki or Prometheus. What the DX servers provide for it:

- **Container logs.** Whatever a container writes to stdout and stderr, Docker keeps on its server, rotated at 50 MB per container (the `x-logging` block in `compose.yaml`). Each container is labelled with its compose project and service (`dx-staging`, `server`), so environments sharing a server stay apart.
- **A log agent per server, not per environment.** The monitoring server's setup installs one agent on each DX server (Grafana Alloy). It reads every container's logs through the Docker socket, plus nginx's logs, and pushes them over HTTPS to the central Loki. One agent covers test and staging together.
- **The apps' own logs are on stdout too.** The server's and backend's loggers write every line to stdout as well as to their files (`logging/dx_server.log`, `logging/backend.log`, kept in the `server_logs` and `backend_logs` volumes), so the agent needs nothing but Docker's logs. Browser logs the client posts to the server are marked `[client]`. `LOG_LEVEL` in the env file sets how much both write to stdout (default `info`; the backend's file still gets everything).

Moving a server from the old submodule setup is a one-off with its own guide: [docs/MIGRATION.md](docs/MIGRATION.md). What each app repo must add for this to work is in [docs/APP-REPOS.md](docs/APP-REPOS.md).

## Code management

Style your commits in the following form, to support semantic release.

```
feat: A new feature
fix: A bug fix
docs: Documentation only changes
style: Changes that do not affect the meaning of the code (white-space, formatting, missing semi-colons, etc)
refactor: A code change that neither fixes a bug nor adds a feature
perf: A code change that improves performance
test: Adding missing or correcting existing tests
chore: Changes to the build process or auxiliary tools and libraries such as documentation generation
```
