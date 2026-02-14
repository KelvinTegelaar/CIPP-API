
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
        
        # Get role assignments without expanding principal to avoid rate limiting
        $RoleAssignments = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '62e90394-69f5-4237-9190-012177145e10'" -tenantid $($TenantFilter) | Where-Object { $_.principalOrganizationId -EQ $TenantId }
        
        # Build bulk requests for each principalId
        $UserRequests = $RoleAssignments | ForEach-Object {
            [PSCustomObject]@{
                id     = $_.principalId
                method = 'GET'
                url    = "users/$($_.principalId)?`$select=id,UserPrincipalName,lastPasswordChangeDateTime"
            }
        }
        
        # Make bulk call to get user information
        if ($UserRequests) {
            $BulkResults = New-GraphBulkRequest -Requests @($UserRequests) -tenantid $TenantFilter
            
            # Filter users with recent password changes and sort to prevent duplicate alerts
            $AlertData = $BulkResults | Where-Object { $_.status -eq 200 -and $_.body.lastPasswordChangeDateTime -gt (Get-Date).AddDays(-1) } | ForEach-Object {
                $_.body | Select-Object -Property UserPrincipalName, lastPasswordChangeDateTime
            } | Sort-Object UserPrincipalName
        } else {
            $AlertData = @()
        }
        
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Could not get admin password changes for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}
