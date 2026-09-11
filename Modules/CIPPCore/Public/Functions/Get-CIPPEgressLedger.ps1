function Get-CIPPEgressLedger {
    <#
    .SYNOPSIS
        Reads today's API egress ledger written by Craft.
    .DESCRIPTION
        Craft flushes egress-ledger.json ({"DateUtc":"yyyy-MM-dd","Bytes":<long>}) to its log
        directory every 60s, only when egress accounting is enabled and at least one API-client
        response has been served today. A missing file, a different UTC day, or unparsable JSON
        all mean "no data for today" rather than an error, so this never throws.
    .FUNCTIONALITY
        Internal
    .EXAMPLE
        Get-CIPPEgressLedger -LogDirectory ([Craft.Services.LogBridge]::GetLogDirectory())
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,

        [DateTime]$Now = [DateTime]::UtcNow
    )

    $Path = Join-Path -Path $LogDirectory -ChildPath 'egress-ledger.json'
    if (-not (Test-Path -Path $Path -PathType Leaf)) { return $null }

    try {
        $Ledger = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return $null
    }

    if (-not $Ledger.DateUtc -or $Ledger.DateUtc -ne $Now.ToString('yyyy-MM-dd')) { return $null }

    try {
        $Bytes = [long]$Ledger.Bytes
    } catch {
        return $null
    }

    return [pscustomobject]@{
        DateUtc = [string]$Ledger.DateUtc
        Bytes   = $Bytes
    }
}
