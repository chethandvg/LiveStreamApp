# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

# This stage is used when running from VS in fast mode (Default for Debug configuration)
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS base
#USER $APP_UID
WORKDIR /app
EXPOSE 80
EXPOSE 443


## This stage is used to build the service project
#FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
#ARG BUILD_CONFIGURATION=Release
#WORKDIR /src
#COPY ["Server.csproj", "."]
#RUN dotnet restore "./Server.csproj"
#COPY . .
#WORKDIR "/src/."
#RUN dotnet build "./Server.csproj" -c $BUILD_CONFIGURATION -o /app/build
#
## This stage is used to publish the service project to be copied to the final stage
#FROM build AS publish
#ARG BUILD_CONFIGURATION=Release
#RUN dotnet publish "./Server.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false
#
## This stage is used in production or when running from VS in regular mode (Default when not using the Debug configuration)
#FROM base AS final
#WORKDIR /app
#COPY --from=publish /app/publish .
#ENTRYPOINT ["dotnet", "Server.dll"

# Install FFmpeg
RUN apt-get update && \
    apt-get install -y ffmpeg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["LiveStreamApp.Server/LiveStreamApp.Server.csproj", "LiveStreamApp.Server/"]
COPY ["LiveStreamApp.Client/LiveStreamApp.Client.csproj", "LiveStreamApp.Client/"]
RUN dotnet restore "LiveStreamApp.Server/LiveStreamApp.Server.csproj"
COPY . .
WORKDIR "/src/LiveStreamApp.Server"
RUN dotnet build "LiveStreamApp.Server.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "LiveStreamApp.Server.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "LiveStreamApp.Server.dll"]]