function Get-DefenderTvmExportUrls {
    <#
    .SYNOPSIS
        Returns the Defender TVM software-vulnerabilities export file URLs for a tenant, cached.
    .DESCRIPTION
        Calls SoftwareVulnerabilitiesExport (rate-limited to 20/hour) and caches the returned SAS blob
        URLs so any consumer in the app can reuse them until they near expiry. sasValidHours=6, so a
        cached set is reused for MaxAgeHours (default 5) before a fresh call is made.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [int]$MaxAgeHours = 5,
        [switch]$Force
    )

    $Table = Get-CIPPTable -TableName 'CacheDefenderTvmExport'

    if (-not $Force) {
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TvmExport' and RowKey eq '$TenantId'"
        if ($Row -and $Row.Cached -and ([datetime]$Row.Cached) -gt (Get-Date).ToUniversalTime().AddHours(-$MaxAgeHours)) {
            return @($Row.ExportFiles | ConvertFrom-Json)
        }
    }

    $Export = New-GraphGetRequest -tenantid $TenantId -uri 'https://api.securitycenter.microsoft.com/api/machines/SoftwareVulnerabilitiesExport?sasValidHours=6' -scope 'https://api.securitycenter.microsoft.com/.default'
    $Files = @($Export.exportFiles)

    Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey  = 'TvmExport'
        RowKey        = $TenantId
        ExportFiles   = "$($Files | ConvertTo-Json -Compress)"
        GeneratedTime = "$($Export.generatedTime)"
        Cached        = (Get-Date).ToUniversalTime().ToString('o')
    } -Force

    return $Files
}
