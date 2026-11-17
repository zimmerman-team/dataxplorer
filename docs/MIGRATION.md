# Moving a server off the submodule setup

A one-off per server and environment. The old setup ran from a checkout (`~/DX`, which is `/root/DX` on the servers) with `docker-compose[.<mode>].yml`, built images on the server, and served the client from `/var/www/html/<mode>`. Afterwards the server pulls images and runs `make up`.

The old volumes and folders are left untouched, so going back is stopping the new stack and starting the old one.

## Before you start

- The images for the tags in `versions.<env>.env` exist in GitHub Container Registry ([APP-REPOS.md](APP-REPOS.md)). Until then `make up` can't pull them.
- The server has a self-hosted GitHub runner with the label in the versions file's `RUNNER=` line (`staging` for test and staging, `prod` for production), running as a deploy user in the `docker` group. The deploy workflows run on it.
- That deploy user is logged in to ghcr.io, because the images are private: create a classic GitHub token with only the `read:packages` scope (GitHub's registry doesn't take fine-grained tokens), then on the server, as the deploy user:

  ```bash
  echo <token> | docker login ghcr.io -u <github user> --password-stdin
  ```

  Check it with `docker pull ghcr.io/zimmerman-team/dx-server:<SERVER_TAG from versions.staging.env>`. Give the token an expiry and log in again with a new one before it runs out.

## 1. Check the versions the server runs

The old compose files used `mongo:latest` and `redis:latest`. `compose.yaml` pins `mongo:7.0` and `redis:8.2`; a database can't start on data written by a newer version. On each server:

```bash
docker exec dx-mongo mongod --version | head -1     # dx-mongo-staging, dx-mongo-test, ...
docker exec dx-redis redis-server --version
```

If Mongo or Redis is newer than the pin, raise the pin in `compose.yaml` by PR before going on. If servers differ, pin the newest and upgrade the others first.

## 2. Env file and keys in /opt/dx

```bash
sudo mkdir -p /opt/dx/secrets/backend /opt/dx/secrets/server
sudo chown -R <deploy user> /opt/dx && chmod 700 /opt/dx/secrets
cp .env.example /opt/dx/.env.<env> && chmod 600 /opt/dx/.env.<env>
```

Fill it in from the old `~/DX/.env.<mode>` (`prod`, `staging`, `test`):

- Copy the secrets and URLs across. `REACT_APP_*` names are now `VITE_*`.
- Keep the database credentials exactly as they are: `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD`, `MONGO_USERNAME`, `MONGO_PASSWORD` and `REDIS_PASSWORD`. The data you copy in step 5 already contains its users; the `INITDB` values only create users in an empty database, so new ones would simply fail to log in.
- Drop `MONGO_HOST`, `REDIS_HOST`, `DX_BACKEND_DIR`, `DATA_EXPLORER_SSR`, `PARSED_DATA_FILES_PATH`, `AIAPI_PARSED_DATA_FILES`, `BACKEND_SUBDOMAIN`, `MAIN_DOMAIN`, `APP_SUBDOMAIN` and `API_SUBDOMAIN`: compose sets the in-network values itself.
- Set the ports for this environment (`.env.example` lists them), `SECRETS_DIR=/opt/dx/secrets`, and `ENV_TYPE` / `VITE_ENV_TYPE`.
- Where environments share a server, set `BACKEND_MEMORY_LIMIT` so their backends fit together (for example `4G` each for test and staging).
- Leave `COMPOSE_PROFILES` empty unless this environment runs the CMS.

Move the key files:

```bash
cp /root/DX/dx.backend/kaggle.json /opt/dx/secrets/backend/kaggle.json
cp /root/DX/dx.backend/.hdx_configuration.yaml /opt/dx/secrets/backend/hdx_configuration.yaml
cp -r /root/DX/dx.server/google_keys/. /opt/dx/secrets/server/    # if the server uses Google Calendar
```

