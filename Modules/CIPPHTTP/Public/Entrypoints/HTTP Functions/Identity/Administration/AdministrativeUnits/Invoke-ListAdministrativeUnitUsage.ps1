function Invoke-ListAdministrativeUnitUsage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    .DESCRIPTION
        Lists what an administrative unit is used for: Entra role assignments scoped to it (active and PIM
        eligible) and Exchange role assignments scoped to it, for admins and for apps (RBAC for Applications).
        Exchange is read best effort: when it cannot be read, the Entra rows are returned with status 207.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # Object id of the administrative unit.
    $ID = $Request.Query.ID ?? $Request.Body.ID
    # Display name of the unit, used to match Exchange assignments that report the unit by name.
    $DisplayName = [string]($Request.Query.displayName ?? $Request.Body.displayName)

    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Select a single tenant' }
            })
    }
    if ([string]::IsNullOrWhiteSpace($ID) -or -not (Test-IsGuid -String $ID)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'ID must be the object id of an administrative unit' }
            })
    }

    $Rows = [System.Collections.Generic.List[object]]::new()
    try {
        # Same rows as the Roles page, so the role assignment actions work on them unchanged.
        $Scope = "/administrativeUnits/$ID"
        foreach ($Assignment in @(Get-CIPPPIMRoleAssignments -TenantFilter $TenantFilter)) {
            if ($Assignment.DirectoryScopeId -ne $Scope) { continue }
            $Assignment.PSObject.Properties.Add([psnoteproperty]::new('Source', 'Entra role'))
            $Rows.Add($Assignment)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to read the role assignments scoped to administrative unit $($ID): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = $Result }
            })
    }

    $StatusCode = [HttpStatusCode]::OK
    try {
        # An assignment is scoped to the unit by its object id; the name is matched too in case Exchange reports that.
        $ExoAssignments = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementRoleAssignment' | Where-Object {
                [string]$_.RecipientAdministrativeUnitScope -and [string]$_.RecipientAdministrativeUnitScope -in @($ID, $DisplayName)
            })
        $AppNames = @{}
        if (@($ExoAssignments.Where({ [string]$_.Role -like 'Application *' })).Count -gt 0) {
            # An app assignment names the app by its Exchange identity; map it to the Entra app.
            foreach ($ExoSp in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ServicePrincipal')) {
                foreach ($Key in @($ExoSp.Identity, $ExoSp.Name, $ExoSp.ObjectId, $ExoSp.AppId, $ExoSp.DisplayName)) {
                    if ($Key -and -not $AppNames.ContainsKey([string]$Key)) { $AppNames[[string]$Key] = $ExoSp }
                }
            }
        }
        foreach ($Assignment in $ExoAssignments) {
            $IsApp = [string]$Assignment.Role -like 'Application *'
            $ExoSp = if ($IsApp) { $AppNames[[string]$Assignment.RoleAssignee] ?? $AppNames[[string]$Assignment.RoleAssigneeName] }
            $Rows.Add([PSCustomObject]@{
                    Tenant               = $TenantFilter
                    Id                   = [string]($Assignment.Guid ?? $Assignment.Identity)
                    Source               = if ($IsApp) { 'Exchange app role' } else { 'Exchange admin role' }
                    RoleDisplayName      = [string]$Assignment.Role
                    PrincipalDisplayName = if ($ExoSp) { [string]$ExoSp.DisplayName } else { [string]($Assignment.RoleAssigneeName ?? $Assignment.RoleAssignee) }
                    PrincipalType        = if ($IsApp) { 'ServicePrincipal' } else { [string]$Assignment.RoleAssigneeType }
                    AssignmentType       = if ($Assignment.Enabled -eq $false) { 'Disabled' } else { 'Exchange RBAC' }
                    ServicePrincipalId   = if ($ExoSp) { [string]$ExoSp.ObjectId }
                    StartDateTime        = $Assignment.WhenCreatedUTC
                })
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not read Exchange role assignments for administrative unit $($ID): $($_.Exception.Message)" -Sev 'Warning'
        $StatusCode = [HttpStatusCode]::MultiStatus
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Rows)
        })
}
