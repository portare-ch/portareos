# Build container

**Docker containers**
- Ubuntu
  - jammy     (Ubuntu 22.04)
  - noble     (Ubuntu 24.04)
  - questing  (Ubuntu 25.10)
  - resolute  (Ubuntu 26.04)
- Debian
  - bookworm  (Debian 12)
  - trixie    (Debian 13)

**Build Docker image**

From the PortareOS repository root, build the container used by this tree
and tag it with `portareos-build`:

```
docker build --pull -t portareos-build .
```

See https://docs.docker.com/engine/reference/commandline/build/ for details on `docker build` usage.

The root `Dockerfile` is the one used by CI. The distribution-specific
Dockerfiles listed above remain under `tools/docker/`; they are alternatives,
not the definition used for the published build container.

**Build a PortareOS image inside a container**

From the repository root:

```sh
make docker-SM8550
```

This uses `ghcr.io/portare-ch/portareos-build:latest` and runs the Nova build
with the repository mounted at the same path, as your user. Docker and
Podman are supported. To use the container built above:

```sh
make docker-SM8550 DOCKER_IMAGE=portareos-build
```

Images are written to `target/`. To run the same build directly with Docker:

```sh
docker run --rm --init --user "$(id -u):$(id -g)" \
  -v "$PWD:$PWD" -w "$PWD" -it portareos-build make SM8550
```

Use `--env`, `-e` or `--env-file` to pass build settings to `docker run`:

```sh
docker run --rm --init --user "$(id -u):$(id -g)" \
  -v "$PWD:$PWD" -w "$PWD" -it -e DEBUG_PACKAGES=yes portareos-build make SM8550
```

See https://docs.docker.com/engine/reference/commandline/run/ for details on `docker run` usage.

Use `make docker-shell` for an interactive shell in the published container.
