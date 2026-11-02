function Invoke-CIPPBaselineDefenderExclusionPolicy {
    <#
    .SYNOPSIS
        DefenderExclusionPolicy executor: recreates the 'Default AV Exclusion Policy'
        settings catalog policy.
    .DESCRIPTION
        The classic's write: delete the drifted policy, then recreate through the
        Set-CIPPDefenderExclusionPolicy helper with only the configured collections.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if (-not [string]::IsNullOrWhiteSpace("$($Current.policyId)")) {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($Current.policyId)')" -tenantid $TenantFilter -type DELETE
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Deleted the drifted Defender exclusion policy for recreation.' -Sev 'Info'
    }

    $Extensions = @(("$($Remediate.excludedExtensions)" -replace ' ', '') -split ',' | Where-Object { $_ } | Sort-Object)
    $Paths = @("$($Remediate.excludedPaths)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
    $Processes = @("$($Remediate.excludedProcesses)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)

    $ExclusionSettings = @{
        AssignTo = [string]($Remediate.assignTo.value ?? $Remediate.assignTo ?? 'none')
    }
    if ($Extensions.Count -gt 0) { $ExclusionSettings['excludedExtensions'] = $Extensions }
    if ($Paths.Count -gt 0) { $ExclusionSettings['excludedPaths'] = $Paths }
    if ($Processes.Count -gt 0) { $ExclusionSettings['excludedProcesses'] = $Processes }

    $Result = Set-CIPPDefenderExclusionPolicy -TenantFilter $TenantFilter -DefenderExclusions $ExclusionSettings -APIName 'Baselines'
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$Result" -Sev 'Info'
}
