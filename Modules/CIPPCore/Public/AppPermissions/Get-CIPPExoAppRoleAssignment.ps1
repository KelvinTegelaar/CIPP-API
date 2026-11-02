function Get-CIPPExoAppRoleAssignment {
    <#
    .SYNOPSIS
        Reads the Exchange RBAC for Applications role assignments of a tenant
    .DESCRIPTION
        Exchange can give an app mailbox access through its own role assignments (RBAC for Applications), which
        Entra does not show as a permission or consent. Reads the service principals registered in Exchange and,
        when there are any, the assignments of the 'Application *' roles. Returns one row per assignment with the
        app's Entra appId and service principal object id, the scope (a management scope with its recipient
        filter, or an administrative unit) and when it was created. Errors reading the service principals or
        assignments are thrown; a scope filter that cannot be read is left out.
    .PARAMETER TenantFilter
        The tenant to read
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    # No service principal registered in Exchange means no app can hold an Exchange application role.
    $ExoServicePrincipals = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ServicePrincipal')
    if ($ExoServicePrincipals.Count -eq 0) { return @() }

    # An assignment names the app by its Exchange identity: index every name it may use.
    $SpByKey = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Field in 'Identity', 'Name', 'Guid', 'ExchangeObjectId', 'ObjectId', 'AppId', 'DisplayName') {
        foreach ($ExoSp in $ExoServicePrincipals) {
            $Key = [string]$ExoSp.$Field
            if ($Key -and -not $SpByKey.ContainsKey($Key)) { $SpByKey[$Key] = $ExoSp }
        }
    }

    $Assignments = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementRoleAssignment' | Where-Object { [string]$_.Role -like 'Application *' })
    if ($Assignments.Count -eq 0) { return @() }

    $ScopeFilters = @{}
    if (@($Assignments | Where-Object { $_.CustomResourceScope }).Count -gt 0) {
        try {
            foreach ($Scope in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementScope')) {
                if ($Scope.Name) { $ScopeFilters[[string]$Scope.Name] = [string]$Scope.RecipientFilter }
            }
        } catch {
            Write-Information "Exchange management scopes unavailable for $($TenantFilter): $($_.Exception.Message)"
        }
    }

    foreach ($Assignment in $Assignments) {
        $ExoSp = $null
        foreach ($Key in @([string]$Assignment.RoleAssignee, [string]$Assignment.RoleAssigneeName)) {
            if ($Key -and $SpByKey.TryGetValue($Key, [ref]$ExoSp)) { break }
        }
        $ResourceScope = [string]$Assignment.CustomResourceScope
        [PSCustomObject]@{
            id                               = if ($Assignment.Guid) { [string]$Assignment.Guid } else { [string]$Assignment.Identity }
            name                             = [string]$Assignment.Name
            role                             = [string]$Assignment.Role
            roleAssignee                     = if ($Assignment.RoleAssigneeName) { [string]$Assignment.RoleAssigneeName } else { [string]$Assignment.RoleAssignee }
            appId                            = [string]$ExoSp.AppId
            servicePrincipalId               = [string]$ExoSp.ObjectId
            enabled                          = $Assignment.Enabled
            customResourceScope              = $ResourceScope
            customResourceScopeFilter        = if ($ResourceScope) { $ScopeFilters[$ResourceScope] } else { $null }
            recipientAdministrativeUnitScope = [string]$Assignment.RecipientAdministrativeUnitScope
            whenCreatedUTC                   = $Assignment.WhenCreatedUTC
        }
    }
}
