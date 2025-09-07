# Angular .NET Microservices Platform Documentation

## Project Overview

This project implements a modern, scalable, cloud-native application using a microservices architecture. It combines an Angular frontend with .NET 9 backend microservices, orchestrated through an API Gateway, and is deployable via containers using Docker and Kubernetes.

## Architecture Goals

1. **Modular Design**: Separate concerns into independent microservices that can be developed, deployed, and scaled independently.
2. **API Gateway Pattern**: Use Ocelot as a single entry point for client applications, handling cross-cutting concerns like routing, authentication, and CORS.
3. **Container-First Approach**: Ensure all components are containerized for consistent deployment across environments.
4. **DevOps Integration**: Implement CI/CD pipelines for automated testing and deployment.
5. **Scalability**: Design services to be independently scalable in a Kubernetes environment.

## Core Components

### 1. Angular Client Application (Frontend)
- Modern Angular SPA that consumes backend services through the API Gateway
- Implements proper error handling, model definitions, and environment configurations
- Served via Nginx in production environments
- Communicates exclusively with the API Gateway (never directly with microservices)

### 2. API Gateway (Ocelot)
- Single entry point for client applications
- Routes requests to appropriate microservices based on configuration in `ocelot.json`
- Implements cross-cutting concerns:
  - CORS policies to allow cross-origin requests from the client application
  - Request routing and aggregation
  - Potential future enhancements: authentication, rate limiting, caching

### 3. Microservices
Each microservice follows a clean architecture approach with:
- **Controllers**: API endpoints and request handling
- **Services/Repositories**: Business logic and data access
- **Models**: Domain entities and DTOs
- **Data**: Database contexts and migrations

#### a. User Service
- Manages user-related operations (registration, profile management, etc.)
- Has its own dedicated database (UserServiceDB)

#### b. Product Service
- Manages product catalog operations (listing, creating, updating products)
- Has its own dedicated database (ProductServiceDB)
- Implements CRUD operations with proper validation

### 4. Persistence Layer
- Each microservice has its own dedicated SQL Server database
- Database isolation ensures services remain decoupled
- Optional Redis cache for performance optimization

### 5. Deployment & Infrastructure
- Docker containerization for each component
- Docker Compose for local development
- Kubernetes manifests for production deployment
- CI/CD pipelines via GitHub Actions and Azure Pipelines

## Communication Patterns

1. **Synchronous Communication**:
   - Client to API Gateway: HTTP/REST
   - API Gateway to Microservices: HTTP/REST
   
2. **Future Enhancements**:
   - Event-driven communication between services using message brokers (RabbitMQ/Kafka)
   - Service-to-service communication for complex workflows

## Network Configuration

- **Angular Client**: Exposed on port 4200 (development) and port 80 (production)
- **API Gateway**: Exposed on port 5000
- **User Service**: Internal container port 5100, exposed via API Gateway on port 5000
- **Product Service**: Internal container port 5200, exposed via API Gateway on port 5000

- **SQL Server**: Port 1433 (standard SQL Server port)
- **Redis**: Port 6379 (standard Redis port)

## Security Considerations

- CORS policies implemented at the API Gateway level
- Database credentials managed via environment variables
- Future enhancements to include centralized authentication (IdentityServer/Keycloak/Azure AD B2C)

## Development Workflow

### Local Development with Docker Compose
```bash
# Start all services
./start-services.sh  # Linux/macOS
start-services.bat   # Windows

# Access the application
# Angular: http://localhost:4200
# API Gateway: http://localhost:5000
```

### Local Development without Docker
```bash
# Start backend services
dotnet run --project src/ApiGateway/ApiGateway.csproj
dotnet run --project src/Microservices/UserService/UserService.csproj
dotnet run --project src/Microservices/ProductService/ProductService.csproj

# Start Angular client
cd src/ClientApp
npm install
npm start
```

### Kubernetes Deployment
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/
```

## Monitoring and Observability

- Health check endpoints on each service
- Future enhancements to include:
  - OpenTelemetry for distributed tracing
  - Prometheus for metrics collection
  - Grafana for visualization
  - Loki for log aggregation

## Project Roadmap

1. **Current Implementation**:
   - Basic microservices architecture with API Gateway
   - Containerized deployment
   - CRUD operations for key entities

2. **Planned Enhancements**:
   - Centralized authentication
   - Event-driven communication between services
   - Enhanced observability and monitoring
   - Automated integration tests
   - Message broker integration for asynchronous communication

## Conclusion

This Angular .NET Microservices Platform demonstrates a modern approach to building scalable, maintainable applications using microservices architecture. It provides a foundation that can be extended for complex business requirements while maintaining separation of concerns and scalability.
