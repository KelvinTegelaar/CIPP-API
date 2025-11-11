#Prerequisite: 
#Azure Container Registry / Function App with premium plan 
#enter function app deployment center and choose the ACR way to build 
--------------------------------------------------
# Docker Build & Push pipeline for Azure DevOps
# Works with any container registry (ACR / Docker Hub / GHCR).
# Prerequisite: Create a Service Connection (Docker Registry or Azure Resource Manager for ACR).

trigger:
  branches:
    include:
      - main
      - master

pool:
  vmImage: ubuntu-latest

variables:
  # ---- Registry / Image settings (edit these) ----
  registryServiceConnection: '<YOUR_REGISTRY_SERVICE_CONNECTION_NAME>'  # Service connection name
  imageRepository: '<YOUR_IMAGE_REPOSITORY_NAME>'                       # e.g., 'myapp' or 'org/myapp'
  imageTag: '$(Build.BuildId)'                                          # Unique tag per build

steps:
# 1) Login to the registry
- task: Docker@2
  displayName: Login to container registry
  inputs:
    command: login
    containerRegistry: $(registryServiceConnection)

# 2) Build & Push (push both 'latest' and a unique tag)
- task: Docker@2
  displayName: Build and push image
  inputs:
    command: buildAndPush
    containerRegistry: $(registryServiceConnection)
    repository: $(imageRepository)
    dockerfile: $(Build.SourcesDirectory)/Dockerfile
    buildContext: $(Build.SourcesDirectory)
    tags: |
      latest
      $(imageTag)

# (Optional) If your Dockerfile requires build args, uncomment and adjust:
# - task: Docker@2
#   displayName: Build and push (with build args)
#   inputs:
#     command: buildAndPush
#     containerRegistry: $(registryServiceConnection)
#     repository: $(imageRepository)
#     dockerfile: $(Build.SourcesDirectory)/Dockerfile
#     buildContext: $(Build.SourcesDirectory)
#     buildArguments: |
#       NODE_ENV=production
#       API_BASE_URL=$(API_BASE_URL)
#     tags: |
#       latest
#       $(imageTag)
