using namespace System.Net

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
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $ResponseURL = "$(($Request.headers.'x-ms-original-url').replace('/api/ExecListAppId','/api/ExecSAMSetup'))"
    #make sure we get the very latest version of the appid from kv:
    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
        $env:ApplicationID = $Secret.ApplicationID
        $env:TenantID = $Secret.TenantID
    } else {
        Write-Information 'Connecting to Azure'
        Connect-AzAccount -Identity
        $SubscriptionId = $env:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
        try {
            $Context = Get-AzContext
            if ($Context.Subscription) {
                #Write-Information "Current context: $($Context | ConvertTo-Json)"
                if ($Context.Subscription.Id -ne $SubscriptionId) {
                    Write-Information "Setting context to subscription $SubscriptionId"
                    $null = Set-AzContext -SubscriptionId $SubscriptionId
                }
            }
        } catch {
            Write-Information "ERROR: Could not set context to subscription $SubscriptionId."
        }

        $keyvaultname = ($env:WEBSITE_DEPLOYMENT_ID -split '-')[0]
        try {
            $env:ApplicationID = (Get-AzKeyVaultSecret -AsPlainText -VaultName $keyvaultname -Name 'ApplicationID')
            $env:TenantID = (Get-AzKeyVaultSecret -AsPlainText -VaultName $keyvaultname -Name 'TenantID')
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
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
