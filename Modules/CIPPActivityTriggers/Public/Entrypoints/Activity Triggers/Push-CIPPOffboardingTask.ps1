function Push-CIPPOffboardingTask {
    <#
    .SYNOPSIS
        Generic wrapper to execute individual offboarding task cmdlets

    .DESCRIPTION
        Executes the specified cmdlet with the provided parameters as part of user offboarding and,
        when the job tracks live progress, reports the outcome to the step it was stamped with

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Cmdlet = $Item.Cmdlet
    $Parameters = $Item.Parameters | ConvertTo-Json -Depth 5 | ConvertFrom-Json -AsHashtable
    # Live progress (optional): the job stamps each task with the status row and step it reports to
    $Step = if ($Item.DeploymentId) { @{ JobId = $Item.DeploymentId; Name = $Item.DeploymentName; StepIndex = [int]$Item.StepIndex } }

    try {
        Write-Information "Executing offboarding cmdlet: $Cmdlet"
        if ($Step) { Set-CIPPAsyncDeploymentStep @Step -StepStatus 'running' -Message 'In progress' }

        # Check if cmdlet exists
        $CmdletInfo = Get-Command -Name $Cmdlet -Module CIPPCore -ErrorAction SilentlyContinue
        if (-not $CmdletInfo) {
            throw "Cmdlet $Cmdlet does not exist"
        }

        # Execute the cmdlet with splatting
        $Result = & $Cmdlet @Parameters

        Write-Information "Completed $Cmdlet successfully"
        if ($Step) {
            # Most cmdlets report per-item problems as returned 'Error: ...' lines rather than throwing
            # (group removal, for one), so a returned error line counts as a failed step.
            $Lines = @($Result | ForEach-Object { [string]($_.resultText ?? $_) })
            $StepStatus = if (@($Lines | Where-Object { $_ -match '^\s*(Error|Failed)\b' }).Count -gt 0) { 'failed' } else { 'succeeded' }
            Set-CIPPAsyncDeploymentStep @Step -StepStatus $StepStatus -Message ($Lines -join "`n")
        }
        return $Result

    } catch {
        $ErrorMsg = "Failed to execute $Cmdlet : $($_.Exception.Message)"
        Write-Information $ErrorMsg
        if ($Step) { Set-CIPPAsyncDeploymentStep @Step -StepStatus 'failed' -Message $ErrorMsg }
        return $ErrorMsg
    }
}
