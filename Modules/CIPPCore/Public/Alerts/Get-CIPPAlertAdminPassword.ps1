
function Get-CIPPAlertAdminPassword {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $TenantId = (Get-Tenants | Where-Object -Property defaultDomainName -EQ $TenantFilter).customerId
        $AlertData = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'&`$expand=principal" -tenantid $($TenantFilter) | Where-Object { ($_.principalOrganizationId -EQ $TenantId) -and ($_.principal.'@odata.type' -eq '#microsoft.graph.user') } | ForEach-Object {
            $LastChanges = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.principalId)?`$select=UserPrincipalName,lastPasswordChangeDateTime" -tenant $($TenantFilter)
            if ($LastChanges.LastPasswordChangeDateTime -gt (Get-Date).AddDays(-1)) {
                $LastChanges | Select-Object -Property UserPrincipalName, lastPasswordChangeDateTime
            }
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get admin password changes for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
