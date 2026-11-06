# AutoDeploy Lab

A Flask service for practising automated testing, container builds and continuous deployment to AWS.

## Application

- `GET /` returns the service name and running status.
- `GET /health` is the health-check endpoint used by the load balancer.
- Pytest covers the HTTP status codes and JSON response bodies.
- Ruff checks Python code quality.
- Docker packages the service with Gunicorn.
- GitHub Actions builds the image, pushes it to Amazon ECR and deploys it to Amazon ECS Express Mode on Fargate.

## Run locally

Requires Python 3.12 or later.

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

Install dependencies and run the service:

```bash
python -m pip install -r requirements-dev.txt
python app.py
```

Open `http://127.0.0.1:5000` or `http://127.0.0.1:5000/health`.

Run checks:

```bash
ruff check .
pytest -q
```

## Run with Docker

```bash
docker build -t autodeploy-lab .
docker run --rm -p 5000:5000 autodeploy-lab
```

## AWS deployment architecture

```text
GitHub push to main
       |
       v
GitHub Actions
  - Ruff and pytest
  - Build Docker image
       |
       | OIDC role assumption (temporary credentials)
       v
Amazon ECR
       |
       v
Amazon ECS Express Mode
       |
       +-- AWS Fargate task
       +-- Application Load Balancer
       +-- HTTPS endpoint
       +-- Health checks and managed scaling
       +-- CloudWatch logs
```

The deployment workflow is `.github/workflows/deploy.yml`. A successful push to `main` triggers a deployment. The workflow creates the ECS Express Mode service on the first deployment and updates it on later deployments.

## Deployment status

**AWS deployment status: not yet verified.** The repository contains a GitHub Actions deployment workflow and an AWS bootstrap script, but those files do not prove that AWS resources have been created or that a deployment succeeded. A live deployment requires an AWS account, successful execution of `scripts/bootstrap-aws.sh`, the `AWS_REGION` and `AWS_DEPLOY_ROLE_ARN` repository variables, and a successful deployment workflow run with a passing HTTPS health check. Until that run exists, describe this project as deployment-ready infrastructure code rather than a deployed AWS application.

## One-time AWS setup

You need an AWS account with permissions to create IAM roles, an OIDC provider, an ECR repository, and ECS Express Mode resources. The account must have a default VPC with public subnets in the selected Region.

1. Open AWS CloudShell in the Region you intend to use. The bootstrap script defaults to `eu-west-1`; change it if required.
2. Clone this repository in CloudShell:

   ```bash
   git clone https://github.com/Slimjoey56/autodeploy-lab.git
   cd autodeploy-lab
   ```

3. Run the bootstrap script:

   ```bash
   chmod +x scripts/bootstrap-aws.sh
   AWS_REGION=eu-west-1 ./scripts/bootstrap-aws.sh
   ```

   The script creates or configures:
   - A GitHub Actions OIDC identity provider.
   - An IAM deployment role restricted to this repository's `main` branch.
   - The ECS task execution role.
   - The ECS Express Mode infrastructure role.
   - The ECR repository with image scanning and a lifecycle rule retaining the latest 15 images.

4. In GitHub, open **Settings → Secrets and variables → Actions → Variables** and add these repository variables using the values printed by the script:

   | Variable | Value |
   |---|---|
   | `AWS_REGION` | Region used by the bootstrap script |
   | `AWS_DEPLOY_ROLE_ARN` | ARN printed for `GitHubActionsAutoDeployLabRole` |

   These are variables, not secrets. The role ARN is not a credential. GitHub receives short-lived AWS credentials through OIDC; do not create or store AWS access keys in GitHub.

5. Push a commit to `main`, or run **Actions → Deploy to AWS → Run workflow**. The workflow runs checks, builds and pushes the image, then creates or updates the ECS Express Mode service.

6. Open the successful deployment run in GitHub Actions. The job summary contains the HTTPS application URL and health-check URL.

## AWS resources and costs

This setup is not guaranteed to be free. ECS Express Mode has no separate Express Mode fee, but AWS bills for the resources it provisions and uses. Expect charges for:

- Fargate task CPU and memory while the service runs.
- The Application Load Balancer, including hourly and capacity-unit charges.
- Public IPv4 addresses.
- ECR image storage and image transfer.
- CloudWatch logs and metrics.
- Internet data transfer.

The service is configured with one small task (0.25 vCPU and 512 MiB) and a maximum of one task to limit compute usage. The load balancer and other supporting resources still incur costs while provisioned. Check the AWS Pricing Calculator for your selected Region and create an AWS Budget before deploying.

## Removing AWS resources

Deleting the ECS Express Mode service does not automatically remove the ECR repository or IAM roles created by the bootstrap script. To stop ongoing application infrastructure charges, delete the Express Mode service from the ECS console or with the AWS CLI:

```bash
aws ecs list-clusters
aws ecs list-services --cluster default
aws ecs delete-express-gateway-service --service-arn YOUR_SERVICE_ARN --monitor-resources RESOURCE --monitor-mode TEXT-ONLY
```

After the service is deleted, remove the ECR repository if you no longer need the images:

```bash
aws ecr delete-repository --repository-name autodeploy-lab --force
```

The IAM roles and GitHub OIDC provider can also be removed when no longer needed. Do not delete an OIDC provider if other repositories or workflows in your AWS account depend on it.

## Project structure

```text
.
├── .github/workflows/
│   ├── main.yml
│   └── deploy.yml
├── scripts/
│   └── bootstrap-aws.sh
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

This repository demonstrates a small Flask API, automated quality checks, container image publishing and continuous deployment to AWS ECS Express Mode. It is a deployment learning project, not a high-availability production service with a database or application-specific authentication.

## Author

Jehosaphat Brobbey Impiani  
[GitHub](https://github.com/Slimjoey56)
