function Invoke-CIPPNhiContainment {
    <#
    .SYNOPSIS
        Runs a selectable set of containment actions on the app of a non-human identity (NHI) case.
    .DESCRIPTION
        Actions come from Get-CIPPNhiContainmentActions; with no selection the default set runs. They run in
        catalog order, each in its own try/catch so one failure never stops the rest, and return result rows
        ({ Action, Target, state, resultText }). Targets come from Parameters (ids the operator picked), else from
        what the case flagged: never every credential, owner or permission the app has, because the app may
        depend on them. Critical actions refuse to run without -Confirmed. The rows are appended to the case's
        containment history.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER CaseId
        The completed NHI case the containment belongs to; the app and the default targets come from it.
    .PARAMETER Actions
        Action ids to run. Empty = the default set.
    .PARAMETER Parameters
        Explicit targets (hashtable or object): CredentialKeyIds, FederatedCredentialIds, OwnerIds,
        AppRoleAssignmentIds, GrantIds, RoleAssignmentIds, PersistenceServicePrincipalIds, ElevationIds.
    .PARAMETER Confirmed
        The operator confirmed the Critical actions.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [string[]]$Actions = @(),
        $Parameters,
        [switch]$Confirmed,
        $Headers,
        [string]$APIName = 'NHIContainment'
    )

    $Run = Get-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults
    if (-not $Run) { throw [System.Management.Automation.ItemNotFoundException]::new("NHI case $CaseId was not found for $TenantFilter") }
    if ($Run.Status -ne 'Completed') { throw [System.ArgumentException]::new("NHI case $CaseId has not completed: contain the app from a finished investigation") }
    $Results = $Run.Results
    $SpId = [string]$Results.ServicePrincipalId
    $Subject = $Results.Subject
    $Name = [string]$Results.DisplayName
    $AppRegId = [string]$Subject.AppRegistrationId

    $Catalog = Get-CIPPNhiContainmentActions
    $Selected = if (@($Actions | Where-Object { $_ }).Count -eq 0) {
        @($Catalog | Where-Object { $_.DefaultSelected })
    } else {
        @(foreach ($Id in ($Actions | Where-Object { $_ } | Select-Object -Unique)) {
                $Match = $Catalog | Where-Object { $_.Id -ieq [string]$Id } | Select-Object -First 1
                if (-not $Match) { throw [System.ArgumentException]::new("Unknown containment action '$Id'") }
                $Match
            })
    }
    $Selected = @($Selected | Sort-Object -Property Order)
    $CriticalSelected = @($Selected | Where-Object { $_.Impact -eq 'Critical' })
    if ($CriticalSelected.Count -gt 0 -and -not $Confirmed) {
        throw [System.ArgumentException]::new("Confirmation is required: the selected actions include Critical changes ($($CriticalSelected.Id -join ', '))")
    }

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Add = { param($Action, $Target, $State, $Text) $Rows.Add([pscustomobject]@{ Action = $Action; Target = [string]$Target; state = $State; resultText = $Text }) }
    # The operator's selection, even an empty one, else the case's defaults; parameters may be a hashtable or a deserialised object.
    $Targets = {
        param($ParameterName, $Defaults)
        $Sent = if ($Parameters -is [System.Collections.IDictionary]) { $Parameters.Contains($ParameterName) } else { $null -ne $Parameters -and $null -ne $Parameters.PSObject.Properties[$ParameterName] }
        if ($Sent) {
            @($Parameters.$ParameterName | Where-Object { $null -ne $_ -and "$_" -ne '' } | ForEach-Object { [string]($_.value ?? $_) })
        } else {
            @($Defaults | Where-Object { $_ } | ForEach-Object { [string]$_ })
        }
    }
    $Graph = 'https://graph.microsoft.com/v1.0'
    $Credentials = @($Results.Exposure.CredentialDetails | Where-Object { $_ })

    Set-CippBecCaseContext -CaseId $CaseId
    try {
        foreach ($Action in $Selected) {
            $Id = $Action.Id
            if (-not $PSCmdlet.ShouldProcess($Name, $Action.Label)) { continue }
            try {
                switch ($Id) {
                    'DisableServicePrincipal' {
                        if ($Subject.IsManagedIdentity) {
                            & $Add $Id $SpId 'warning' "A managed identity is disabled in Azure, not Entra: remove the identity from $(if ($Subject.AzureResourceId) { $Subject.AzureResourceId } else { 'its Azure resource' }), or stop that resource."
                            break
                        }
                        $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$SpId" -tenantid $TenantFilter -type PATCH -body '{"accountEnabled":false}' -AsApp $true
                        & $Add $Id $SpId 'success' "Disabled $Name in this tenant: it gets no new tokens. Tokens it already holds stay valid until they expire (about an hour)."
                    }
                    'RemoveCredentials' {
                        $Federated = @($Credentials | Where-Object Type -EQ 'Federated' | ForEach-Object { [string]$_.KeyId })
                        $KeyIds = @(& $Targets 'CredentialKeyIds' @($Results.FlaggedKeyIds | Where-Object { $_ -notin $Federated }))
                        if ($KeyIds.Count -eq 0) { & $Add $Id $Name 'info' 'No credential was selected or flagged: nothing removed.'; break }
                        foreach ($Location in 'Enterprise app', 'App registration') {
                            $ObjectPath = if ($Location -eq 'Enterprise app') { "servicePrincipals/$SpId" } elseif ($AppRegId) { "applications/$AppRegId" } else { $null }
                            $Here = @($Credentials | Where-Object { $_.Location -eq $Location -and [string]$_.KeyId -in $KeyIds })
                            if (-not $ObjectPath -or $Here.Count -eq 0) { continue }
                            foreach ($Secret in @($Here | Where-Object Type -EQ 'Secret')) {
                                try {
                                    $null = New-GraphPOSTRequest -uri "$Graph/$ObjectPath/removePassword" -tenantid $TenantFilter -type POST -body (ConvertTo-Json -InputObject @{ keyId = [string]$Secret.KeyId } -Compress) -AsApp $true
                                    & $Add $Id $Secret.KeyId 'success' "Removed secret $($Secret.DisplayName) ($($Secret.KeyId)) from the $($Location.ToLowerInvariant())"
                                } catch { & $Add $Id $Secret.KeyId 'error' "Could not remove secret $($Secret.KeyId): $((Get-CippException -Exception $_).NormalizedError)" }
                            }
                            $CertificateIds = @($Here | Where-Object Type -EQ 'Certificate' | ForEach-Object { [string]$_.KeyId })
                            if ($CertificateIds.Count -gt 0) {
                                try {
                                    # keyCredentials are replaced as a whole: keep every certificate not being removed
                                    $Current = New-GraphGetRequest -uri "$Graph/$($ObjectPath)?`$select=keyCredentials" -tenantid $TenantFilter -AsApp $true
                                    $Keep = @($Current.keyCredentials | Where-Object { [string]$_.keyId -notin $CertificateIds })
                                    $null = New-GraphPOSTRequest -uri "$Graph/$ObjectPath" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject @{ keyCredentials = $Keep } -Depth 5 -Compress) -AsApp $true
                                    foreach ($KeyId in $CertificateIds) { & $Add $Id $KeyId 'success' "Removed certificate $KeyId from the $($Location.ToLowerInvariant())" }
                                } catch {
                                    $Message = (Get-CippException -Exception $_).NormalizedError
                                    foreach ($KeyId in $CertificateIds) { & $Add $Id $KeyId 'error' "Could not remove certificate $KeyId`: $Message" }
                                }
                            }
                        }
                        foreach ($KeyId in @($KeyIds | Where-Object { $_ -notin $Credentials.KeyId })) { & $Add $Id $KeyId 'warning' "Credential $KeyId was not on the app when the case ran: nothing removed" }
                    }
                    'RemoveFederatedCredentials' {
                        $Ids = @(& $Targets 'FederatedCredentialIds' @($Credentials | Where-Object { $_.Type -eq 'Federated' -and $_.Flags -contains 'UntrustedIssuer' } | ForEach-Object { $_.KeyId }))
                        if ($Ids.Count -eq 0) { & $Add $Id $Name 'info' 'No federated credential was selected or flagged: nothing removed.'; break }
                        if (-not $AppRegId) { & $Add $Id $Name 'warning' 'Federated credentials live on an app registration in this tenant, and this app has none here.'; break }
                        foreach ($CredentialId in $Ids) {
                            if ($CredentialId -notin @($Credentials | Where-Object Type -EQ 'Federated' | ForEach-Object { [string]$_.KeyId })) { & $Add $Id $CredentialId 'warning' "Federated credential $CredentialId was not on the app when the case ran: nothing removed"; continue }
                            try {
                                $null = New-GraphPOSTRequest -uri "$Graph/applications/$AppRegId/federatedIdentityCredentials/$CredentialId" -tenantid $TenantFilter -type DELETE -AsApp $true
                                & $Add $Id $CredentialId 'success' "Removed federated credential $(($Credentials | Where-Object KeyId -EQ $CredentialId | Select-Object -First 1).DisplayName) ($CredentialId)"
                            } catch { & $Add $Id $CredentialId 'error' "Could not remove federated credential $CredentialId`: $((Get-CippException -Exception $_).NormalizedError)" }
                        }
                    }
                    'RemoveOwners' {
                        $Ids = @(& $Targets 'OwnerIds' @())
                        if ($Ids.Count -eq 0) { & $Add $Id $Name 'info' 'No owner was selected: nothing removed.'; break }
                        foreach ($OwnerId in @($Ids | Where-Object { $_ -notin @($Results.Owners.Id) })) { & $Add $Id $OwnerId 'warning' "$OwnerId was not an owner of the app when the case ran: nothing removed" }
                        foreach ($Owner in @($Results.Owners | Where-Object { [string]$_.Id -in $Ids })) {
                            $ObjectPath = if ($Owner.OwnerOf -eq 'Enterprise app') { "servicePrincipals/$SpId" } else { "applications/$AppRegId" }
                            $Label = if ($Owner.UserPrincipalName) { $Owner.UserPrincipalName } else { $Owner.DisplayName }
                            try {
                                $null = New-GraphPOSTRequest -uri "$Graph/$ObjectPath/owners/$($Owner.Id)/`$ref" -tenantid $TenantFilter -type DELETE -AsApp $true
                                & $Add $Id $Owner.Id 'success' "Removed $Label as owner of the $($Owner.OwnerOf.ToLowerInvariant())"
                            } catch { & $Add $Id $Owner.Id 'error' "Could not remove $Label as owner: $((Get-CippException -Exception $_).NormalizedError)" }
                        }
                    }
                    { $_ -in 'RevokeAppRoleAssignments', 'RevokeDelegatedGrants', 'RemoveDirectoryRoles' } {
                        $Spec = switch ($Id) {
                            'RevokeAppRoleAssignments' { @{ Parameter = 'AppRoleAssignmentIds'; Defaults = @($Results.AppRoleAssignments | Where-Object InWindow | ForEach-Object { $_.Id }); Rows = $Results.AppRoleAssignments; Path = "servicePrincipals/$SpId/appRoleAssignments/{0}"; Label = { "$($_.ResourceDisplayName) $($_.Permission)" } } }
                            'RevokeDelegatedGrants' { @{ Parameter = 'GrantIds'; Defaults = @(); Rows = $Results.DelegatedGrants; Path = 'oauth2PermissionGrants/{0}'; Label = { "$($_.ConsentType) consent for $($_.Scope)" } } }
                            'RemoveDirectoryRoles' { @{ Parameter = 'RoleAssignmentIds'; Defaults = @(); Rows = $Results.DirectoryRoles; Path = 'roleManagement/directory/roleAssignments/{0}'; Label = { "directory role $($_.RoleName)" } } }
                        }
                        $Ids = @(& $Targets $Spec.Parameter $Spec.Defaults)
                        if ($Ids.Count -eq 0) { & $Add $Id $Name 'info' "Nothing was selected$(if ($Id -eq 'RevokeAppRoleAssignments') { ' or granted in the window' }): nothing removed."; break }
                        foreach ($TargetId in $Ids) {
                            # only what the case found on this app, never an id from elsewhere
                            $Row = @($Spec.Rows | Where-Object { $_ -and [string]$_.Id -eq $TargetId }) | Select-Object -First 1
                            if (-not $Row) { & $Add $Id $TargetId 'warning' "$TargetId was not on the app when the case ran: nothing removed"; continue }
                            $Label = @($Row | ForEach-Object $Spec.Label)[0]
                            try {
                                $null = New-GraphPOSTRequest -uri "$Graph/$($Spec.Path -f $TargetId)" -tenantid $TenantFilter -type DELETE -AsApp $true
                                & $Add $Id $TargetId 'success' "Removed $Label"
                            } catch { & $Add $Id $TargetId 'error' "Could not remove $Label`: $((Get-CippException -Exception $_).NormalizedError)" }
                        }
                    }
                    'DisablePersistenceApps' {
                        # only apps the case found this app creating or taking over, never an id from elsewhere
                        $Found = @($Results.DirectoryActions | Where-Object { $_.Kind -eq 'AppPersistence' -and $_.TargetServicePrincipalId -and $_.TargetServicePrincipalId -ne $SpId })
                        $Ids = @(@(& $Targets 'PersistenceServicePrincipalIds' @($Found | Where-Object { $_.InWindow -and -not $_.TargetProtected } | ForEach-Object { $_.TargetServicePrincipalId })) | Select-Object -Unique)
                        if ($Ids.Count -eq 0) { & $Add $Id $Name 'info' 'No app this app created or put credentials on was selected or found in the window: nothing disabled.'; break }
                        foreach ($TargetId in $Ids) {
                            $Row = $Found | Where-Object TargetServicePrincipalId -EQ $TargetId | Select-Object -First 1
                            if (-not $Row) { & $Add $Id $TargetId 'warning' "$TargetId is not an app this case found the app creating or taking over: not disabled"; continue }
                            if ($Row.TargetProtected) { & $Add $Id $TargetId 'warning' "$($Row.TargetDisplayName) is Microsoft's or CIPP's own app: not disabled. Remove the credential or owner it was given instead."; continue }
                            try {
                                $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$TargetId" -tenantid $TenantFilter -type PATCH -body '{"accountEnabled":false}' -AsApp $true
                                & $Add $Id $TargetId 'success' "Disabled $($Row.TargetDisplayName), which $Name $(if ($Row.CreatedApp) { 'created' } else { 'put a credential or owner on' })"
                            } catch { & $Add $Id $TargetId 'error' "Could not disable $($Row.TargetDisplayName): $((Get-CippException -Exception $_).NormalizedError)" }
                        }
                    }
                    'RevokeElevation' {
                        # only grants the case recorded this app making
                        $Found = @($Results.DirectoryActions | Where-Object { $_.Kind -eq 'Elevation' -and $_.ElevationId -and $_.RecipientId })
                        $Ids = @(@(& $Targets 'ElevationIds' @($Found | Where-Object { $_.InWindow -and $_.Impact -in 'High', 'Critical' } | ForEach-Object { $_.ElevationId })) | Select-Object -Unique)
                        if ($Ids.Count -eq 0) { & $Add $Id $Name 'info' 'No access this app granted was selected or found in the window: nothing revoked.'; break }
                        foreach ($ElevationId in $Ids) {
                            $Row = $Found | Where-Object ElevationId -EQ $ElevationId | Select-Object -First 1
                            if (-not $Row) { & $Add $Id $ElevationId 'warning' 'Not a grant this case found the app making: nothing revoked'; continue }
                            $Label = "$($Row.Permission) for $(if ($Row.RecipientName) { $Row.RecipientName } else { $Row.RecipientId })"
                            try {
                                $Removed = switch ($Row.ElevationType) {
                                    'Application permission' {
                                        @(New-GraphGetRequest -uri "$Graph/servicePrincipals/$($Row.RecipientId)/appRoleAssignments" -tenantid $TenantFilter -AsApp $true | Where-Object { $_.appRoleId -eq $Row.ElevationRoleId -and (-not $Row.ResourceId -or $_.resourceId -eq $Row.ResourceId) } | ForEach-Object {
                                                $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$($Row.RecipientId)/appRoleAssignments/$($_.id)" -tenantid $TenantFilter -type DELETE -AsApp $true
                                                $_.id
                                            })
                                    }
                                    'Directory role' {
                                        @(New-GraphGetRequest -uri "$Graph/roleManagement/directory/roleAssignments?`$filter=principalId eq '$($Row.RecipientId)' and roleDefinitionId eq '$($Row.ElevationRoleId)'" -tenantid $TenantFilter -AsApp $true | ForEach-Object {
                                                $null = New-GraphPOSTRequest -uri "$Graph/roleManagement/directory/roleAssignments/$($_.id)" -tenantid $TenantFilter -type DELETE -AsApp $true
                                                $_.id
                                            })
                                    }
                                    'Eligible directory role' {
                                        @(New-GraphGetRequest -uri "$Graph/roleManagement/directory/roleEligibilitySchedules?`$filter=principalId eq '$($Row.RecipientId)' and roleDefinitionId eq '$($Row.ElevationRoleId)'" -tenantid $TenantFilter -AsApp $true | ForEach-Object {
                                                $Req = New-CIPPPIMScheduleRequest -Kind Eligibility -Action adminRemove -PrincipalId $Row.RecipientId -RoleDefinitionId $Row.ElevationRoleId -DirectoryScopeId ([string]$_.directoryScopeId) -Justification "NHI containment [case $CaseId]"
                                                $null = New-GraphPOSTRequest -uri $Req.Uri -tenantid $TenantFilter -type POST -body (ConvertTo-Json -InputObject $Req.Body -Compress) -AsApp $true
                                                $_.id
                                            })
                                    }
                                    'Delegated permission' {
                                        # only the scopes this app added: what others consented to on the same grant stays
                                        $Added = @(([string]$Row.Scopes).Split([char[]]' ', [System.StringSplitOptions]::RemoveEmptyEntries))
                                        @(New-GraphGetRequest -uri "$Graph/oauth2PermissionGrants?`$filter=clientId eq '$($Row.RecipientId)' and resourceId eq '$($Row.ResourceId)'" -tenantid $TenantFilter -AsApp $true | Where-Object { -not $Row.ConsentType -or $_.consentType -eq $Row.ConsentType } | ForEach-Object {
                                                $Remaining = @(([string]$_.scope).Split([char[]]' ', [System.StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_ -notin $Added })
                                                if ($Remaining.Count -eq 0) {
                                                    $null = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants/$($_.id)" -tenantid $TenantFilter -type DELETE -AsApp $true
                                                } else {
                                                    $null = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants/$($_.id)" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject @{ scope = $Remaining -join ' ' } -Compress) -AsApp $true
                                                }
                                                $_.id
                                            })
                                    }
                                    default { $null }
                                }
                                if (@($Removed).Count -gt 0) { & $Add $Id $ElevationId 'success' "Revoked $Label" } else { & $Add $Id $ElevationId 'info' "$Label is no longer in place: nothing revoked" }
                            } catch { & $Add $Id $ElevationId 'error' "Could not revoke $Label`: $((Get-CippException -Exception $_).NormalizedError)" }
                        }
                    }
                    'ConfirmCompromised' {
                        $null = New-GraphPOSTRequest -uri "$Graph/identityProtection/riskyServicePrincipals/confirmCompromised" -tenantid $TenantFilter -type POST -body (ConvertTo-Json -InputObject @{ servicePrincipalIds = @($SpId) } -Compress)
                        & $Add $Id $SpId 'success' "Confirmed $Name compromised in Identity Protection"
                    }
                    'LockAppInstanceProperties' {
                        if (-not $AppRegId) { & $Add $Id $Name 'info' 'The app is not registered in this tenant: its owner sets the lock.'; break }
                        $null = New-GraphPOSTRequest -uri "$Graph/applications/$AppRegId" -tenantid $TenantFilter -type PATCH -body '{"servicePrincipalLockConfiguration":{"isEnabled":true,"allProperties":true}}' -AsApp $true
                        & $Add $Id $AppRegId 'success' "Locked the app instance properties of $Name"
                    }
                    default { & $Add $Id $Name 'error' "Action '$Id' has no implementation" }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                & $Add $Id $Name 'error' "$($Action.Label) failed: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "NHI containment action $Id failed for $Name`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Executed NHI containment for $Name ($($Selected.Id -join ', ')) [case $CaseId]" -Sev 'Info' -LogData @($Rows)
        try {
            $By = if ($Headers -and $Headers.'x-ms-client-principal') { try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' } } else { 'CIPP' }
            $History = [System.Collections.Generic.List[object]]::new()
            foreach ($Entry in @($Run.Containment | Where-Object { $_ })) { $History.Add($Entry) }
            $History.Add([pscustomobject]@{ At = (Get-Date).ToUniversalTime().ToString('o'); By = [string]$By; Kind = 'Containment'; Actions = @($Selected.Id); Results = $Rows.ToArray() })
            $null = Set-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -Properties @{ Containment = @($History); LastContainmentAt = (Get-Date).ToUniversalTime().ToString('o') }
        } catch {
            Write-Information "NHI containment: could not append the result to case $CaseId`: $($_.Exception.Message)"
        }
    } finally {
        Set-CippBecCaseContext -CaseId $null
    }
    return $Rows.ToArray()
}
