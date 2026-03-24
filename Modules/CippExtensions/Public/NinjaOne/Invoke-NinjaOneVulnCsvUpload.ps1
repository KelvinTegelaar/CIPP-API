function Invoke-NinjaOneVulnCsvUpload {
    <#
    .SYNOPSIS
        Upload CVE CSV to NinjaOne vulnerability scan group via multipart POST.
    .PARAMETER Uri
        Full NinjaOne API upload URI including scan group ID.
    .PARAMETER CsvBytes
        UTF-8 encoded CSV payload as a byte array.
    .PARAMETER Headers
        Hashtable of HTTP headers including Authorization bearer token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][byte[]]$CsvBytes,
        [Parameter(Mandatory)][hashtable]$Headers
    )

    $boundary = [System.Guid]::NewGuid().ToString()
    $LF       = "`r`n"

    $bodyLines  = @()
    $bodyLines += "--$boundary"
    $bodyLines += 'Content-Disposition: form-data; name="csv"; filename="cve.csv"'
    $bodyLines += 'Content-Type: text/csv'
    $bodyLines += ''

    $headerText  = $bodyLines -join $LF
    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerText + $LF)

    $trailerText  = "$LF--$boundary--$LF"
    $trailerBytes = [System.Text.Encoding]::UTF8.GetBytes($trailerText)

    $mem = New-Object System.IO.MemoryStream
    try {
        $mem.Write($headerBytes, 0, $headerBytes.Length)
        $mem.Write($CsvBytes,    0, $CsvBytes.Length)
        $mem.Write($trailerBytes, 0, $trailerBytes.Length)
        $mem.Position = 0

        Write-LogMessage -API 'NinjaOne' -message "Uploading CVE CSV to $Uri ($($CsvBytes.Length) bytes)" -Sev 'Info'

        # Debug: log a preview of the multipart body — Debug severity only
        $debugBody = [System.Text.Encoding]::UTF8.GetString($mem.ToArray())
        Write-LogMessage -API 'NinjaOne' -message "Multipart preview (first 300 chars): $($debugBody.Substring(0, [Math]::Min(300, $debugBody.Length)))" -Sev 'Debug'
        $mem.Position = 0

        $resp = Invoke-RestMethod -Method POST -Uri $Uri `
            -Headers $Headers `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $mem

        Write-LogMessage -API 'NinjaOne' -message "Upload successful" -Sev 'Info'
        return $resp
    }
    catch {
        Write-LogMessage -API 'NinjaOne' -message "CSV upload failed: $($_.Exception.Message)" -Sev 'Error'
        throw
    }
    finally {
        if ($mem) { $mem.Dispose() }
    }
}
