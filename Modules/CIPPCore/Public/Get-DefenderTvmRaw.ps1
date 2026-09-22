function Get-DefenderTvmRaw {
    <#
    .SYNOPSIS
        Stream Defender TVM software-vulnerabilities-per-device via the export (gzip files) API.
    .DESCRIPTION
        Uses the "via files" export only: cached SAS URLs (Get-DefenderTvmExportUrls) to GZIP
        multiline-JSON files, stream-decompressed one record at a time. Peak memory is ~one record
        plus the consumer's aggregate, independent of tenant size. Pass -Stream to emit to the
        pipeline (the fold consumers do); without it, records are buffered into a list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantId,
        [switch]$Stream
    )

    try {
        $Files = Get-DefenderTvmExportUrls -TenantId $TenantId
        if (-not $Files -or $Files.Count -eq 0) {
            Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message 'No export files returned from Defender TVM' -Sev 'Warning'
            return
        }

        $Buffer = if ($Stream) { $null } else { [System.Collections.Generic.List[object]]::new() }
        $Client = [System.Net.Http.HttpClient]::new()
        $Client.Timeout = [TimeSpan]::FromMinutes(30)
        try {
            foreach ($Url in $Files) {
                $NetStream = $Client.GetStreamAsync($Url).GetAwaiter().GetResult()
                $Gzip = [System.IO.Compression.GZipStream]::new($NetStream, [System.IO.Compression.CompressionMode]::Decompress)
                $Reader = [System.IO.StreamReader]::new($Gzip)
                try {
                    while ($null -ne ($Line = $Reader.ReadLine())) {
                        if (-not $Line) { continue }
                        $Record = $Line | ConvertFrom-Json
                        if ($Stream) { $Record } else { $Buffer.Add($Record) }
                    }
                } finally {
                    $Reader.Dispose(); $Gzip.Dispose(); $NetStream.Dispose()
                }
            }
        } finally {
            $Client.Dispose()
        }

        if (-not $Stream) { return $Buffer }
    } catch {
        $Sev = if (Test-CIPPCacheCapabilityError -Message $_.Exception.Message) { 'Debug' } else { 'Error' }
        Write-LogMessage -API 'DefenderTVM' -tenant $TenantId -message "Error: $($_.Exception.Message)" -Sev $Sev
        throw
    }
}
