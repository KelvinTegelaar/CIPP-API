function Set-CIPPDBCachePlannerUserPolicies {
    <#
    .SYNOPSIS
        Caches the Planner tenant-admin UserPolicy of every enabled, Planner-licensed member

    .DESCRIPTION
        On-demand only (no scheduled collection group): collected on miss and refreshed by the
        PlannerBlockTaskDelete baseline. The UserPolicy API (tasks.office.com) has no list or batch
        endpoint, so each candidate is read individually. A 403/404 means no policy exists yet and is
        stored as policyExists = false; any other read failure skips that user.

    .PARAMETER TenantFilter
        The tenant to cache Planner user policies for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $PlannerPlanId = 'b737dad2-2f6c-4c65-90e3-ca563267e8b9'
        $Users = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users?$select=id,userPrincipalName,userType,accountEnabled,assignedPlans&$top=999' -tenantid $TenantFilter -AsApp $true

        $Failures = [System.Collections.Generic.List[string]]::new()
        $Policies = foreach ($User in $Users) {
            if ($User.userType -ne 'Member' -or $User.accountEnabled -ne $true -or -not $User.id -or -not $User.userPrincipalName) { continue }
            if (-not @($User.assignedPlans).Where({ $_.capabilityStatus -eq 'Enabled' -and $_.servicePlanId -eq $PlannerPlanId }, 'First')) { continue }

            $Upn = "$($User.userPrincipalName)"
            $Uri = "https://tasks.office.com/taskAPI/tenantAdminSettings/UserPolicy('$($Upn -replace "'", "''")')"
            try {
                $Policy = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -scope 'https://tasks.office.com/.default' -AsApp $true
                [PSCustomObject]@{ id = "$($User.id)"; userPrincipalName = $Upn; policyExists = $true; blockDeleteTasksNotCreatedBySelf = ($Policy.blockDeleteTasksNotCreatedBySelf -eq $true) }
            } catch {
                $Message = "$($_.Exception.Message)"
                if ($Message -match '403|404|Access is denied|Not Found|Forbidden') {
                    [PSCustomObject]@{ id = "$($User.id)"; userPrincipalName = $Upn; policyExists = $false; blockDeleteTasksNotCreatedBySelf = $false }
                } else {
                    $Failures.Add("${Upn}: $Message")
                }
            }
        }

        if ($Failures.Count -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Planner user policies: could not read $($Failures.Count) of $($Failures.Count + @($Policies).Count) users. $($Failures.GetRange(0, [Math]::Min(10, $Failures.Count)) -join ' | ')" -sev Warning
            # An empty set would grade the whole tenant compliant; keep the previous cache instead.
            if (@($Policies).Count -eq 0) { throw "every Planner user policy read failed: $($Failures[0])" }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'PlannerUserPolicies' -Data @($Policies) -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $(@($Policies).Count) Planner user policies" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Planner user policies: $($_.Exception.Message)" -sev Error
    }
}
