function Invoke-CIPPBaselineAutopilotProfile {
    <#
    .SYNOPSIS
        AutopilotProfile executor: deploys or updates the named Autopilot profile.
    .DESCRIPTION
        The classic's write, verbatim: one Set-CIPPDefaultAPDeploymentProfile call carrying
        the derived deployment mode and user type. HideChangeAccount is always true in the
        helper call - the classic hardcoded it despite exposing a switch. Assignments are
        reconciled to the configured mode, except for baselines saved before the mode
        existed and when a custom group name matches nothing.
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
    $DisplayName = "$($Remediate.displayName.value ?? $Remediate.displayName)"

    # Baselines saved before the assignTo variable only render the legacy assignToAllDevices switch, which never removed assignments.
    $AssignMode = "$($Remediate.assignTo.value ?? $Remediate.assignTo)"
    $LegacyAssign = [string]::IsNullOrWhiteSpace($AssignMode)
    if ($LegacyAssign) {
        $AssignMode = $(if ($Remediate.assignToAllDevices -eq $true) { 'allDevices' } else { 'none' })
    }
    $IncludeNames = @(if ($AssignMode -eq 'customGroup' -and $Remediate.customGroup) { "$($Remediate.customGroup)".Split(',').Trim() | Where-Object { $_ } })
    $ExcludeNames = @(if ($AssignMode -ne 'none' -and $Remediate.excludeGroup) { "$($Remediate.excludeGroup)".Split(',').Trim() | Where-Object { $_ } })
    $IncludeGroupIds = @()
    $ExcludeGroupIds = @()
    if ($IncludeNames.Count -gt 0 -or $ExcludeNames.Count -gt 0) {
        $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$select=id,displayName&$top=999' -tenantid $TenantFilter
        $IncludeGroupIds = @($Groups | ForEach-Object {
                foreach ($SingleName in $IncludeNames) {
                    if ($_.displayName -like ($SingleName -replace '\[', '`[' -replace '\]', '`]')) {
                        $_.id
                    }
                }
            } | Select-Object -Unique)
        $ExcludeGroupIds = @($Groups | ForEach-Object {
                foreach ($SingleName in $ExcludeNames) {
                    if ($_.displayName -like ($SingleName -replace '\[', '`[' -replace '\]', '`]')) {
                        $_.id
                    }
                }
            } | Select-Object -Unique)
    }
    # Never strip assignments because a group name matched nothing.
    $Reconcile = -not $LegacyAssign
    if ($AssignMode -eq 'customGroup' -and $IncludeGroupIds.Count -eq 0) {
        $Reconcile = $false
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "No groups found matching '$($Remediate.customGroup)' for the Autopilot profile '$DisplayName'. Existing assignments are left unchanged." -Sev 'Warning'
    }

    $Parameters = @{
        TenantFilter       = $TenantFilter
        DisplayName        = $DisplayName
        Description        = "$($Remediate.description)"
        UserType           = $UserType
        DeploymentMode     = $DeploymentMode
        AssignTo           = ($AssignMode -eq 'allDevices')
        GroupIds           = $IncludeGroupIds
        ExcludeGroupIds    = $ExcludeGroupIds
        Reconcile          = $Reconcile
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
