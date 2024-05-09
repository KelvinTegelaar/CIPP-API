
function Get-CIPPAlertAdminPassword {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )
    try {
        New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'&`$expand=principal" -tenantid $($TenantFilter) | Where-Object { ($_.principalOrganizationId -EQ $TenantFilter) -and ($_.principal.'@odata.type' -eq '#microsoft.graph.user') } | ForEach-Object {
            $LastChanges = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.principalId)?`$select=UserPrincipalName,lastPasswordChangeDateTime" -tenant $($TenantFilter)
            if ($LastChanges.LastPasswordChangeDateTime -gt (Get-Date).AddDays(-1)) {
                Write-AlertMessage -tenant $($TenantFilter) -message "Admin password has been changed for $($LastChanges.UserPrincipalName) in last 24 hours"
            }
        }
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get admin password changes for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
