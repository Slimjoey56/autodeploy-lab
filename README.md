# AutoDeploy Lab

A small Flask service used to practise automated testing and continuous integration with GitHub Actions. The repository includes a container build so the application can be run consistently outside a local development environment.

## Current functionality

- `GET /` returns the service name and running status.
- `GET /health` returns a health-check response.
- Pytest tests the HTTP status codes and JSON response bodies.
- GitHub Actions runs linting and tests for pushes and pull requests targeting `main`.
- Docker packages the application with Gunicorn for container-based execution.

This repository currently implements continuous integration. It does not automatically publish or deploy the application to a cloud platform.

## Requirements

- Python 3.12+
- pip
- Docker (optional, for container execution)

## Run locally

Create and activate a virtual environment:

```bash
python -m venv .venv
```

Windows PowerShell:

```powershell
.venv\Scripts\Activate.ps1
```

macOS or Linux:

```bash
source .venv/bin/activate
```

Install the application and development dependencies:

```bash
python -m pip install -r requirements-dev.txt
```

Start the development server:

```bash
python app.py
```

The service listens on `http://127.0.0.1:5000`.

## Run quality checks

Run Ruff:

```bash
ruff check .
```

Run the test suite:

```bash
pytest -q
```

## Run with Docker

Build the image:

```bash
docker build -t autodeploy-lab .
```

Start the container:

```bash
docker run --rm -p 5000:5000 autodeploy-lab
```

Check the health endpoint:

```bash
curl http://127.0.0.1:5000/health
```

## Continuous integration

The workflow in `.github/workflows/ci.yml` runs on pushes and pull requests targeting `main`. It installs the development dependencies, checks the code with Ruff, and runs the pytest suite.

A successful workflow confirms that the configured static checks and automated tests passed in the GitHub Actions runner. It does not, by itself, confirm that the application has been deployed.

## Project structure

```text
.
├── .github/
│   └── workflows/
│       └── ci.yml
├── app.py
├── test_app.py
├── requirements.txt
├── requirements-dev.txt
├── pyproject.toml
├── Dockerfile
├── .dockerignore
└── .gitignore
```

## Scope

The project is intentionally small. The next deployment stage would require selecting a hosting target and adding the corresponding deployment workflow and credentials through GitHub Actions secrets or a cloud identity mechanism.

## Author

Jehosaphat Brobbey Impiani  
[GitHub](https://github.com/Slimjoey56)
