CloudLift

Containerized Application Migration & Reliability on AWS

CloudLift explores migrating a Node.js and PostgreSQL application from a local Docker environment to AWS. The project combines infrastructure as code, container deployment automation, and reliability testing.

Stack: Node.js · Express · PostgreSQL · Docker · Terraform · AWS ECS Fargate · RDS · ALB · CloudWatch · GitHub Actions

Architecture

The Terraform configuration defines:

An Application Load Balancer routing requests to ECS Fargate tasks across two Availability Zones.

An encrypted Multi-AZ PostgreSQL database in private subnets.

Security groups controlling communication between the load balancer, application, and database.

CloudWatch logs, metrics, and a monitoring dashboard.

Application

The REST API supports customer management and database health checks.

Endpoint

Description

GET /

Service information

GET /health

Application and database health

GET /api/customers

List customers

POST /api/customers

Create a customer

GET /api/stats

Customer count

Security

IAM-based database authentication for the application.

AWS Secrets Manager integration for database initialization.

Certificate-verified TLS connections to PostgreSQL.

Scoped IAM roles and GitHub Actions authentication through OpenID Connect.

Non-root application containers.

CI/CD

The validation workflow checks the application, Terraform configuration, and Docker build. A separate, manually triggered deployment workflow publishes an image to ECR and updates an existing ECS service.

Run Locally

docker compose up --build -d

The API is available at http://localhost:3000.

Run integration and bounded load tests:

python3 scripts/test_api.py http://localhost:3000
python3 scripts/load_test.py http://localhost:3000 --requests 100 --workers 5

Stop the application:

docker compose down

Project Status

Local integration, load, and database-recovery tests have passed. AWS deployment configuration is prepared; cloud deployment and failover validation are in progress.
