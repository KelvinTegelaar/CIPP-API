function Invoke-ExecEnterpriseAppPermission {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .DESCRIPTION
        Adds or removes API permissions on an enterprise application (service principal). Application permissions are
        app role assignments. Delegated permissions are added to the tenant-wide (AllPrincipals) consent grant; removing
        a delegated scope strips it from every grant the app holds for that API, per-user grants included, and deletes
        grants left without scopes.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $ServicePrincipalId = "$($Request.Body.ServicePrincipalId)"
    $Action = "$($Request.Body.Action)"
    $Type = "$($Request.Body.Type)"
    $ResourceId = "$($Request.Body.ResourceId.value ?? $Request.Body.ResourceId)"
    $Mode = "$Type$Action"
    $Guid = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'

    if (-not $TenantFilter -or $ServicePrincipalId -notmatch $Guid) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter and a valid ServicePrincipalId are required' }
            })
    }
    if ($Mode -notin @('ApplicationAdd', 'ApplicationRemove', 'DelegatedAdd', 'DelegatedRemove')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Action must be Add or Remove and Type must be Application or Delegated' }
            })
    }
    if ($Mode -ne 'ApplicationRemove' -and $ResourceId -notmatch $Guid) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'A valid ResourceId (the object id of the resource API service principal) is required' }
            })
    }

    $ItemField, $ItemPattern = switch ($Mode) {
        'ApplicationAdd' { 'AppRoleIds', $Guid }
        'ApplicationRemove' { 'AppRoleAssignmentIds', '^[A-Za-z0-9_-]+$' }
        default { 'Scopes', '^\S+$' }
    }
    # Autocomplete fields post { label, value } objects.
    $Items = @(foreach ($Item in @($Request.Body.$ItemField)) { if ($Item) { "$($Item.value ?? $Item)".Trim() } })
    if ($Items.Count -eq 0 -or $Items.Where({ $_ -notmatch $ItemPattern }).Count -gt 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "$ItemField must hold at least one valid value" }
            })
    }

    $SpUri = "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId"
    $Results = [System.Collections.Generic.List[object]]::new()
    $Total = 0
    $Failed = 0
    try {
        if ($Action -eq 'Add') {
            $Resource = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ResourceId`?`$select=displayName,appRoles,oauth2PermissionScopes" -tenantid $TenantFilter
            # Keyed case-insensitively, so delegated scopes resolve to the casing the API publishes.
            $Known = @{}
            if ($Type -eq 'Application') {
                foreach ($Role in @($Resource.appRoles)) { if ($Role.allowedMemberTypes -contains 'Application') { $Known[$Role.id] = $Role.value } }
            } else {
                foreach ($Scope in @($Resource.oauth2PermissionScopes)) { if ($Scope.value) { $Known[$Scope.value] = $Scope.value } }
            }
            $Unknown = $Items.Where({ -not $Known.ContainsKey($_) })
            if ($Unknown.Count -gt 0) {
                throw [System.ArgumentException]::new("$($Resource.displayName) does not publish the $($Type.ToLower()) permission(s): $($Unknown -join ', ')")
            }
        }

        if ($Mode -eq 'ApplicationAdd') {
            $Assigned = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Assignment in @(New-GraphGetRequest -uri "$SpUri/appRoleAssignments" -tenantid $TenantFilter)) {
                if ($Assignment.resourceId -eq $ResourceId) { $null = $Assigned.Add("$($Assignment.appRoleId)") }
            }
            foreach ($AppRoleId in $Items) {
                $Total++
                $Name = $Known[$AppRoleId]
                if ($Assigned.Contains($AppRoleId)) {
                    $Results.Add([pscustomobject]@{ resultText = "$Name is already granted on $($Resource.displayName)"; state = 'success' })
                    continue
                }
                try {
                    $Body = ConvertTo-Json -Compress -InputObject @{ principalId = $ServicePrincipalId; resourceId = $ResourceId; appRoleId = $AppRoleId }
                    $null = New-GraphPOSTRequest -uri "$SpUri/appRoleAssignments" -tenantid $TenantFilter -type POST -body $Body
                    $Message = "Granted application permission $Name on $($Resource.displayName)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'success' })
                } catch {
                    $Failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Failed to grant application permission $Name on $($Resource.displayName): $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
                }
            }
        } elseif ($Mode -eq 'ApplicationRemove') {
            # Assignment ids are case-sensitive.
            $Assignments = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
            foreach ($Assignment in @(New-GraphGetRequest -uri "$SpUri/appRoleAssignments" -tenantid $TenantFilter)) {
                if ($Assignment.id) { $Assignments[$Assignment.id] = $Assignment }
            }
            $Found = $Items.Where({ $Assignments.ContainsKey($_) })
            if ($Found.Count -eq 0) {
                throw [System.Management.Automation.ItemNotFoundException]::new('None of the app role assignments exist on this application')
            }
            $RoleNames = @{}
            $ResourceIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Id in $Found) { $null = $ResourceIds.Add("$($Assignments[$Id].resourceId)") }
            foreach ($Rid in $ResourceIds) {
                try {
                    $Res = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$Rid`?`$select=appRoles" -tenantid $TenantFilter
                    foreach ($Role in @($Res.appRoles)) { if ($Role.id) { $RoleNames[$Role.id] = $Role.value } }
                } catch {
                    Write-Information "Could not read app roles of $Rid, reporting role ids: $($_.Exception.Message)"
                }
            }
            foreach ($Id in $Items) {
                $Total++
                $Assignment = $null
                if (-not $Assignments.TryGetValue($Id, [ref]$Assignment)) {
                    $Failed++
                    $Results.Add([pscustomobject]@{ resultText = "App role assignment $Id does not exist on this application"; state = 'error' })
                    continue
                }
                $Name = $RoleNames["$($Assignment.appRoleId)"] ?? $Assignment.appRoleId
                try {
                    $null = New-GraphPOSTRequest -uri "$SpUri/appRoleAssignments/$Id" -tenantid $TenantFilter -type DELETE
                    $Message = "Removed application permission $Name on $($Assignment.resourceDisplayName)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'success' })
                } catch {
                    $Failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Failed to remove application permission $Name on $($Assignment.resourceDisplayName): $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
                }
            }
        } else {
            $Grants = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$ServicePrincipalId'" -tenantid $TenantFilter).Where({ $_.resourceId -eq $ResourceId })

            if ($Mode -eq 'DelegatedAdd') {
                $Total = 1
                $Scopes = $Items.ForEach({ $Known[$_] })
                $TenantGrant = $Grants.Where({ $_.consentType -eq 'AllPrincipals' }, 'First')[0]
                try {
                    if ($TenantGrant) {
                        $Current = "$($TenantGrant.scope)".Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
                        $Missing = $Scopes.Where({ $_ -notin $Current })
                        if ($Missing.Count -gt 0) {
                            $Body = ConvertTo-Json -Compress -InputObject @{ scope = (@($Current; $Missing) -join ' ') }
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($TenantGrant.id)" -tenantid $TenantFilter -type PATCH -body $Body
                        }
                    } else {
                        $Missing = $Scopes
                        $Body = ConvertTo-Json -Compress -InputObject @{ clientId = $ServicePrincipalId; consentType = 'AllPrincipals'; resourceId = $ResourceId; scope = ($Scopes -join ' ') }
                        $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -tenantid $TenantFilter -type POST -body $Body
                    }
                    $Message = if ($Missing.Count -gt 0) {
                        "Granted delegated permission(s) $($Missing -join ', ') on $($Resource.displayName) for all users"
                    } else {
                        "$($Scopes -join ', ') already granted on $($Resource.displayName) for all users"
                    }
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'success' })
                } catch {
                    $Failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Failed to grant delegated permission(s) $($Scopes -join ', ') on $($Resource.displayName): $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
                    $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
                }
            } else {
                $RemoveSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$Items, [StringComparer]::OrdinalIgnoreCase)
                foreach ($Grant in $Grants) {
                    $Current = "$($Grant.scope)".Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
                    $Keep = $Current.Where({ -not $RemoveSet.Contains($_) })
                    if ($Keep.Count -eq $Current.Count) { continue }
                    $Total++
                    $Removed = ($Current.Where({ $RemoveSet.Contains($_) })) -join ', '
                    $Target = if ($Grant.consentType -eq 'AllPrincipals') { 'the grant for all users' } else { "the grant for user $($Grant.principalId)" }
                    try {
                        if ($Keep.Count -eq 0) {
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($Grant.id)" -tenantid $TenantFilter -type DELETE
                        } else {
                            $Body = ConvertTo-Json -Compress -InputObject @{ scope = ($Keep -join ' ') }
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$($Grant.id)" -tenantid $TenantFilter -type PATCH -body $Body
                        }
                        $Message = "Removed delegated permission(s) $Removed from $Target"
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
                        $Results.Add([pscustomobject]@{ resultText = $Message; state = 'success' })
                    } catch {
                        $Failed++
                        $ErrorMessage = Get-CippException -Exception $_
                        $Message = "Failed to remove delegated permission(s) $Removed from $Target`: $($ErrorMessage.NormalizedError)"
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
                        $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
                    }
                }
                if ($Total -eq 0) {
                    throw [System.Management.Automation.ItemNotFoundException]::new("None of the delegated permissions $($Items -join ', ') are granted to this application")
                }
            }
        }
        $StatusCode = Get-CippBulkStatusCode -Total $Total -Failed $Failed
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to $($Action.ToLower()) $($Type.ToLower()) permissions: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}
