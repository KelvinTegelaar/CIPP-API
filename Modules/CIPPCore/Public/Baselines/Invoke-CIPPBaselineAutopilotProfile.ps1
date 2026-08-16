function Invoke-CIPPBaselineAutopilotProfile {
    <#
    .SYNOPSIS
        AutopilotProfile executor: deploys or updates the named Autopilot profile.
    .DESCRIPTION
        The classic's write, verbatim: one Set-CIPPDefaultAPDeploymentProfile call carrying
        the derived deployment mode and user type. HideChangeAccount is always true in the
        helper call - the classic hardcoded it despite exposing a switch.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $UserType = $(if ($Remediate.notLocalAdmin -eq $true) { 'standard' } else { 'administrator' })
    $SelfDeploying = $Remediate.selfDeployingMode -eq $true
    $DeploymentMode = $(if ($SelfDeploying) { 'shared' } else { 'singleUser' })
    $AllowWhiteGlove = $(if ($SelfDeploying) { $false } else { [bool]$Remediate.allowWhiteGlove })

    $Parameters = @{
        TenantFilter       = $TenantFilter
        DisplayName        = "$($Remediate.displayName)"
        Description        = "$($Remediate.description)"
        UserType           = $UserType
        DeploymentMode     = $DeploymentMode
        AssignTo           = ($Remediate.assignToAllDevices -eq $true)
        DeviceNameTemplate = "$($Remediate.deviceNameTemplate)"
        AllowWhiteGlove    = $AllowWhiteGlove
        CollectHash        = [bool]$Remediate.collectHash
        HideChangeAccount  = $true
        HidePrivacy        = [bool]$Remediate.hidePrivacy
        HideTerms          = [bool]$Remediate.hideTerms
        AutoKeyboard       = [bool]$Remediate.autoKeyboard
        Language           = "$($Remediate.languages.value ?? $Remediate.languages)"
    }
    Set-CIPPDefaultAPDeploymentProfile @Parameters
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed the Autopilot profile '$($Remediate.displayName)'." -Sev 'Info'
}
