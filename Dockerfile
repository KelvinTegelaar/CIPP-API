# To enable ssh & remote debugging on app service change the base image to the one below
# FROM mcr.microsoft.com/azure-functions/powershell:4-powershell7.2-appservice
FROM mcr.microsoft.com/azure-functions/powershell:4-powershell7.4
ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true

COPY . /home/site/wwwroot

# Optionally install Proxyman CA certificate if proxyman.pem exists in the build context
RUN if [ -f /home/site/wwwroot/proxyman.pem ]; then \
        apt-get update && apt-get install -y --no-install-recommends ca-certificates && \
        cp /home/site/wwwroot/proxyman.pem /usr/local/share/ca-certificates/proxyman.crt && \
        update-ca-certificates && \
        rm -rf /var/lib/apt/lists/*; \
    fi
