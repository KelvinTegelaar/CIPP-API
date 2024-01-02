
function Push-CIPPAlertAdminPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$QueueItem,
        $TriggerMetadata
    )
    try {
        New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'&`$expand=principal" -tenantid $($QueueItem.tenant) | Where-Object { ($_.principalOrganizationId -EQ $QueueItem.tenantid) -and ($_.principal.'@odata.type' -eq '#microsoft.graph.user') } | ForEach-Object {
            $LastChanges = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$($_.principalId)?`$select=UserPrincipalName,lastPasswordChangeDateTime" -tenant $($QueueItem.tenant)
            if ($LastChanges.LastPasswordChangeDateTime -gt (Get-Date).AddDays(-1)) {
                Write-AlertMessage -tenant $($QueueItem.tenant) -message "Admin password has been changed for $($LastChanges.UserPrincipalName) in last 24 hours"
            }
        }
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Could not get admin password changes for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
