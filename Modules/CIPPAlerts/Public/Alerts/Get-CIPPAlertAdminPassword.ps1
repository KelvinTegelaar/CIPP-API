
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
        $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId

        # Get role assignments without expanding principal to avoid rate limiting
        $RoleAssignments = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'" -tenantid $($TenantFilter) | Where-Object { $_.principalOrganizationId -EQ $TenantId }

        # Build bulk requests for each principalId
        $UserRequests = $RoleAssignments | ForEach-Object {
            [PSCustomObject]@{
                id     = $_.principalId
                method = 'GET'
                url    = "users/$($_.principalId)?`$select=id,UserPrincipalName,lastPasswordChangeDateTime,createdDateTime"
            }
        }

        # Make bulk call to get user information
        if ($UserRequests) {
            $BulkResults = New-GraphBulkRequest -Requests @($UserRequests) -tenantid $TenantFilter

            $Cutoff = (Get-Date).AddDays(-1)
            $AlertData = @(foreach ($Result in $BulkResults) {
                    if ($Result.status -ne 200 -or -not $Result.body.lastPasswordChangeDateTime) { continue }
                    $Changed = [datetime]$Result.body.lastPasswordChangeDateTime
                    if ($Changed -le $Cutoff) { continue }
                    # Graph sets the password timestamp when an account is created, which is not a change
                    if ($Result.body.createdDateTime -and ($Changed - [datetime]$Result.body.createdDateTime).TotalMinutes -lt 5) { continue }
                    $Result.body | Select-Object -Property UserPrincipalName, lastPasswordChangeDateTime
                }) | Sort-Object UserPrincipalName
        } else {
            $AlertData = @()
        }

        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not get admin password changes for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
