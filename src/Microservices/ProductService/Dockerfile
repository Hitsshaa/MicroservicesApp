# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY ./ProductService.csproj ./
RUN dotnet restore ProductService.csproj
COPY . .
RUN dotnet publish ProductService.csproj -c Release -o /app/publish /p:UseAppHost=false

# Runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app
# Install curl in runtime
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=http://+:5200
EXPOSE 5200
HEALTHCHECK --interval=30s --timeout=3s --retries=3 CMD curl -f http://localhost:5200/health || exit 1
ENTRYPOINT ["dotnet", "ProductService.dll"]
