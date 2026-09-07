function Invoke-CIPPBaselineIntuneAppTemplateDeploy {
    <#
    .SYNOPSIS
        IntuneAppTemplateDeploy executor: queues deployment of the missing template apps.
    .DESCRIPTION
        The classic's write: each missing app maps its template type to the deployment
        queue's type and hands off to New-CIPPIntuneAppDeployment. Deployment is ASYNC -
        the queue uploads apps after this run returns, so the first compare afterwards may
        briefly still report the apps missing until the uploads land. Per-app failures log
        and continue; only every app failing is an error.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $MissingApps = @($Current.missingAppObjects)
    if ($MissingApps.Count -eq 0) { return }

    $Failures = 0
    foreach ($App in $MissingApps) {
        try {
            $QueueType = switch ("$($App.AppType)") {
                'StoreApp' { 'WinGet' }
                'chocolateyApp' { 'Choco' }
                'win32ScriptApp' { 'Win32ScriptApp' }
                'mspApp' { 'MSPApp' }
                'officeApp' { 'OfficeApp' }
                default { "$($App.AppType)" }
            }
            $DeployConfig = $App.Config | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            $AppAssignTo = if ("$($DeployConfig.AssignTo)" -eq 'customGroup') { $DeployConfig.CustomGroup } else { $DeployConfig.AssignTo }
            $DeployConfig | Add-Member -NotePropertyMembers ([ordered]@{
                    type            = $QueueType
                    Applicationname = "$($App.AppName)"
                    assignTo        = $AppAssignTo
                }) -Force

            $null = New-CIPPIntuneAppDeployment -AppConfig $DeployConfig -TenantFilter $TenantFilter -APIName 'Baselines'
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Queued the Intune app '$($App.AppName)' ($($App.AppType)) from template '$($App.TemplateName)'." -Sev 'Info'
        } catch {
            $Failures++
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to queue the Intune app '$($App.AppName)' from template '$($App.TemplateName)': $($_.Exception.Message)" -Sev 'Error'
        }
    }
    if ($Failures -ge $MissingApps.Count) { throw "Every Intune app deployment failed to queue for $TenantFilter - see the log for the first error." }
}
