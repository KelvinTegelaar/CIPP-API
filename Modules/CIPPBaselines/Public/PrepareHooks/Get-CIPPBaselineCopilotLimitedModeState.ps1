function Get-CIPPBaselineCopilotLimitedModeState {
    <#
    .SYNOPSIS
        Prepare hook for CopilotLimitedMode: is Copilot limited mode scoped as configured.
    .DESCRIPTION
        Enabled grades both the flag and that the scoping group matches the configured name
        (resolved from the Groups cache with the classic's startsWith-first-match rule).
        Disabled grades the flag alone. An enabled posture whose group cannot be resolved
        reports No Data - the classic refused to remediate that state, and there is nothing
        truthful to grade the tenant's group against.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $State = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'CopilotAdminSettings') | Select-Object -First 1
    if (-not $State) { return @{ Current = $null } }

    $Enabled = [bool]($Item.Variables.LimitedModeEnabled -eq $true)
    if (-not $Enabled) {
        return @{
            Expected = [PSCustomObject]@{ limitedModeEnabled = $false }
            Current  = [PSCustomObject]@{ limitedModeEnabled = [bool]$State.isEnabledForGroup }
        }
    }

    $GroupName = "$($Item.Variables.GroupName)"
    if ([string]::IsNullOrWhiteSpace($GroupName)) { return @{ Current = $null } }
    $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
    $Resolved = @($Groups | Where-Object { "$($_.displayName)".StartsWith($GroupName) }) | Select-Object -First 1
    if (-not $Resolved) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Copilot limited mode: the group '$GroupName' does not resolve in this tenant - nothing was compared." -Sev 'Error'
        return @{ Current = $null }
    }

    $Current = [PSCustomObject]@{
        limitedModeEnabled = [bool]$State.isEnabledForGroup
        groupCorrect       = [bool]("$($State.groupId)" -eq "$($Resolved.id)")
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'resolvedGroupId' -NotePropertyValue "$($Resolved.id)"

    @{
        Expected = [PSCustomObject]@{ limitedModeEnabled = $true; groupCorrect = $true }
        Current  = $Current
    }
}
