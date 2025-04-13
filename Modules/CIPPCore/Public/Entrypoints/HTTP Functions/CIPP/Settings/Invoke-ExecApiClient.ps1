function Invoke-ExecApiClient {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'ApiClients'
    $Action = $Request.Query.Action ?? $Request.Body.Action

    switch ($Action) {
        'List' {
            $Apps = Get-CIPPAzDataTableEntity @Table | Where-Object { ![string]::IsNullOrEmpty($_.RowKey) }
            if (!$Apps) {
                $Apps = @()
            } else {
                $Apps = Get-CippApiClient
                $Body = @{ Results = @($Apps) }
            }
        }
        'ListAvailable' {
            $sitename = $env:WEBSITE_SITE_NAME
            $Apps = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications?`$filter=signInAudience eq 'AzureAdMyOrg' and web/redirectUris/any(x:x eq 'https://$($sitename).azurewebsites.net/.auth/login/aad/callback')&`$top=999&`$select=appId,displayName,createdDateTime,api,web,passwordCredentials&`$count=true" -NoAuthCheck $true -asapp $true -ComplexFilter
            $Body = @{
                Results = @($Apps)
            }
        }
        'AddUpdate' {
            if ($Request.Body.ClientId -or $Request.Body.AppName) {
                $ClientId = $Request.Body.ClientId.value ?? $Request.Body.ClientId
                $AddUpdateSuccess = $false
                try {
                    $ApiConfig = @{
                        Headers = $Request.Headers
                    }
                    if ($ClientId) {
                        $ApiConfig.ClientId = $ClientId
                        $ApiConfig.ResetSecret = $Request.Body.CIPPAPI.ResetSecret
                    }
                    if ($Request.Body.AppName) {
                        $ApiConfig.AppName = $Request.Body.AppName
                    }
                    $APIConfig = New-CIPPAPIConfig @ApiConfig

                    $ClientId = $APIConfig.ApplicationID
                    $AddedText = $APIConfig.Results
                    $AddUpdateSuccess = $true
                } catch {
                    $AddedText = "Could not modify App Registrations. Check the CIPP documentation for API requirements. Error: $($_.Exception.Message)"
                }
            }

            if ($Request.Body.IpRange.value) {
                $IpRange = [System.Collections.Generic.List[string]]::new()
                $regexPattern = '^(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/\d{1,2})?|(?:[0-9A-Fa-f]{1,4}:){1,7}[0-9A-Fa-f]{1,4}(?:/\d{1,3})?)$'
                foreach ($IP in @($Request.Body.IPRange.value)) {
                    if ($IP -match $regexPattern) {
                        $IpRange.Add($IP)
                    }
                }
            } else {
                $IpRange = @()
            }

            if (!$AddUpdateSuccess -and !$ClientId) {
                $Body = @{
                    Results = $AddedText
                }
            } else {
                $ExistingClient = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($ClientId)'"
                if ($ExistingClient) {
                    $Client = $ExistingClient
                    $Client.Role = [string]$Request.Body.Role.value
                    $Client.IPRange = "$(@($IpRange) | ConvertTo-Json -Compress)"
                    $Client.Enabled = $Request.Body.Enabled ?? $false
                    Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Updated API client $($Request.Body.ClientId)" -Sev 'Info'
                    $Results = 'API client updated'
                } else {
                    $Client = @{
                        'PartitionKey' = 'ApiClients'
                        'RowKey'       = "$($ClientId)"
                        'AppName'      = "$($APIConfig.AppName ?? $Request.Body.ClientId.addedFields.displayName)"
                        'Role'         = [string]$Request.Body.Role.value
                        'IPRange'      = "$(@($IpRange) | ConvertTo-Json -Compress)"
                        'Enabled'      = $Request.Body.Enabled ?? $false
                    }
                    $Results = @{
                        resultText = "API Client created with the name '$($Client.AppName)'. Use the Copy to Clipboard button to retrieve the secret."
                        copyField  = $APIConfig.ApplicationSecret
                        state      = 'success'
                    }
                }

                Add-CIPPAzDataTableEntity @Table -Entity $Client -Force | Out-Null
                $Body = @($Results)
            }
        }
        'GetAzureConfiguration' {
            $Owner = $env:WEBSITE_OWNER_NAME
            Write-Information "Owner: $Owner"
            if ($Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                $RGName = $Matches.RGName
            } else {
                $RGName = $env:WEBSITE_RESOURCE_GROUP
            }
            $FunctionAppName = $env:WEBSITE_SITE_NAME
            try {
                $APIClients = Get-CippApiAuth -RGName $RGName -FunctionAppName $FunctionAppName
                $Results = $ApiClients
            } catch {
                $Results = @{
                    Enabled = 'Could not get API clients, ensure you have the appropriate rights to read the Authentication settings.'
                    Error   = (Get-CippException -Exception $_)
                }
            }
            $Body = @{
                Results = $Results
            }
        }
        'SaveToAzure' {
            $TenantId = $env:TenantID
            $Owner = $env:WEBSITE_OWNER_NAME
            if ($Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                $RGName = $Matches.RGName
            } else {
                $RGName = $env:WEBSITE_RESOURCE_GROUP
            }
            $FunctionAppName = $env:WEBSITE_SITE_NAME
            $AllClients = Get-CIPPAzDataTableEntity @Table -Filter 'Enabled eq true' | Where-Object { ![string]::IsNullOrEmpty($_.RowKey) }
            $ClientIds = $AllClients.RowKey
            try {
                Set-CippApiAuth -RGName $RGName -FunctionAppName $FunctionAppName -TenantId $TenantId -ClientIds $ClientIds
                $Body = @{ Results = 'API clients saved to Azure' }
                Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message 'Saved API clients to Azure' -Sev 'Info'
            } catch {
                $Body = @{
                    Results = 'Failed to save allowed API clients to Azure, ensure your function app has the appropriate rights to make changes to the Authentication settings.'
                    Error   = (Get-CippException -Exception $_)
                }
                Write-Information (Get-CippException -Exception $_ | ConvertTo-Json)
            }
        }
        'ResetSecret' {
            $Client = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.ClientId)'"
            if (!$Client) {
                $Results = @{
                    resultText = 'API client not found'
                    severity   = 'error'
                }
            } else {
                $ApiConfig = New-CIPPAPIConfig -ResetSecret -AppId $Request.Body.ClientId -Headers $Request.Headers

                if ($ApiConfig.ApplicationSecret) {
                    $Results = @{
                        resultText = "API secret reset for $($Client.AppName). Use the Copy to Clipboard button to retrieve the new secret."
                        copyField  = $ApiConfig.ApplicationSecret
                        state      = 'success'
                    }
                } else {
                    $Results = @{
                        resultText = "Failed to reset secret for $($Client.AppName)"
                        state      = 'error'
                    }
                }
            }
            $Body = @($Results)
        }
        'Delete' {
            try {
                if ($Request.Body.ClientId) {
                    $ClientId = $Request.Body.ClientId.value ?? $Request.Body.ClientId
                    if ($Request.Body.RemoveAppReg -eq $true) {
                        Write-Information "Deleting API Client: $ClientId from Entra"
                        $App = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$($ClientId)'&`$select=id,appId,web" -NoAuthCheck $true -asapp $true
                        $Id = $App.id
                        if ($Id -and $App.web.redirectUris -like "*$($env:WEBSITE_SITE_NAME)*") {
                            New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$Id" -type DELETE -Body '{}' -NoAuthCheck $true -asapp $true
                            Write-Information "Deleted App Registration for $ClientId"
                        } else {
                            Write-Information "App Registration for $ClientId not found or Redirect URI does not match"
                        }
                    }
                    Write-Information "Deleting API Client: $ClientId from CIPP"
                    $Client = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($ClientId)'" -Property RowKey, PartitionKey
                    Remove-AzDataTableEntity @Table -Entity $Client -Force
                    Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Deleted API client $ClientId" -Sev 'Info'
                    $Body = @{ Results = "API client $ClientId deleted" }
                } else {
                    $Body = @{ Results = "API client $ClientId not found or not a valid CIPP-API application" }
                }
            } catch {
                Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Failed to remove app registration for $ClientId" -Sev 'Warning'
            }
        }
        default {
            $Body = @{Results = 'Invalid action' }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}

