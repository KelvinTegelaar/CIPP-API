function Start-ExtensionOrchestrator {
    <#
    .SYNOPSIS
        Start the Extension Orchestrator
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Table = Get-CIPPTable -TableName Extensionsconfig

    $Configuration = ((Get-AzDataTableEntity @Table).config | ConvertFrom-Json)

    Write-Host 'Started Scheduler for Extensions'

    # NinjaOne Extension
    if ($Configuration.NinjaOne.Enabled -eq $true) {
        if ($PSCmdlet.ShouldProcess('Invoke-NinjaOneExtensionScheduler')) {
            Invoke-NinjaOneExtensionScheduler
        }
    }
}
