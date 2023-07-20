using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

#Connect-AzAccount -UseDeviceAuthentication
# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$results = try { 
    if ($Request.body.CIPPAPI.Enabled) {
        $APIConfig = New-CIPPAPIConfig -ExecutingUser $request.headers.'x-ms-client-principal' -resetpassword $request.body.CIPPAPI.ResetPassword
        $AddedText = $APIConfig.Results
    }
    $Table = Get-CIPPTable -TableName Extensionsconfig
    foreach ($APIKey in ([pscustomobject]$request.body).psobject.properties.name) {
        Write-Host "Working on $apikey"
        if ($request.body.$APIKey.APIKey -eq "SentToKeyVault" -or $request.body.$APIKey.APIKey -eq "") {
            Write-Host "Not sending to keyvault. Key previously set or left blank."
        }
        else {
            Write-Host "writing API Key to keyvault, and clearing."
            Write-Host "$ENV:WEBSITE_DEPLOYMENT_ID"
            if ($request.body.$APIKey.APIKey) {
                $null = Set-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name $APIKey -SecretValue (ConvertTo-SecureString -String $request.body.$APIKey.APIKey -AsPlainText -Force)
            }
            $request.body.$APIKey = @{ APIKey = "SentToKeyVault" }
        }
    }
    $body = $request.body | Select-Object * -ExcludeProperty APIKey, Enabled |  ConvertTo-Json -Depth 10 -Compress
    $Config = @{
        'PartitionKey' = 'CippExtensions'
        'RowKey'       = 'Config'
        'config'       = [string]$body
    }

    Add-AzDataTableEntity @Table -Entity $Config -Force | Out-Null
    "Successfully set the configuration. $AddedText"
}
catch {
    "Failed to set configuration: $($_.Exception.message) Linenumber: $($_.InvocationInfo.ScriptLineNumber)"
}


$body = [pscustomobject]@{'Results' = $Results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
