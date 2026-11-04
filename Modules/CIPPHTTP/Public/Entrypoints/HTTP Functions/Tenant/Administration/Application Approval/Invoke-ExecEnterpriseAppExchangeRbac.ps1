function Invoke-ExecEnterpriseAppExchangeRbac {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .DESCRIPTION
        Manages the Exchange access of enterprise applications (service principals).
        AddRoles assigns Exchange RBAC for Applications roles, organisation-wide or scoped to a management scope or
        administrative unit, registering the app in Exchange first when needed. ChangeScope assigns the same role
        with the new scope and then removes the old assignment. RemoveRoles removes role assignments of the app.
        These three need ServicePrincipalId.
        RemovePolicies removes application access policies. With ServicePrincipalId only that app's own policies are
        removed: a policy for every app ('*') or that also names other apps is refused. Without it, any policy is.
        NewScope creates a management scope from a name and a recipient filter; RemoveScope removes management
        scopes no role assignment uses. Changes to the CIPP-SAM application itself are refused. After a role or
        policy change the matching CIPP DB cache is refreshed, so the permission exposure report shows it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $ServicePrincipalId = "$($Request.Body.ServicePrincipalId)"
    $Action = "$($Request.Body.Action)"
    $Guid = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $AppActions = @('AddRoles', 'ChangeScope', 'RemoveRoles')

    function Get-BodyValue($Value) {
        # Autocomplete and select fields post { label, value } objects.
        if ($null -eq $Value) { return $null }
        "$($Value.value ?? $Value)".Trim()
    }
    function Get-BodyValues($Value) {
        @(foreach ($Item in @($Value)) { if ($Item) { Get-BodyValue $Item } })
    }
    function New-BadRequest($Message) {
        [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = $Message } }
    }

    if ($Action -notin ($AppActions + @('RemovePolicies', 'NewScope', 'RemoveScope'))) {
        return (New-BadRequest 'Action must be AddRoles, ChangeScope, RemoveRoles, RemovePolicies, NewScope or RemoveScope')
    }
    if (-not $TenantFilter -or ($ServicePrincipalId -and $ServicePrincipalId -notmatch $Guid) -or ($Action -in $AppActions -and -not $ServicePrincipalId)) {
        return (New-BadRequest "tenantFilter$(if ($Action -in $AppActions) { ' and a valid ServicePrincipalId are' } else { ' is' }) required")
    }

    # The scope for AddRoles and ChangeScope: organisation-wide, a management scope or an administrative unit.
    $ScopeParams = @{}
    $ScopeLabel = 'the whole organisation'
    if ($Action -in @('AddRoles', 'ChangeScope')) {
        $ScopeType = Get-BodyValue $Request.Body.ScopeType
        switch ($ScopeType) {
            'Organization' { }
            'ManagementScope' {
                $ScopeName = Get-BodyValue $Request.Body.ManagementScope
                if (-not $ScopeName) { return (New-BadRequest 'Select a management scope') }
                $ScopeParams.CustomResourceScope = $ScopeName
                $ScopeLabel = "the management scope $ScopeName"
            }
            'AdministrativeUnit' {
                $AdminUnit = $Request.Body.AdministrativeUnit
                $AdminUnitId = Get-BodyValue $AdminUnit
                if ($AdminUnitId -notmatch $Guid) { return (New-BadRequest 'Select an administrative unit') }
                $ScopeParams.RecipientAdministrativeUnitScope = $AdminUnitId
                $ScopeLabel = "the administrative unit $(if ($AdminUnit.label) { $AdminUnit.label } else { $AdminUnitId })"
            }
            default { return (New-BadRequest 'ScopeType must be Organization, ManagementScope or AdministrativeUnit') }
        }
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $Total = 0
    # Add-Result counts failures here: a nested function cannot change this function's variables.
    $Counts = @{ Failed = 0 }
    function Add-Result($Message, [switch]$IsError, $ErrorData) {
        if ($IsError) {
            $Counts.Failed++
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorData
        } else {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        }
        $Results.Add([pscustomobject]@{ resultText = $Message; state = $(if ($IsError) { 'error' } else { 'success' }) })
    }

    try {
        $Sp = $null
        $AppName = $null
        if ($ServicePrincipalId) {
            $Sp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId`?`$select=id,appId,displayName" -tenantid $TenantFilter
            $SamAppId = [System.Environment]::GetEnvironmentVariable('ApplicationID')
            if ($SamAppId -and $Sp.appId -eq $SamAppId) {
                throw [System.ArgumentException]::new('Refusing to change the Exchange access of the CIPP-SAM application itself.')
            }
            $AppName = $Sp.displayName
        }

        switch ($Action) {
            'RemoveScope' {
                $ScopeNames = Get-BodyValues $Request.Body.ScopeNames
                if ($ScopeNames.Count -eq 0) { throw [System.ArgumentException]::new('ScopeNames must hold at least one management scope') }
                # A scope in use by any role assignment, an app's or an admin's, is kept.
                $InUse = @{}
                foreach ($Assignment in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementRoleAssignment')) {
                    foreach ($Field in 'CustomResourceScope', 'CustomRecipientWriteScope', 'CustomConfigWriteScope', 'ExclusiveRecipientWriteScope', 'ExclusiveConfigWriteScope') {
                        $Name = [string]$Assignment.$Field
                        if ($Name) { $InUse[$Name] = 1 + [int]$InUse[$Name] }
                    }
                }
                foreach ($Name in $ScopeNames) {
                    $Total++
                    if ($InUse[$Name]) {
                        Add-Result "The management scope $Name is used by $($InUse[$Name]) role assignment(s): remove or rescope them first" -IsError
                        continue
                    }
                    try {
                        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-ManagementScope' -cmdParams @{ Identity = $Name; Confirm = $false } -useSystemMailbox $true
                        Add-Result "Removed the management scope $Name"
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Add-Result "Failed to remove the management scope $($Name): $($ErrorMessage.NormalizedError)" -IsError -ErrorData $ErrorMessage
                    }
                }
            }
            'NewScope' {
                $Name = Get-BodyValue $Request.Body.ScopeName
                $Filter = Get-BodyValue $Request.Body.RecipientFilter
                if (-not $Name -or -not $Filter) { throw [System.ArgumentException]::new('A name and a recipient filter are required') }
                $Total++
                try {
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ManagementScope' -cmdParams @{ Name = $Name; RecipientRestrictionFilter = $Filter } -useSystemMailbox $true
                    Add-Result "Created the management scope $Name ($Filter)"
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Add-Result "Failed to create the management scope $($Name): $($ErrorMessage.NormalizedError)" -IsError -ErrorData $ErrorMessage
                }
            }
            'RemovePolicies' {
                $PolicyIds = Get-BodyValues $Request.Body.PolicyIds
                if ($PolicyIds.Count -eq 0) { throw [System.ArgumentException]::new('PolicyIds must hold at least one policy') }
                # A policy can name several apps: one row per app, so collect the apps per policy.
                $Policies = @{}
                $PolicyApps = @{}
                foreach ($Policy in @(Get-CIPPExoApplicationAccessPolicy -TenantFilter $TenantFilter)) {
                    $Identity = [string]$Policy.policyIdentity
                    $Policies[$Identity] = $Policy
                    if (-not $PolicyApps.ContainsKey($Identity)) { $PolicyApps[$Identity] = [System.Collections.Generic.List[string]]::new() }
                    $PolicyApps[$Identity].Add([string]$Policy.appId)
                }
                $ForApp = if ($AppName) { " from $AppName" } else { '' }
                foreach ($PolicyId in $PolicyIds) {
                    $Total++
                    $Policy = $Policies[$PolicyId]
                    $Apps = @($PolicyApps[$PolicyId])
                    if (-not $Policy -or ($Sp -and $Sp.appId -notin $Apps -and '*' -notin $Apps)) {
                        Add-Result "Application access policy $PolicyId does not exist$(if ($AppName) { " for $AppName" })" -IsError
                        continue
                    }
                    if ($Sp -and '*' -in $Apps) {
                        Add-Result "The application access policy for $($Policy.scopeName) applies to every app: remove it from App Mailbox Access, not from one app" -IsError
                        continue
                    }
                    if ($Sp -and @($Apps | Where-Object { $_ -ne $Sp.appId }).Count -gt 0) {
                        Add-Result "The application access policy for $($Policy.scopeName) also applies to other apps: remove it from App Mailbox Access, not from one app" -IsError
                        continue
                    }
                    try {
                        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-ApplicationAccessPolicy' -cmdParams @{ Identity = $PolicyId; Confirm = $false } -useSystemMailbox $true
                        Add-Result "Removed the $($Policy.accessRight) application access policy for $($Policy.scopeName)$ForApp"
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Add-Result "Failed to remove the application access policy for $($Policy.scopeName)$($ForApp): $($ErrorMessage.NormalizedError)" -IsError -ErrorData $ErrorMessage
                    }
                }
            }
            default {
                # AddRoles, ChangeScope and RemoveRoles work on this app's role assignments.
                $ExoServicePrincipals = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ServicePrincipal')
                $Held = @(Get-CIPPExoAppRoleAssignment -TenantFilter $TenantFilter -ServicePrincipals $ExoServicePrincipals |
                        Where-Object { $_.servicePrincipalId -eq $ServicePrincipalId -or ($_.appId -and $_.appId -eq $Sp.appId) })
                $HeldById = @{}
                foreach ($Assignment in $Held) { $HeldById[[string]$Assignment.id] = $Assignment }
                $HasScope = {
                    param($Assignment)
                    [string]$Assignment.customResourceScope -eq [string]$ScopeParams.CustomResourceScope -and
                    [string]$Assignment.recipientAdministrativeUnitScope -eq [string]$ScopeParams.RecipientAdministrativeUnitScope
                }

                $Roles = if ($Action -eq 'AddRoles') { Get-BodyValues $Request.Body.Roles } else { @() }
                $AssignmentIds = if ($Action -ne 'AddRoles') { Get-BodyValues $Request.Body.AssignmentIds } else { @() }
                if ($Action -eq 'AddRoles' -and $Roles.Count -eq 0) { throw [System.ArgumentException]::new('Select at least one Application role') }
                if ($Action -ne 'AddRoles' -and $AssignmentIds.Count -eq 0) { throw [System.ArgumentException]::new('AssignmentIds must hold at least one role assignment') }

                if ($Action -ne 'RemoveRoles') {
                    # The -App parameter only takes Application roles; checking first gives a clear error.
                    $KnownRoles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
                    foreach ($Role in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementRole')) {
                        if ([string]$Role.Name -like 'Application *') { $null = $KnownRoles.Add([string]$Role.Name) }
                    }
                    $Unknown = @($Roles | Where-Object { -not $KnownRoles.Contains($_) })
                    if ($Unknown.Count -gt 0) { throw [System.ArgumentException]::new("Unknown Application role(s): $($Unknown -join ', ')") }

                    # Exchange only takes role assignments for an app registered with it.
                    $Registered = $ExoServicePrincipals | Where-Object { [string]$_.ObjectId -eq $ServicePrincipalId -or [string]$_.AppId -eq $Sp.appId }
                    if (-not $Registered) {
                        try {
                            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ServicePrincipal' -cmdParams @{ AppId = $Sp.appId; ObjectId = $ServicePrincipalId; DisplayName = $AppName } -useSystemMailbox $true
                            Add-Result "Registered $AppName in Exchange"
                        } catch {
                            if ($_.Exception.Message -notmatch 'already exist') { throw }
                        }
                    }
                }

                $Assign = {
                    param($RoleName)
                    $Params = @{ App = $ServicePrincipalId; Role = $RoleName } + $ScopeParams
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ManagementRoleAssignment' -cmdParams $Params -useSystemMailbox $true
                }

                if ($Action -eq 'AddRoles') {
                    foreach ($RoleName in $Roles) {
                        $Total++
                        if (@($Held | Where-Object { $_.role -eq $RoleName -and (& $HasScope $_) }).Count -gt 0) {
                            $Results.Add([pscustomobject]@{ resultText = "$AppName already holds $RoleName for $ScopeLabel"; state = 'success' })
                            continue
                        }
                        try {
                            & $Assign $RoleName
                            Add-Result "Assigned $RoleName to $AppName for $ScopeLabel"
                        } catch {
                            $ErrorMessage = Get-CippException -Exception $_
                            Add-Result "Failed to assign $RoleName to $($AppName): $($ErrorMessage.NormalizedError)" -IsError -ErrorData $ErrorMessage
                        }
                    }
                } else {
                    foreach ($Id in $AssignmentIds) {
                        $Total++
                        $Assignment = $HeldById[$Id]
                        if (-not $Assignment) {
                            Add-Result "Role assignment $Id does not belong to $AppName" -IsError
                            continue
                        }
                        $RoleName = $Assignment.role
                        try {
                            if ($Action -eq 'ChangeScope') {
                                if (& $HasScope $Assignment) {
                                    $Results.Add([pscustomobject]@{ resultText = "$RoleName of $AppName is already scoped to $ScopeLabel"; state = 'success' })
                                    continue
                                }
                                # Assign with the new scope before removing the old one, so the app never loses access.
                                if (@($Held | Where-Object { $_.role -eq $RoleName -and (& $HasScope $_) }).Count -eq 0) { & $Assign $RoleName }
                            }
                            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-ManagementRoleAssignment' -cmdParams @{ Identity = $Id; Confirm = $false } -useSystemMailbox $true
                            Add-Result $(if ($Action -eq 'ChangeScope') { "Scoped $RoleName of $AppName to $ScopeLabel" } else { "Removed $RoleName from $AppName" })
                        } catch {
                            $ErrorMessage = Get-CippException -Exception $_
                            Add-Result "Failed to $(if ($Action -eq 'ChangeScope') { 'change the scope of' } else { 'remove' }) $RoleName for $($AppName): $($ErrorMessage.NormalizedError)" -IsError -ErrorData $ErrorMessage
                        }
                    }
                }
            }
        }

        # The permission exposure report reads role assignments and policies from the CIPP DB: refresh the one
        # changed so the report does not keep showing access that was just removed or miss access just given.
        $CacheRefresh = if ($Action -in $AppActions) { 'Set-CIPPDBCacheExoAppRoleAssignments' } elseif ($Action -eq 'RemovePolicies') { 'Set-CIPPDBCacheExoApplicationAccessPolicies' }
        if ($CacheRefresh -and $Total -gt $Counts.Failed) {
            try {
                & $CacheRefresh -TenantFilter $TenantFilter
            } catch {
                Write-Information "Exchange app access changed but the $CacheRefresh refresh failed: $($_.Exception.Message)"
            }
        }
        $StatusCode = Get-CippBulkStatusCode -Total $Total -Failed $Counts.Failed
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to change the Exchange access of $(if ($AppName) { $AppName } else { $ServicePrincipalId }): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add([pscustomobject]@{ resultText = $Message; state = 'error' })
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}
