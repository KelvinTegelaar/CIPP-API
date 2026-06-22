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
            $Results = [System.Collections.Generic.List[object]]::new()

            # Authorize the role assignment BEFORE any side effects (app registration /
            # secret creation). A caller may only assign a role whose effective
            # permissions are a subset of their own, and may only modify an existing
            # client whose current role is likewise within their grant. This blocks
            # privilege escalation via the ApiClients table (e.g. editor -> superadmin).
            $RequestedRole = [string]$Request.Body.Role.value
            $RolesToAuthorize = [System.Collections.Generic.List[string]]::new()
            $RolesToAuthorize.Add($RequestedRole)
            $ExistingClientForAuth = $null
            $AuthClientId = $Request.Body.ClientId.value ?? $Request.Body.ClientId
            if ($AuthClientId) {
                $ExistingClientForAuth = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($AuthClientId)'"
                if ($ExistingClientForAuth) {
                    $RolesToAuthorize.Add([string]$ExistingClientForAuth.Role)
                }
            }
            $RoleGrant = Test-CippApiClientRoleGrant -Request $Request -Role $RolesToAuthorize
            if (-not $RoleGrant.Allowed) {
                Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Blocked API client role assignment: $($RoleGrant.Message)" -Sev 'Warning'
                $Body = @(@{
                        resultText = $RoleGrant.Message
                        state      = 'error'
                    })
                break
            }

            if ($Request.Body.ClientId -or $Request.Body.AppName) {
                $ClientId = $Request.Body.ClientId.value ?? $Request.Body.ClientId
                $AddUpdateSuccess = $false
                $RetryClientId = $null
                $RetryObjectId = $null
                try {
                    $ApiConfig = @{
                        Headers = $Request.Headers
                    }
                    if ($ClientId) {
                        $ApiConfig.ClientId = $ClientId
                        $ApiConfig.ResetSecret = [bool]$Request.Body.CIPPAPI.ResetSecret
                    }
                    if ($Request.Body.AppName) {
                        $ApiConfig.AppName = $Request.Body.AppName
                    }
                    $APIConfig = New-CIPPAPIConfig @ApiConfig

                    $ClientId = $APIConfig.ApplicationID
                    $AddedText = $APIConfig.Results
                    $AddUpdateSuccess = $true
                } catch {
                    $RetryClientId = [string]$_.Exception.Data['ApplicationID']
                    $RetryObjectId = [string]$_.Exception.Data['ApplicationObjectID']

                    $AddedText = @{
                        resultText = "Could not modify App Registrations. Check the CIPP documentation for API requirements. Error: $($_.Exception.Message)"
                        state      = 'error'
                    }

                    if ($RetryClientId) {
                        $AddedText.retryAvailable = $true
                        $AddedText.retryPayload = @{
                            RetrySetup = $true
                            ClientId   = $RetryClientId
                            CIPPAPI    = @{
                                ResetSecret = $true
                            }
                        }
                        if ($RetryObjectId) {
                            $AddedText.retryPayload.ApplicationObjectID = $RetryObjectId
                        }
                    }
                }
            }

            $IPValidationErrors = [System.Collections.Generic.List[string]]::new()
            if ($Request.Body.IpRange.value) {
                $IpRange = [System.Collections.Generic.List[string]]::new()
                $regexPattern = '^(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/\d{1,2})?|(?:[0-9A-Fa-f]{1,4}:){1,7}[0-9A-Fa-f]{1,4}(?:/\d{1,3})?)$'
                foreach ($IP in @($Request.Body.IPRange.value)) {
                    $IP = $IP.Trim()
                    if ($IP -match $regexPattern) {
                        $IpRange.Add($IP)
                    } else {
                        $IPValidationErrors.Add("'$IP' is not a valid IP address or CIDR range.")
                    }
                }
            } else {
                $IpRange = @()
            }

            if (!$AddUpdateSuccess) {
                if ($AddedText) {
                    $Results.Add($AddedText)
                }
            } else {
                $ExistingClient = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($ClientId)'"
                if ($ExistingClient) {
                    $Client = $ExistingClient
                    $Client.Role = [string]$Request.Body.Role.value
                    $Client.IPRange = "$(@($IpRange) | ConvertTo-Json -Compress)"
                    $Client.Enabled = $Request.Body.Enabled ?? $false
                    $Client | Add-Member -NotePropertyName 'MCPAllowed' -NotePropertyValue ([bool]($Request.Body.MCPAllowed ?? $false)) -Force
                    Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Updated API client $($Request.Body.ClientId)" -Sev 'Info'
                    if ($APIConfig.ApplicationSecret) {
                        $Results.Add(@{
                                resultText = "API client updated and application secret reset for '$($Client.AppName)'. Use the Copy to Clipboard button to retrieve the new secret."
                                copyField  = $APIConfig.ApplicationSecret
                                state      = 'success'
                            })
                    } else {
                        $Results.Add('API client updated')
                    }
                } else {
                    $Client = @{
                        'PartitionKey' = 'ApiClients'
                        'RowKey'       = "$($ClientId)"
                        'AppName'      = "$($APIConfig.AppName ?? $Request.Body.ClientId.addedFields.displayName)"
                        'Role'         = [string]$Request.Body.Role.value
                        'IPRange'      = "$(@($IpRange) | ConvertTo-Json -Compress)"
                        'Enabled'      = $Request.Body.Enabled ?? $false
                        'MCPAllowed'   = [bool]($Request.Body.MCPAllowed ?? $false)
                    }
                    $Results.Add(@{
                            resultText = "API Client created with the name '$($Client.AppName)'. Use the Copy to Clipboard button to retrieve the secret."
                            copyField  = $APIConfig.ApplicationSecret
                            state      = 'success'
                        })
                }

                Add-CIPPAzDataTableEntity @Table -Entity $Client -Force | Out-Null

                # When this client is MCP-enabled, configure its app registration as the MCP OAuth
                # resource (host identifier URIs + v2 tokens) so the Claude connector flow can resolve it.
                if ([bool]($Request.Body.MCPAllowed ?? $false)) {
                    try {
                        $null = Set-CIPPMCPClientApp -AppId $ClientId -Headers $Request.Headers
                        $Results.Add('MCP resource URIs and v2 tokens configured on the app registration. Run Save to Azure to apply the changes.')
                    } catch {
                        $Results.Add(@{
                                resultText = "Client saved, but MCP app configuration failed: $($_.Exception.Message)"
                                state      = 'warning'
                            })
                    }
                }
            }

            if ($IPValidationErrors.Count -gt 0) {
                foreach ($ValidationError in $IPValidationErrors) {
                    $Results.Add(@{
                            resultText = $ValidationError
                            state      = 'warning'
                        })
                }
            }

            if (!$AddUpdateSuccess) {
                $Body = @{
                    Results = @($Results)
                }
            } else {
                $Body = @($Results)
            }
        }
        'GetAzureConfiguration' {
            if ($env:WEBSITE_RESOURCE_GROUP) {
                $RGName = $env:WEBSITE_RESOURCE_GROUP
            } else {
                $Owner = $env:WEBSITE_OWNER_NAME
                if ($env:WEBSITE_SKU -ne 'FlexConsumption' -and $Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                    $RGName = $Matches.RGName
                } else {
                    Write-Information "Could not determine resource group from environment variables. Owner: $Owner"
                    $RGName = $null
                }
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
            if ($env:WEBSITE_RESOURCE_GROUP) {
                $RGName = $env:WEBSITE_RESOURCE_GROUP
            } else {
                $Owner = $env:WEBSITE_OWNER_NAME
                if ($env:WEBSITE_SKU -ne 'FlexConsumption' -and $Owner -match '^(?<SubscriptionId>[^+]+)\+(?<RGName>[^-]+(?:-[^-]+)*?)(?:-[^-]+webspace(?:-Linux)?)?$') {
                    $RGName = $Matches.RGName
                } else {
                    Write-Information "Could not determine resource group from environment variables. Owner: $Owner"
                    $RGName = $null
                }
            }
            $FunctionAppName = $env:WEBSITE_SITE_NAME
            $AllClients = Get-CIPPAzDataTableEntity @Table -Filter 'Enabled eq true' | Where-Object { ![string]::IsNullOrEmpty($_.RowKey) }
            $ClientIds = $AllClients.RowKey
            # MCPAllowed can round-trip from table storage as a bool or a string; compare on string form.
            $McpClientIds = @($AllClients | Where-Object { "$($_.MCPAllowed)" -eq 'True' } | ForEach-Object { $_.RowKey })
            Write-Information "[ExecApiClient] MCP clients resolved for audiences/scope: $($McpClientIds -join ', ')"
            try {
                Set-CippApiAuth -RGName $RGName -FunctionAppName $FunctionAppName -TenantId $TenantId -ClientIds $ClientIds -McpClientIds $McpClientIds

                # Advertise the MCP resource scope via App Service PRM so the Claude connector requests
                # a scope that matches the resource app (clears AADSTS9010010). Cleared when no MCP clients.
                if ($McpClientIds.Count -gt 0 -and $env:WEBSITE_HOSTNAME) {
                    $null = Update-CIPPAzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $RGName -AppSetting @{ 'WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES' = "https://$($env:WEBSITE_HOSTNAME)/user_impersonation" }
                } else {
                    $null = Update-CIPPAzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $RGName -AppSetting @{} -RemoveKeys @('WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES')
                }

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
                    state      = 'error'
                }
            } else {
                # Block resetting the secret of a client whose role outranks the caller;
                # otherwise an editor could harvest a working superadmin secret.
                $RoleGrant = Test-CippApiClientRoleGrant -Request $Request -Role ([string]$Client.Role)
                if (-not $RoleGrant.Allowed) {
                    Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Blocked API client secret reset for $($Request.Body.ClientId): $($RoleGrant.Message)" -Sev 'Warning'
                    $Results = @{
                        resultText = $RoleGrant.Message
                        state      = 'error'
                    }
                    $Body = @($Results)
                    break
                }
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
        'RepairUri' {
            $Client = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.ClientId)'"
            if (!$Client) {
                $Results = @{
                    resultText = 'API client not found'
                    state      = 'error'
                }
            } else {
                try {
                    $RepairResult = Repair-CippApiIdentifierUri -AppId $Request.Body.ClientId

                    if ($RepairResult.Fixed) {
                        Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Repaired identifier URI for $($Client.AppName) $($RepairResult.Message)" -Sev 'Info'
                        $Results = @{
                            resultText = "Identifier URI fixed for $($Client.AppName). $($RepairResult.Message)"
                            state      = 'success'
                        }
                    } else {
                        $Results = @{
                            resultText = "Identifier URI already correct for $($Client.AppName). $($RepairResult.Message)"
                            state      = 'info'
                        }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Failed to repair identifier URI for $($Client.AppName) $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                    $Results = @{
                        resultText = "Failed to repair identifier URI for $($Client.AppName) $($ErrorMessage.NormalizedError)"
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
                    # Block deleting a client whose role outranks the caller (tamper/DoS).
                    $ExistingClientForAuth = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($ClientId)'"
                    if ($ExistingClientForAuth) {
                        $RoleGrant = Test-CippApiClientRoleGrant -Request $Request -Role ([string]$ExistingClientForAuth.Role)
                        if (-not $RoleGrant.Allowed) {
                            Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Blocked API client deletion for $($ClientId): $($RoleGrant.Message)" -Sev 'Warning'
                            $Body = @{ Results = $RoleGrant.Message }
                            break
                        }
                    }
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
                Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Failed to remove app registration for $ClientId" -sev 'Warning'
            }
        }
        default {
            $Body = @{Results = 'Invalid action' }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}

