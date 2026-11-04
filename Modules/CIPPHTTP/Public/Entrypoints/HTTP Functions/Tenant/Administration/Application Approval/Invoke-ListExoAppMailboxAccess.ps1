function Invoke-ListExoAppMailboxAccess {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Lists the mailbox access Exchange gives apps across a tenant, by Type:
        Roles: every Exchange RBAC for Applications role assignment, with the app, the scope and the role's impact
        and suspicion from the risky permissions catalog.
        Policies: every application access policy, once per policy, with the apps it names ('*' is every app).
        Scopes: every management scope, with how many app and other role assignments use it.
        AvailableRoles: the Application roles that can be assigned, with their impact from the catalog.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Type = "$($Request.Query.Type ?? $Request.Body.Type)"

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Select a single tenant' } })
    }
    if ($Type -notin @('Roles', 'Policies', 'Scopes', 'AvailableRoles')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Type must be Roles, Policies, Scopes or AvailableRoles' } })
    }

    try {
        $Rows = switch ($Type) {
            'Roles' {
                $Catalog = (Get-CIPPRiskyPermissionCatalog).ExchangeRole
                foreach ($Assignment in @(Get-CIPPExoAppRoleAssignment -TenantFilter $TenantFilter | Sort-Object appDisplayName, role)) {
                    $Entry = $null
                    [void]$Catalog.TryGetValue([string]$Assignment.role, [ref]$Entry)
                    $Assignment | Add-Member -NotePropertyMembers @{
                        scope     = if ($Assignment.customResourceScope) { 'Management scope' } elseif ($Assignment.recipientAdministrativeUnitScope) { 'Administrative unit' } else { 'Organization' }
                        scopeName = if ($Assignment.customResourceScope) { $Assignment.customResourceScope } else { $Assignment.recipientAdministrativeUnitScope }
                        impact    = $Entry.impact
                        suspicion = $Entry.suspicion
                    } -PassThru
                }
            }
            'Policies' {
                $Names = @{}
                foreach ($Sp in @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals?$select=id,appId,displayName&$top=999' -tenantid $TenantFilter)) {
                    if ($Sp.appId) { $Names[([string]$Sp.appId).ToLowerInvariant()] = $Sp }
                }
                # One row per app from the reader: fold them back into one row per policy.
                $ByPolicy = [ordered]@{}
                foreach ($Row in @(Get-CIPPExoApplicationAccessPolicy -TenantFilter $TenantFilter)) {
                    $Identity = [string]$Row.policyIdentity
                    if (-not $ByPolicy.Contains($Identity)) {
                        $ByPolicy[$Identity] = [PSCustomObject]@{
                            policyIdentity      = $Identity
                            accessRight         = $Row.accessRight
                            scopeName           = if ($Row.scopeName) { $Row.scopeName } else { $Row.scopeIdentity }
                            scopeIdentityRaw    = $Row.scopeIdentityRaw
                            description         = $Row.description
                            isValid             = $Row.isValid
                            appliesToEveryApp   = $false
                            appIds              = [System.Collections.Generic.List[string]]::new()
                            apps                = [System.Collections.Generic.List[string]]::new()
                            servicePrincipalIds = [System.Collections.Generic.List[string]]::new()
                        }
                    }
                    $Policy = $ByPolicy[$Identity]
                    $Policy.appIds.Add([string]$Row.appId)
                    if ($Row.appId -eq '*') {
                        $Policy.appliesToEveryApp = $true
                        $Policy.apps.Add('Every app')
                    } else {
                        $Sp = $Names[([string]$Row.appId).ToLowerInvariant()]
                        $Policy.apps.Add($(if ($Sp) { [string]$Sp.displayName } else { "$($Row.appId) (not in this tenant)" }))
                        if ($Sp) { $Policy.servicePrincipalIds.Add([string]$Sp.id) }
                    }
                }
                foreach ($Policy in $ByPolicy.Values) {
                    $Policy | Add-Member -NotePropertyMembers @{
                        appNames           = $Policy.apps -join ', '
                        # Set for a policy naming one app here, to link to that app.
                        servicePrincipalId = if (-not $Policy.appliesToEveryApp -and $Policy.servicePrincipalIds.Count -eq 1) { $Policy.servicePrincipalIds[0] } else { $null }
                    } -PassThru
                }
            }
            'AvailableRoles' {
                $Catalog = (Get-CIPPRiskyPermissionCatalog).ExchangeRole
                foreach ($Role in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementRole' | Where-Object { [string]$_.Name -like 'Application *' } | Sort-Object Name)) {
                    $Entry = $null
                    [void]$Catalog.TryGetValue([string]$Role.Name, [ref]$Entry)
                    [PSCustomObject]@{ name = [string]$Role.Name; description = [string]$Role.Description; impact = $Entry.impact }
                }
            }
            'Scopes' {
                $AppUses = @{}
                $OtherUses = @{}
                foreach ($Assignment in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementRoleAssignment')) {
                    $IsApp = [string]$Assignment.Role -like 'Application *'
                    foreach ($Field in 'CustomResourceScope', 'CustomRecipientWriteScope', 'CustomConfigWriteScope', 'ExclusiveRecipientWriteScope', 'ExclusiveConfigWriteScope') {
                        $Name = [string]$Assignment.$Field
                        if (-not $Name) { continue }
                        if ($IsApp) { $AppUses[$Name] = 1 + [int]$AppUses[$Name] } else { $OtherUses[$Name] = 1 + [int]$OtherUses[$Name] }
                    }
                }
                foreach ($Scope in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementScope' | Where-Object { $_.Name } | Sort-Object Name)) {
                    $Name = [string]$Scope.Name
                    [PSCustomObject]@{
                        name                 = $Name
                        recipientFilter      = [string]$Scope.RecipientFilter
                        scopeRestrictionType = [string]$Scope.ScopeRestrictionType
                        exclusive            = [bool]$Scope.Exclusive
                        appAssignmentCount   = [int]$AppUses[$Name]
                        otherAssignmentCount = [int]$OtherUses[$Name]
                        whenCreatedUTC       = $Scope.WhenCreatedUTC
                    }
                }
            }
        }
        $Body = @{ Results = @($Rows) }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to list Exchange app mailbox access ($Type): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to list Exchange app mailbox access: $($ErrorMessage.NormalizedError)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
