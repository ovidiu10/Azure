FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build-env   
WORKDIR /otnetcore1

# Copy everything
COPY . ./
# Restore as distinct layers
RUN dotnet restore
# Build and publish a release
RUN dotnet publish -c Release -o out

# Build runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /otnetcore1
COPY --from=build-env /otnetcore1/out .
ENTRYPOINT ["dotnet", "DotNet.Docker.dll"]
ENV DOTNET_EnableDiagnostics=0