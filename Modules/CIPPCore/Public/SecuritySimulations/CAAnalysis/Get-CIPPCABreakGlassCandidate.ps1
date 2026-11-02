function Get-CIPPCABreakGlassCandidate {
    <#
    .SYNOPSIS
        Identifies the most likely break-glass (emergency access) account or group from policy exclusion
        patterns.
    .DESCRIPTION
        Walks every enabled or report-only policy that targets All users and counts how often each excluded
        user or group appears.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Policies
    )

    $Candidates = [ordered]@{}
    $ActivePolicies = @($Policies | Where-Object { $_.state -in @('enabled', 'enabledForReportingButNotEnforced') })

    foreach ($Policy in $ActivePolicies) {
        if (-not (@($Policy.conditions.users.includeUsers) -contains 'All')) { continue }

        foreach ($UserId in @($Policy.conditions.users.excludeUsers)) {
            if ($UserId -eq 'GuestsOrExternalUsers') { continue }
            if (-not $Candidates.Contains($UserId)) {
                $Candidates[$UserId] = [PSCustomObject]@{ Id = $UserId; Hits = 0; Policies = [System.Collections.Generic.List[string]]::new(); Type = 'user' }
            }
            $Candidates[$UserId].Hits++
            $Candidates[$UserId].Policies.Add("$($Policy.displayName)")
        }

        foreach ($GroupId in @($Policy.conditions.users.excludeGroups)) {
            if (-not $Candidates.Contains($GroupId)) {
                $Candidates[$GroupId] = [PSCustomObject]@{ Id = $GroupId; Hits = 0; Policies = [System.Collections.Generic.List[string]]::new(); Type = 'group' }
            }
            $Candidates[$GroupId].Hits++
            $Candidates[$GroupId].Policies.Add("$($Policy.displayName)")
        }
    }

    $Primary = $null
    foreach ($Entry in $Candidates.Values) {
        if ($null -eq $Primary -or $Entry.Hits -gt $Primary.Hits) { $Primary = $Entry }
    }
    if ($null -eq $Primary) { return $null }

    [PSCustomObject]@{
        id          = "$($Primary.Id)"
        count       = [int]$Primary.Hits
        policies    = [string[]]@($Primary.Policies)
        type        = $Primary.Type
        displayName = $null
    }
}
