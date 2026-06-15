# 9Router deploy on dockge240

This setup keeps the server simple:

```text
decolua/9router update
  -> storevani/9router sync workflow
  -> GHCR image build
  -> dockge240 pulls ghcr.io/storevani/9router:latest
```

## GitHub repository setup

In `storevani/9router`:

1. Open `Settings -> Actions -> General`.
2. Set workflow permissions to `Read and write permissions`.
3. Enable `Allow GitHub Actions to create and approve pull requests` only if your org requires it for bot pushes.
4. Open `Settings -> Packages` after the first build and make sure `ghcr.io/storevani/9router` is visible to the server. Public packages can be pulled without login. Private packages require `docker login ghcr.io`.

Workflows:

- `.github/workflows/sync-upstream.yml`
  - Runs every 6 hours.
  - Merges `decolua/9router:master` into the fork default branch.
- `.github/workflows/docker-publish.yml`
  - Builds and pushes `ghcr.io/storevani/9router:latest`.
  - Runs on `master`/`main` pushes, tags, manual dispatch, and after upstream sync completes.

## First deploy on dockge240

Run as root:

```bash
mkdir -p /root/9router/data
cd /root/9router
```

Place `docker-compose.yml` in `/root/9router/docker-compose.yml`.

If the GHCR package is private:

```bash
echo "YOUR_GITHUB_PAT" | docker login ghcr.io -u storevani --password-stdin
```

Start the app:

```bash
docker compose pull 9router
docker compose up -d 9router
```

Expected bindings:

```text
127.0.0.1:1455 -> 1455
0.0.0.0:20128 -> 20128
```

Main data stays on the host under:

```text
/root/9router/data
/root/9router/data/db.json
```

## Manual update on dockge240

```bash
cd /root/9router
docker compose pull 9router
docker compose up -d --remove-orphans 9router
docker image prune -f
```

Or run:

```bash
sh /root/9router/update-9router.sh
```

## Optional automatic server pull

Add a cron job on dockge240 if you want the server to poll GHCR:

```cron
*/10 * * * * /bin/sh /root/9router/update-9router.sh >/var/log/9router-update.log 2>&1
```

The container is recreated only when the pulled image differs from the running one.
