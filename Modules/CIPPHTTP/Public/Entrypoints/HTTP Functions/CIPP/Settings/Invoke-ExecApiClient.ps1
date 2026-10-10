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

                # When this client is MCP-enabled it becomes one of the OAuth client apps that AI
                # connectors sign in as. Several MCPAllowed clients may coexist (each with its own
                # role/IP/redirects/CA); the dedicated CIPP-MCP app is the shared protected resource.
                # Configure this client (callbacks, public client flows, resource permissions +
                # consent) and ensure the resource app exists (Set-CIPPMCPClientApp ->
                # New-CIPPMcpResourceApp).
                if ([bool]($Request.Body.MCPAllowed ?? $false)) {
                    try {
                        $McpResult = Set-CIPPMCPClientApp -AppId $ClientId -Headers $Request.Headers
                        $Results.Add("Configured '$($Client.AppName)' as an MCP OAuth client (callbacks for Claude, ChatGPT, VS Code and Copilot Studio) against the CIPP-MCP resource app. Run Save to Azure to apply the changes.")
                        if (-not $McpResult.ResourceAppId) {
                            $Results.Add(@{
                                    resultText = 'The CIPP-MCP resource app could not be created or resolved. MCP connectors will not be able to sign in until this succeeds - re-run Save, or check the app registration permissions.'
                                    state      = 'warning'
                                })
                        } else {
                            $Results.Add('For Copilot Studio, use this client''s Application (Client) ID and its secret (reset it with Actions > Reset Application Secret if you did not save it).')
                        }
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
            $FunctionAppName = $env:WEBSITE_SITE_NAME
            try {
                $RGName = Get-CIPPFunctionAppResourceGroup -SiteName $FunctionAppName
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
            $FunctionAppName = $env:WEBSITE_SITE_NAME
            $AllClients = Get-CIPPAzDataTableEntity @Table -Filter 'Enabled eq true' | Where-Object { ![string]::IsNullOrEmpty($_.RowKey) }
            $ClientIds = $AllClients.RowKey
            # MCPAllowed can round-trip from table storage as a bool or a string; compare on string form.
            $McpClientIds = @($AllClients | Where-Object { "$($_.MCPAllowed)" -eq 'True' } | ForEach-Object { $_.RowKey })
            Write-Information "[ExecApiClient] MCP clients resolved for audiences/scope: $($McpClientIds -join ', ')"
            try {
                $RGName = Get-CIPPFunctionAppResourceGroup -SiteName $FunctionAppName

                # Ensure the dedicated CIPP-MCP resource app exists and every MCP client app is wired
                # up (callbacks, resource permission, admin consent) BEFORE writing EasyAuth:
                # Set-CippApiAuth reads the resource app id for allowedAudiences, so the resource must
                # exist first. This makes Save to Azure a full deploy for both new and existing setups
                # (an instance upgraded from the single-app model gets its resource app created and its
                # client rewired here). Best-effort per client.
                foreach ($McpId in $McpClientIds) {
                    if ([string]::IsNullOrEmpty($McpId)) { continue }
                    try {
                        $null = Set-CIPPMCPClientApp -AppId $McpId -Headers $Request.Headers
                    } catch {
                        Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "MCP client $McpId could not be configured during Save to Azure: $($_.Exception.Message)" -Sev 'Warning'
                    }
                }

                Set-CippApiAuth -RGName $RGName -FunctionAppName $FunctionAppName -TenantId $TenantId -ClientIds $ClientIds -McpClientIds $McpClientIds

                if ($McpClientIds.Count -gt 0 -and $env:WEBSITE_HOSTNAME) {
                    # Advertise the OIDC + offline_access scopes alongside the resource scope so
                    # discovery-based MCP clients (ChatGPT, VS Code, Copilot CLI) request a refresh
                    # token. offline_access is what makes Entra issue one; without it the client
                    # re-consents every ~hour. Claude appends offline_access itself, but stricter
                    # clients only request what the metadata advertises, so it has to be in the
                    # challenge header and the discovery docs, not just one of them. The values come
                    # from Get-CippMcpScopeAppSettings so the Initialize-CIPPAuth warmup reconcile
                    # writes byte-identical settings and the two paths never fight each other.
                    # NOTE: Copilot Studio does NOT read any of this. Entra has no RFC 7591 DCR, so
                    # Copilot Studio uses Manual OAuth with a maker-typed scope; its refresh token
                    # depends on offline_access being consented on the MCP client app registration
                    # (Set-CIPPMCPClientApp / Grant-CippAppGraphConsent), not on these documents.
                    $McpAppSettings = Get-CippMcpScopeAppSettings -Hostname $env:WEBSITE_HOSTNAME -TenantId $env:TenantID -IsCippNg:([bool]$env:CIPPNG)
                    $null = Update-CIPPAzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $RGName -AppSetting $McpAppSettings
                } else {
                    $null = Update-CIPPAzFunctionAppSetting -Name $FunctionAppName -ResourceGroupName $RGName -AppSetting @{} -RemoveKeys @('WEBSITE_AUTH_PRM_DEFAULT_WITH_SCOPES', 'CRAFT_PRM', 'CRAFT_PRM_AS')
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
                    Remove-CIPPAzDataTableEntity @Table -Entity $Client -Force
                    Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Deleted API client $ClientId" -Sev 'Info'
                    $Body = @{ Results = "API client $ClientId deleted" }
                } else {
                    $Body = @{ Results = "API client $ClientId not found or not a valid CIPP-API application" }
                }
            } catch {
                Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Failed to remove app registration for $ClientId" -sev 'Warning'
            }
        }
        'GetMcpAuth' {
            # MCP status for the client-management UI: whether the dedicated CIPP-MCP resource app is
            # provisioned, plus each MCPAllowed client app and its custom (non-default) redirect URIs.
            $KnownClients = Get-CippMcpKnownClients
            $McpResTable = Get-CippTable -tablename 'CippMcpResource'
            $McpResRow = Get-CIPPAzDataTableEntity @McpResTable -Filter "PartitionKey eq 'McpResource' and RowKey eq 'McpResource'"
            $ResourceConfigured = $false
            $ResourceAppId = ''
            $ResourceObjectId = ''
            $ResourceDisplayName = ''
            $ResourceIdentifierUris = @()
            $PreAuthorizedClientIds = @()
            if (-not [string]::IsNullOrWhiteSpace($McpResRow.AppId)) {
                try {
                    $ResApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($McpResRow.AppId)')?`$select=id,appId,displayName,identifierUris,api" -NoAuthCheck $true -asapp $true
                    $ResourceConfigured = [bool]$ResApp.appId
                    $ResourceAppId = "$($ResApp.appId)"
                    $ResourceObjectId = "$($ResApp.id)"
                    $ResourceDisplayName = "$($ResApp.displayName)"
                    $ResourceIdentifierUris = @($ResApp.identifierUris)
                    $PreAuthorizedClientIds = @(@($ResApp.api.preAuthorizedApplications) | ForEach-Object { $_.appId })
                } catch {
                    $ResourceConfigured = $false
                }
            }
            # If the resource app isn't set up, check whether the MCP resource URL is being held by a
            # DIFFERENT app (e.g. a client left over from the old single-app setup) - that blocks
            # creation and the admin must delete it manually. Surface it so the page can warn.
            $ResourceConflict = $null
            if (-not $ResourceConfigured -and $env:WEBSITE_HOSTNAME) {
                try {
                    $HostUri = "https://$($env:WEBSITE_HOSTNAME)/api/ExecMcp"
                    $Holders = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications?`$filter=identifierUris/any(u:u eq '$HostUri')&`$count=true&`$select=appId,displayName" -NoAuthCheck $true -asapp $true -ComplexFilter)
                    $Conflict = $Holders | Where-Object { $_.appId -and $_.displayName -ne 'CIPP-MCP' } | Select-Object -First 1
                    if ($Conflict) { $ResourceConflict = @{ AppId = "$($Conflict.appId)"; AppName = "$($Conflict.displayName)" } }
                } catch {
                    Write-Information "[ExecApiClient] Could not check for MCP resource URI conflict: $($_.Exception.Message)"
                }
                # Fall back to (or enrich with) the conflict error persisted by New-CIPPMcpResourceApp.
                try {
                    $ErrRow = Get-CIPPAzDataTableEntity @McpResTable -Filter "PartitionKey eq 'McpResource' and RowKey eq 'Error'"
                    if ($ErrRow.RowKey) {
                        if (-not $ResourceConflict) { $ResourceConflict = @{ AppId = "$($ErrRow.ConflictAppId)"; AppName = "$($ErrRow.ConflictAppName)" } }
                        $ResourceConflict.Message = "$($ErrRow.Message)"
                    }
                } catch {
                    Write-Information "[ExecApiClient] Could not read stored MCP conflict error: $($_.Exception.Message)"
                }
            }
            $McpClients = @(Get-CIPPAzDataTableEntity @Table | Where-Object { ![string]::IsNullOrEmpty($_.RowKey) -and "$($_.MCPAllowed)" -eq 'True' })
            $ClientInfo = [System.Collections.Generic.List[object]]::new()
            foreach ($C in $McpClients) {
                # Custom redirect URIs are surfaced per platform: 'public' (mobile & desktop, PKCE -
                # Claude/ChatGPT/CLI) and 'web' (confidential, secret - Copilot Studio). Which bucket a
                # URI is in decides whether the token exchange succeeds, so the UI edits them separately.
                $CustomPublic = @()
                $CustomWeb = @()
                try {
                    $CApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$($C.RowKey)')?`$select=publicClient,web" -NoAuthCheck $true -asapp $true
                    $CustomPublic = @(@($CApp.publicClient.redirectUris) | Where-Object { $_ -notin $KnownClients.PublicClientRedirectUris })
                    $CustomWeb = @(@($CApp.web.redirectUris) | Where-Object { $_ -notin $KnownClients.ConfidentialRedirectUris -and $_ -notlike "*/.auth/login/aad/callback" })
                } catch {
                    $CustomPublic = @()
                    $CustomWeb = @()
                }
                $ClientInfo.Add(@{
                        AppId                          = "$($C.RowKey)"
                        AppName                        = "$($C.AppName)"
                        PublicRedirectUris             = @($CustomPublic)
                        WebRedirectUris                = @($CustomWeb)
                        UserImpersonationPreAuthorized = ($PreAuthorizedClientIds -contains "$($C.RowKey)")
                    })
            }
            $Body = @{ Results = @{
                    ResourceConfigured     = $ResourceConfigured
                    ResourceAppId          = $ResourceAppId
                    ResourceObjectId       = $ResourceObjectId
                    ResourceDisplayName    = $ResourceDisplayName
                    ResourceIdentifierUris = @($ResourceIdentifierUris)
                    ResourceConflict       = $ResourceConflict
                    DefaultRedirectUris    = @($KnownClients.PublicClientRedirectUris)
                    DefaultWebRedirectUris = @($KnownClients.ConfidentialRedirectUris)
                    Clients                = @($ClientInfo)
                } }
        }
        'SetMcpRedirectUris' {
            # Replace the CUSTOM redirect URIs on a specific MCP client app, per platform. The built-in
            # provider callbacks are always kept. Body.ClientId picks the client; Body.PublicRedirectUris
            # go under 'publicClient' (mobile & desktop / PKCE - Claude, ChatGPT, CLI) and
            # Body.WebRedirectUris under 'web' (confidential / secret - Copilot Studio). A URI under the
            # wrong platform fails at the token exchange, which is why they are edited separately.
            # Back-compat: a lone Body.RedirectUris is treated as the public list.
            $KnownClients = Get-CippMcpKnownClients
            $TargetClientId = $Request.Body.ClientId.value ?? $Request.Body.ClientId
            if ([string]::IsNullOrWhiteSpace($TargetClientId)) {
                $Body = @{ Results = @{ resultText = 'No ClientId provided.'; state = 'error' } }
                break
            }
            # Only ever patch an app registration that is a CIPP-managed, MCP-enabled API client -
            # never an arbitrary appId, which would let a caller rewrite the redirect URIs of any app
            # in the tenant via CIPP's app-only Graph rights.
            $ManagedClient = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$TargetClientId'"
            if (-not $ManagedClient.RowKey -or "$($ManagedClient.MCPAllowed)" -ne 'True') {
                Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Blocked MCP redirect URI update for $TargetClientId : not an MCP-enabled CIPP API client." -Sev 'Warning'
                $Body = @{ Results = @{ resultText = 'That app is not an MCP-enabled CIPP API client.'; state = 'error' } }
                break
            }
            $Invalid = [System.Collections.Generic.List[string]]::new()
            $ParseUris = {
                param($Raw)
                $Out = [System.Collections.Generic.List[string]]::new()
                foreach ($Uri in @($Raw)) {
                    $U = "$Uri".Trim()
                    if ([string]::IsNullOrWhiteSpace($U)) { continue }
                    $Parsed = $null
                    if ([System.Uri]::TryCreate($U, [System.UriKind]::Absolute, [ref]$Parsed)) {
                        if ($Out -notcontains $U) { $Out.Add($U) }
                    } else {
                        $Invalid.Add($U)
                    }
                }
                $Out
            }
            $CustomPublic = & $ParseUris ($Request.Body.PublicRedirectUris ?? $Request.Body.RedirectUris)
            $CustomWeb = & $ParseUris $Request.Body.WebRedirectUris
            if ($Invalid.Count -gt 0) {
                $Body = @{ Results = @{ resultText = "These are not valid absolute URIs: $($Invalid -join ', ')"; state = 'error' } }
                break
            }
            try {
                $CApp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/applications(appId='$TargetClientId')?`$select=id,web" -NoAuthCheck $true -asapp $true
                # Preserve the EasyAuth login callback if this app carries one; it is not ours to drop.
                $KeepWeb = @(@($CApp.web.redirectUris) | Where-Object { $_ -like "*/.auth/login/aad/callback" })
                $DesiredPublic = @(@($KnownClients.PublicClientRedirectUris) + @($CustomPublic) | Where-Object { $_ } | Select-Object -Unique)
                $DesiredWeb = @(@($KnownClients.ConfidentialRedirectUris) + @($KeepWeb) + @($CustomWeb) | Where-Object { $_ } | Select-Object -Unique)
                $PatchBody = @{ publicClient = @{ redirectUris = @($DesiredPublic) }; web = @{ redirectUris = @($DesiredWeb) } } | ConvertTo-Json -Depth 6 -Compress
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/applications/$($CApp.id)" -type PATCH -body $PatchBody -NoAuthCheck $true -asapp $true
                Write-LogMessage -headers $Request.Headers -API 'ExecApiClient' -message "Updated MCP client $TargetClientId redirect URIs ($($CustomPublic.Count) public, $($CustomWeb.Count) web)." -Sev 'Info'
                $Body = @{ Results = @{ resultText = 'MCP connector redirect URIs updated.'; state = 'success' } }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Body = @{ Results = @{ resultText = "Failed to update redirect URIs: $($ErrorMessage.NormalizedError)"; state = 'error' } }
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

