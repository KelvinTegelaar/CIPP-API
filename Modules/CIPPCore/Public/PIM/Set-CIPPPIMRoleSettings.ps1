function Set-CIPPPIMRoleSettings {
    <#
    .SYNOPSIS
        Applies desired PIM policy rules to a role's management policy, one PATCH per differing rule.

    .DESCRIPTION
        Compares first (Compare-CIPPPIMRoleSettings) and only writes the rules that differ, so a
        compliant tenant sees no writes and the logbook records exactly what changed. Callers must
        have validated the desired settings against the secure floor; this function does not
        weaken or strengthen anything on its own.

    .PARAMETER PolicyId
        The unifiedRoleManagementPolicy id (from policies/roleManagementPolicyAssignments.policyId).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$PolicyId,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$DesiredRules,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        $CurrentRules,

        [string]$RoleName = '',

        $Headers,

        [string]$APIName = 'Standards'
    )

    $Differences = Compare-CIPPPIMRoleSettings -DesiredRules $DesiredRules -CurrentRules $CurrentRules -RoleName $RoleName
    $Results = [System.Collections.Generic.List[object]]::new()

    if ($Differences.Count -eq 0) {
        return @($Results)
    }

    $RuleIds = @($Differences.Rule | Sort-Object -Unique)
    foreach ($RuleId in $RuleIds) {
        $Rule = $DesiredRules | Where-Object { $_['id'] -eq $RuleId } | Select-Object -First 1
        if (-not $Rule) { continue }

        $Changed = @($Differences | Where-Object { $_.Rule -eq $RuleId } | ForEach-Object { "$($_.Property): $($_.Current) -> $($_.Expected)" }) -join '; '
        $Uri = "https://graph.microsoft.com/beta/policies/roleManagementPolicies/$PolicyId/rules/$RuleId"
        $Body = ConvertTo-Json -InputObject $Rule -Depth 20 -Compress

        if (-not $PSCmdlet.ShouldProcess("$RoleName ($PolicyId) rule $RuleId", 'PATCH')) { continue }

        try {
            $null = New-GraphPOSTRequest -type PATCH -uri $Uri -body $Body -tenantid $TenantFilter -AsApp $true
            $Message = "Updated PIM role setting $RuleId for $RoleName`: $Changed"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info' -LogData @{ Role = $RoleName; PolicyId = $PolicyId; Rule = $RuleId; Changes = $Changed }
            $Results.Add([PSCustomObject]@{ Rule = $RuleId; Success = $true; Message = $Message })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to update PIM role setting $RuleId for $RoleName`: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
            $Results.Add([PSCustomObject]@{ Rule = $RuleId; Success = $false; Message = $Message })
        }
    }

    return @($Results)
}
