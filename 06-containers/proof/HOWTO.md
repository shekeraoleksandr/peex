# How to fill this folder

`proof/` is empty in the kit — Docker can't run in the assistant's sandboxes,
so you run the scripts on your Mac (Docker Desktop running, `gcloud` logged in
for the registry steps):

```bash
./scripts/collect-proof.sh     # everything, in order
```

Artifacts map 1:1 to the NEBO task's "Outcome Artifacts":

| Artifact required | Where in proof |
|---|---|
| Dockerfile stored in a Git repository with commit history | `01_build.txt` (`git log -- Dockerfile` + the full Dockerfile inlined) |
| Terminal output showing `docker build` | `01_build.txt` |
| Running container + successful port forwarding test (`docker ps`, curl) | `02_run.txt` (`docker ps`, `curl -i localhost:8080`, served `<title>`) |
| CLI output showing image in container registry | `04_registry.txt` (`gcloud artifacts docker images list`, repo listing, build history) |
| Pull and run from registry | `05_pull_and_run.txt` (`docker pull` + `docker run -p 8081:4000` + curl) |
| Short README (base image, build/run/registry commands) | `../README.md` |

Extra evidence beyond the required list:

| Requirement | Where |
|---|---|
| Non-root user | `03_inspect.txt` (`Config.User` = `node`, `id` = uid 1000) |
| Minimal base image / efficient layers | `03_inspect.txt` (`docker history`, image size, multi-stage) |
| No build artifacts/caches in final image | `03_inspect.txt` (explicit absence check for `.git`, `src`, `public`, `.angular`) |
| Reproducible builds | `01_build.txt` (context is `git archive HEAD`; image tagged with the commit SHA) |
| Healthy startup logs | `02_run.txt` (`docker logs`) |

## Screenshots worth adding here
- Browser on `http://localhost:8080/` — the locally built image serving the page.
- Browser on `http://localhost:8081/` — the same page from the registry image.
- GCP console → Artifact Registry → the `movie-links-lending` repository.