The backend won't start with an empty `hdx_configuration.yaml`. If the old one is empty (the old setup created it with `touch`), put `hdx_key: ""` in it.

## 3. Back up

In the old checkout, with the old scripts:

```bash
cd /root/DX && bash scripts/snapshot_db.sh <mode>
```

## 4. Stop the old stack

```bash
cd /root/DX && docker compose -f docker-compose.yml down            # production
cd /root/DX && docker compose -f docker-compose.staging.yml down    # staging (test: docker-compose.test.yml)
```

`down` keeps volumes. The old monitoring stack (`/root/DX/monitoring`) can keep running until the central monitoring server replaces it; infra.dx doesn't run monitoring.

## 5. Copy the data into the new volumes

From a checkout of the infra repo (the runner's, or a clone in `/opt/dx`), as a user that can read the old checkout:

```bash
make import-legacy ENV=<env> ENV_DIR=/opt/dx OLD_DIR=/root/DX
```

It creates the `dx-<env>` volumes, refuses to copy over a database volume that already has data, and copies:

| From | To |
|---|---|
| `dx_dx_mongo_data[_<mode>]`, `dx_dx_redis_data[_<mode>]` | `dx-<env>_mongo_data`, `dx-<env>_redis_data` |
| `dx.backend/parsed-data-files`, `sample-data-files`, `staging`, `logging` | `parsed_data_files`, `sample_data_files`, `staging_files`, `backend_logs` |
| `dx.server/logging` | `server_logs` |

If the old volumes have another prefix (`docker volume ls | grep mongo`), pass `OLD_PROJECT=<prefix>`.

## 6. Start it, and point nginx at the client container

```bash
make up ENV=<env> ENV_DIR=/opt/dx
```

The client is now a container on `CLIENT_PORT` instead of files in `/var/www/html/<mode>`. In `/etc/nginx/sites-available/<mode>-app`, replace the `root` and `try_files` lines with:

```nginx
    location / {
        include proxy_params;
        proxy_pass http://localhost:<CLIENT_PORT>;
    }
```

The server, backend and AI API keep their old ports, so their nginx sites don't change. Then `sudo nginx -t && sudo systemctl reload nginx`.

From here on the workflows do this: merges to `main` deploy the environments whose versions file changed, and images pushed for a branch deploy to every environment that follows it.

## 7. Test and staging on the same server

Run steps 2 to 6 once per environment, `ENV=test` and `ENV=staging`, on the same server:

- Two env files, `/opt/dx/.env.test` and `/opt/dx/.env.staging`, with their own ports (test 8202/4202/4006/5002, staging 8201/4201/4005/5001) and `BACKEND_MEMORY_LIMIT`. They share `/opt/dx/secrets`.
- `make import-legacy` picks each environment's old volumes (`dx_dx_mongo_data_test`, `dx_dx_mongo_data_staging`) and only checks that environment's old containers are stopped, so you can move one environment at a time.
- Both deploy on the server's staging runner: `versions.test.env` says `RUNNER=staging`.
- **The CMS stays as it is.** The existing Strapi and its Postgres keep running from their own compose, outside infra.dx. Keep `COMPOSE_PROFILES` empty in both env files, and set `VITE_CMS_API` and `VITE_CMS_TOKEN` to the values the old env files used, so the client keeps reading the existing CMS. Its port (1337) doesn't clash with anything infra.dx publishes.

Each runs as its own compose project, so deploying or stopping one leaves the other running.

## 8. Clean up, once you're confident

- The old containers' volumes (`dx_dx_*`) and `/root/DX`, and the old monitoring stack once the central one is running.
- The old repo branches (`develop`, `staging`): the infra repo runs from `main` only.
- `/var/www/html/<mode>` and the old cron entries (`crontab -l`; snapshots now run `make backup`).

## Going back

```bash
make down ENV=<env> ENV_DIR=/opt/dx
cd /root/DX && docker compose -f docker-compose.yml up -d    # or the staging/test file
```

and restore the nginx `root` lines.
