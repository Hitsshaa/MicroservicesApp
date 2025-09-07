# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ./ApiGateway.csproj ./
RUN dotnet restore ApiGateway.csproj
COPY . .
RUN dotnet publish ApiGateway.csproj -c Release -o /app/publish /p:UseAppHost=false

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:5000
EXPOSE 5000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD curl -f http://localhost:5000/health || exit 1
ENTRYPOINT ["dotnet", "ApiGateway.dll"]
