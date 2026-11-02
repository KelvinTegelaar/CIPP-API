function Invoke-CIPPBaselinePlannerBlockTaskDelete {
    <#
    .SYNOPSIS
        PlannerBlockTaskDelete executor: PUTs blockDeleteTasksNotCreatedBySelf on each offending
        user's Planner UserPolicy.
    .DESCRIPTION
        Only users the hook flagged are written, so a repeat run is cheap and needs no rerun guard.
        Per-user failures are logged and skipped; the run throws only when every write failed.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if ($null -eq $Current) { throw 'PlannerBlockTaskDelete: no Planner policy data to remediate from.' }
    $Targets = @($Current.targets | Where-Object { $_.userPrincipalName })
    if ($Targets.Count -eq 0) { return }

    $Body = @{ blockDeleteTasksNotCreatedBySelf = $true } | ConvertTo-Json -Compress
    $Failures = [System.Collections.Generic.List[string]]::new()
    foreach ($Target in $Targets) {
        $Upn = "$($Target.userPrincipalName)"
        $Uri = "https://tasks.office.com/taskAPI/tenantAdminSettings/UserPolicy('$($Upn -replace "'", "''")')"
        try {
            $null = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -scope 'https://tasks.office.com/.default' -AsApp $true -type 'PUT' -body $Body
        } catch {
            $Failures.Add("$Upn -> $(Get-NormalizedError -Message $_.Exception.Message)")
        }
    }

    if ($Failures.Count -gt 0) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "PlannerBlockTaskDelete: $($Failures.Count) of $($Targets.Count) writes failed. $($Failures -join ' | ')" -Sev 'Warning'
    }
    if ($Failures.Count -eq $Targets.Count) {
        throw "PlannerBlockTaskDelete: all $($Targets.Count) writes failed. $($Failures[0])"
    }
}
