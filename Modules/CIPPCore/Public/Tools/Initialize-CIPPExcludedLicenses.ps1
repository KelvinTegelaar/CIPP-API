function Initialize-CIPPExcludedLicenses {
    <#
    .SYNOPSIS
        Initialize the ExcludedLicenses table from the default config file

    .DESCRIPTION
        Reads the ExcludeSkuList.JSON config file and adds missing licenses to the ExcludedLicenses Azure Table.
        Only adds licenses that don't already exist, preserving any manually added entries.
        Use -Force to clear the table and reset to defaults.

    .FUNCTIONALITY
        Internal

    .PARAMETER Force
        If specified, clears existing entries before initializing from config

    .PARAMETER Headers
        Request headers for logging

    .PARAMETER APIName
        API name for logging purposes

    .EXAMPLE
        Initialize-CIPPExcludedLicenses -Headers $Request.Headers -APIName 'ExecExcludeLicenses'
    #>
    [CmdletBinding()]
    param(
        [switch]$Force,
        $Headers,
        $APIName = 'Initialize-CIPPExcludedLicenses'
    )

    try {
        $Table = Get-CIPPTable -TableName ExcludedLicenses

        # If Force is specified, clear existing entries first
        if ($Force) {
            $ExistingRows = Get-CIPPAzDataTableEntity @Table
            foreach ($Row in $ExistingRows) {
                Remove-AzDataTableEntity -Force @Table -Entity $Row
            }
            Write-LogMessage -API $APIName -headers $Headers -message 'Cleared existing excluded licenses' -Sev 'Info'
        }

        # Get the config file path
        $CIPPCoreModuleRoot = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
        $CIPPRoot = (Get-Item $CIPPCoreModuleRoot).Parent.Parent
        $ConfigPath = Join-Path $CIPPRoot 'Config\ExcludeSkuList.JSON'

        if (-not (Test-Path $ConfigPath)) {
            throw "Config file not found: $ConfigPath"
        }

        $TableBaseData = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json -AsHashtable -Depth 10

        # Get existing GUIDs to avoid overwriting manually added entries
        $ExistingRows = Get-CIPPAzDataTableEntity @Table
        $ExistingGUIDs = @($ExistingRows | ForEach-Object { $_.GUID })

        $AddedCount = 0
        $SkippedCount = 0
        foreach ($Row in $TableBaseData) {
            if ($Row.GUID -in $ExistingGUIDs) {
                $SkippedCount++
                continue
            }
            $Row.PartitionKey = 'License'
            $Row.RowKey = $Row.GUID
            Add-CIPPAzDataTableEntity @Table -Entity ([pscustomobject]$Row) -Force | Out-Null
            $AddedCount++
        }

        if ($Force) {
            $Message = "Successfully performed full reset. Restored $AddedCount default licenses from config file"
        } else {
            $Message = "Successfully added $AddedCount missing licenses from config file ($SkippedCount already existed)"
        }
        Write-LogMessage -API $APIName -headers $Headers -message $Message -Sev 'Info'

        return @{
            Success      = $true
            Message      = $Message
            AddedCount   = $AddedCount
            SkippedCount = $SkippedCount
            FullReset    = [bool]$Force
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to initialize excluded licenses. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}
