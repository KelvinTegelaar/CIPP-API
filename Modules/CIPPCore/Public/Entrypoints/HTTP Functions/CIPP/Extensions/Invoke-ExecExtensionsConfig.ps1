using namespace System.Net

Function Invoke-ExecExtensionsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Scope = 'Function')]
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    #Connect-AzAccount -UseDeviceAuthentication
    # Write to the Azure Functions log stream.
    Write-Information 'PowerShell HTTP trigger function processed a request.'
    $results = try {
        if ($Request.Body.CIPPAPI.Enabled) {
            $APIConfig = New-CIPPAPIConfig -ExecutingUser $Request.Headers.'x-ms-client-principal' -resetpassword $Request.Body.CIPPAPI.ResetPassword
            $AddedText = $APIConfig.Results
        }

        # Check if NinjaOne URL is set correctly and the instance has at least version 5.6
        if ($Request.Body.NinjaOne) {
            try {
                [version]$Version = (Invoke-WebRequest -Method GET -Uri "https://$(($Request.Body.NinjaOne.Instance -replace '/ws','') -replace 'https://','')/app-version.txt" -ea stop).content
            } catch {
                throw "Failed to connect to NinjaOne check your Instance is set correctly eg 'app.ninjarmmm.com'"
            }
            if ($Version -lt [version]'5.6.0.0') {
                throw 'NinjaOne 5.6.0.0 is required. This will be rolling out regionally between the end of November and mid-December. Please try again at a later date.'
            }
        }

        $Table = Get-CIPPTable -TableName Extensionsconfig
        foreach ($APIKey in ([pscustomobject]$Request.Body).psobject.properties.name) {
            Write-Information "Working on $apikey"
            if ($Request.Body.$APIKey.APIKey -eq 'SentToKeyVault' -or $Request.Body.$APIKey.APIKey -eq '') {
                Write-Information 'Not sending to keyvault. Key previously set or left blank.'
            } else {
                Write-Information 'writing API Key to keyvault, and clearing.'
                Write-Information "$ENV:WEBSITE_DEPLOYMENT_ID"
                if ($Request.Body.$APIKey.APIKey) {
                    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true') {
                        $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
                        $Secret = [PSCustomObject]@{
                            'PartitionKey' = $APIKey
                            'RowKey'       = $APIKey
                            'APIKey'       = $Request.Body.$APIKey.APIKey
                        }
                        Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
                    } else {
                        $null = Set-AzKeyVaultSecret -VaultName $ENV:WEBSITE_DEPLOYMENT_ID -Name $APIKey -SecretValue (ConvertTo-SecureString -AsPlainText -Force -String $Request.Body.$APIKey.APIKey)
                    }
                }
                if ($Request.Body.$APIKey.PSObject.Properties -notcontains 'APIKey') {
                    $Request.Body.$APIKey | Add-Member -MemberType NoteProperty -Name APIKey -Value 'SentToKeyVault'
                } else {
                    $Request.Body.$APIKey.APIKey = 'SentToKeyVault'
                }
            }
            $Request.Body.$APIKey = $Request.Body.$APIKey | Select-Object * -ExcludeProperty ResetPassword
        }
        $body = $Request.Body | Select-Object * -ExcludeProperty APIKey, Enabled | ConvertTo-Json -Depth 10 -Compress
        $Config = @{
            'PartitionKey' = 'CippExtensions'
            'RowKey'       = 'Config'
            'config'       = [string]$body
        }

        Add-CIPPAzDataTableEntity @Table -Entity $Config -Force | Out-Null

        #Write-Information ($Request.Headers | ConvertTo-Json)
        $AddObject = @{
            PartitionKey = 'InstanceProperties'
            RowKey       = 'CIPPURL'
            Value        = [string]([System.Uri]$Request.Headers.'x-ms-original-url').Host
        }
        Write-Information ($AddObject | ConvertTo-Json -Compress)
        $ConfigTable = Get-CIPPTable -tablename 'Config'
        Add-AzDataTableEntity @ConfigTable -Entity $AddObject -Force

        Register-CIPPExtensionScheduledTasks
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
