function Test-CIPPManagedBaselinesEnabled {
    <#
    .SYNOPSIS
        Says whether the CyberDrain Managed Baselines integration is enabled on this instance.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $ConfigTable = Get-CippTable -tablename 'Extensionsconfig'
    $Config = $(try { (Get-CIPPAzDataTableEntity @ConfigTable).config | ConvertFrom-Json -ErrorAction Stop } catch { $null })
    $Config.CyberDrainManagedBaselines.Enabled -eq $true
}
