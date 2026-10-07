function Invoke-CIPPBaselineDefenderEDRPolicy {
    <#
    .SYNOPSIS
        DefenderEDRPolicy executor: recreates the 'EDR Configuration' settings catalog policy.
    .DESCRIPTION
        The classic's write: delete the drifted policy, then recreate through the
        Set-CIPPDefenderEDRPolicy helper which owns the settings tree and the assignment.
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
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Deleted the drifted Defender EDR policy for recreation.' -Sev 'Info'
    }

    $EDRSettings = @{
        Config        = [bool]$Remediate.config
        SampleSharing = [bool]$Remediate.sampleSharing
        AssignTo      = [string]($Remediate.assignTo.value ?? $Remediate.assignTo ?? 'none')
    }

    $Result = Set-CIPPDefenderEDRPolicy -TenantFilter $TenantFilter -EDR $EDRSettings -APIName 'Baselines'
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$Result" -Sev 'Info'
}
