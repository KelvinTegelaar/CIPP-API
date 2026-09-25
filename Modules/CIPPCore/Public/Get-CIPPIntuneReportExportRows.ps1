function Get-CIPPIntuneReportExportRows {
    <#
    .SYNOPSIS
        Streams the rows of a completed Intune report export (JSON format), one at a time.
    .DESCRIPTION
        Reads the export zip straight off its SAS download URL and deserialises each row of the
        "values" array as it arrives, emitting it as a Dictionary[string, object]. Peak memory is
        one row plus the compressed zip, which ZipArchive buffers to reach the central directory
        at the end of the file - never the whole decompressed JSON text or a parse tree of every
        row. Values are typed as ConvertFrom-Json would type them.
    .PARAMETER Url
        The url of a completed deviceManagement/reports/exportJobs job.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url
    )

    $Client = [System.Net.Http.HttpClient]::new()
    $Client.Timeout = [TimeSpan]::FromMinutes(30)
    try {
        $Download = $Client.GetStreamAsync($Url).GetAwaiter().GetResult()
        $Archive = [System.IO.Compression.ZipArchive]::new($Download, [System.IO.Compression.ZipArchiveMode]::Read)
        try {
            $Entry = $Archive.Entries | Where-Object { $_.Name -like '*.json' } | Select-Object -First 1
            if (-not $Entry) { throw 'No JSON entry in the report export archive' }
            $Reader = [Newtonsoft.Json.JsonTextReader]::new([System.IO.StreamReader]::new($Entry.Open()))
            try {
                # Deserialising each row straight into a dictionary skips the intermediate JObject
                # tree, roughly halving allocations against JObject.Load.
                $Serializer = [Newtonsoft.Json.JsonSerializer]::CreateDefault()
                $RowType = [System.Collections.Generic.Dictionary[string, object]]
                $InValues = $false
                while ($Reader.Read()) {
                    $Token = $Reader.TokenType
                    if (-not $InValues) {
                        $InValues = $Token -eq [Newtonsoft.Json.JsonToken]::PropertyName -and $Reader.Value -eq 'values'
                        continue
                    }
                    if ($Token -eq [Newtonsoft.Json.JsonToken]::StartObject) {
                        $Serializer.Deserialize($Reader, $RowType)
                    } elseif ($Token -eq [Newtonsoft.Json.JsonToken]::EndArray) {
                        break
                    }
                }
            } finally { $Reader.Close() }
        } finally { $Archive.Dispose() }
    } finally { $Client.Dispose() }
}
