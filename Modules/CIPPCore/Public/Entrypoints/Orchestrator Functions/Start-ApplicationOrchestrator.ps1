function Start-ApplicationOrchestrator {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param()

    Write-LogMessage -API 'IntuneApps' -message 'Started uploading applications to tenants' -sev Info
    Write-Information 'Started uploading applications to tenants'
    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'ApplicationOrchestrator'
        SkipLog          = $true
        QueueFunction    = @{
            FunctionName = 'GetApplicationQueue'
        }
    }

    if ($PSCmdlet.ShouldProcess('Upload Applications')) {
        return Start-CIPPOrchestrator -InputObject $InputObject
    }
}
