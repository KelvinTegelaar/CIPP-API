function Start-ApplicationOrchestrator {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [switch]$AllowCollision
    )

    Write-LogMessage -API 'IntuneApps' -message 'Started uploading applications to tenants' -sev Info
    Write-Information 'Started uploading applications to tenants'
    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'ApplicationOrchestrator'
        AllowCollision   = $AllowCollision.IsPresent
        SkipLog          = $true
        QueueFunction    = @{
            FunctionName = 'GetApplicationQueue'
        }
    }

    if ($PSCmdlet.ShouldProcess('Upload Applications')) {
        return Start-CIPPOrchestrator -InputObject $InputObject
    }
}
