Function Invoke-ExecListAppId {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    Get-CIPPAuthentication
    $ResponseURL = "$(($Request.headers.'x-ms-original-url').replace('/api/ExecListAppId','/api/ExecSAMSetup'))"
    #make sure we get the very latest version of the appid from kv:
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
        $env:ApplicationID = $Secret.ApplicationID
        $env:TenantID = $Secret.TenantID
    } else {
        $keyvaultname = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
        try {
            $env:ApplicationID = (Get-CippKeyVaultSecret -AsPlainText -VaultName $keyvaultname -Name 'ApplicationID')
            $env:TenantID = (Get-CippKeyVaultSecret -AsPlainText -VaultName $keyvaultname -Name 'TenantID')
            Write-Information "Retrieving secrets from KeyVault: $keyvaultname. The AppId is $($env:ApplicationID) and the TenantId is $($env:TenantID)"
        } catch {
            Write-Information "Retrieving secrets from KeyVault: $keyvaultname. The AppId is $($env:ApplicationID) and the TenantId is $($env:TenantID)"
            Write-LogMessage -message "Failed to retrieve secrets from KeyVault: $keyvaultname" -LogData (Get-CippException -Exception $_) -Sev 'Error'
            $env:ApplicationID = (Get-CippException -Exception $_)
            $env:TenantID = (Get-CippException -Exception $_)
        }
    }
    $Results = @{
        applicationId = $env:ApplicationID
        tenantId      = $env:TenantID
        refreshUrl    = "https://login.microsoftonline.com/$env:TenantID/oauth2/v2.0/authorize?client_id=$env:ApplicationID&response_type=code&redirect_uri=$ResponseURL&response_mode=query&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default+offline_access+profile+openid&state=1&prompt=select_account"
    }
    return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        }

}
