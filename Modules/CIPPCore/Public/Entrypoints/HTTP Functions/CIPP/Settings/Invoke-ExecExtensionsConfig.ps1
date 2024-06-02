using namespace System.Net

Function Invoke-ExecExtensionsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
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

        # Check if NinjaOne URL is set correctly and the intance has at least version 5.6
        if ($request.body.NinjaOne) {
            try {
                [version]$Version = (Invoke-WebRequest -Method GET -Uri "https://$(($request.body.NinjaOne.Instance -replace '/ws','') -replace 'https://','')/app-version.txt" -ea stop).content
            } catch {
                throw "Failed to connect to NinjaOne check your Instance is set correctly eg 'app.ninjarmmm.com'"
            }
            if ($Version -lt [version]'5.6.0.0') {
                throw 'NinjaOne 5.6.0.0 is required. This will be rolling out regionally between the end of November and mid-December. Please try again at a later date.'
            }
        }

        $Table = Get-CIPPTable -TableName Extensionsconfig
        foreach ($APIKey in ([pscustomobject]$request.body).psobject.properties.name) {
            Write-Host "Working on $apikey"
            if ($request.body.$APIKey.APIKey -eq 'SentToKeyVault' -or $request.body.$APIKey.APIKey -eq '') {
                Write-Host 'Not sending to keyvault. Key previously set or left blank.'
            } else {
                Write-Host 'writing API Key to keyvault, and clearing.'
                Write-Host "$ENV:WEBSITE_DEPLOYMENT_ID"
                if ($request.body.$APIKey.APIKey) {
                    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                        $Secret = [PSCustomObject]@{
                            'PartitionKey' = $APIKey
                            'RowKey'       = $APIKey
                            'APIKey'       = $request.body.$APIKey.APIKey
                        }
                        Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                    } else {
                        $null = Set-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name $APIKey -SecretValue (ConvertTo-SecureString -String $request.body.$APIKey.APIKey -AsPlainText -Force)
                    }
                }
                $request.body.$APIKey.APIKey = 'SentToKeyVault'
            }
        }
        $body = $request.body | Select-Object * -ExcludeProperty APIKey, Enabled | ConvertTo-Json -Depth 10 -Compress
        $Config = @{
            'PartitionKey' = 'CippExtensions'
            'RowKey'       = 'Config'
            'config'       = [string]$body
        }

        Add-CIPPAzDataTableEntity @Table -Entity $Config -Force | Out-Null
        "Successfully set the configuration. $AddedText"
    } catch {
        "Failed to set configuration: $($_.Exception.message) Linenumber: $($_.InvocationInfo.ScriptLineNumber)"
    }


    $body = [pscustomobject]@{'Results' = $Results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
