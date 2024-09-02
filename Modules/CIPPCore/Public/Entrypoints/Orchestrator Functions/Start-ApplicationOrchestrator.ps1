function Start-ApplicationOrchestrator {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param()

    Write-LogMessage -API 'IntuneApps' -message 'Started uploading applications to tenants' -sev Info

    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'ApplicationOrchestrator'
        SkipLog          = $true
        QueueFunction    = @{
            FunctionName = 'GetApplicationQueue'
        }
    }

    if ($PSCmdlet.ShouldProcess('Upload Applications')) {
        return Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
    }
}
