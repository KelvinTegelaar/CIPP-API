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
    $ExtensionConfig = (Get-AzDataTableEntity @Table).config
    if ($ExtensionConfig -and (Test-Json -Json $ExtensionConfig)) {
        $Configuration = ($ExtensionConfig | ConvertFrom-Json)
    } else {
        $Configuration = @{}
    }

    Write-Host 'Started Scheduler for Extensions'

    # NinjaOne Extension
    if ($Configuration.NinjaOne.Enabled -eq $true) {
        if ($PSCmdlet.ShouldProcess('Invoke-NinjaOneExtensionScheduler')) {
            Invoke-NinjaOneExtensionScheduler
        }
    }

    if ($Configuration.HaloPSA.Enabled -eq $true) {
        if ($PSCmdlet.ShouldProcess('Invoke-HaloAutoMap')) {
            try {
                Invoke-HaloAutoMap -CIPPMapping (Get-CIPPTable -TableName CippMapping) | Out-Null
            } catch {
                Write-LogMessage -API 'HaloAutoMap' -message "HaloPSA background AutoMap failed: $($_.Exception.Message)" -Sev 'Error'
            }
        }
    }
}
