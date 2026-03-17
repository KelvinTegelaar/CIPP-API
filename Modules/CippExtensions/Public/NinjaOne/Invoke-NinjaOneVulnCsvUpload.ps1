function Invoke-NinjaOneVulnCsvUpload {
    <#
    .SYNOPSIS
        Upload CVE CSV to NinjaOne vulnerability scan group
    .NOTES
        Version: 3.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][byte[]]$CsvBytes,
        [Parameter(Mandatory)][hashtable]$Headers
    )
    
    Write-LogMessage -API 'NinjaOne' -message "Helper Version 3.0 - Starting upload" -Sev 'Info'
    
    $boundary = [System.Guid]::NewGuid().ToString()
    $LF = "`r`n"
    
    # Build multipart body as string first
    $bodyLines = @()
    $bodyLines += "--$boundary"
    $bodyLines += 'Content-Disposition: form-data; name="csv"; filename="cve.csv"'
    $bodyLines += 'Content-Type: text/csv'
    $bodyLines += ''
    
    $headerText = $bodyLines -join $LF
    $headerBytes = [System.Text.Encoding]::UTF8.GetBytes($headerText + $LF)
    
    $trailerText = "$LF--$boundary--$LF"
    $trailerBytes = [System.Text.Encoding]::UTF8.GetBytes($trailerText)
    
    # Combine all parts
    $mem = New-Object System.IO.MemoryStream
    try {
        $mem.Write($headerBytes, 0, $headerBytes.Length)
        $mem.Write($CsvBytes, 0, $CsvBytes.Length)
        $mem.Write($trailerBytes, 0, $trailerBytes.Length)
        $mem.Position = 0
        
        Write-LogMessage -API 'NinjaOne' -message "Uploading CVE CSV to $Uri" -Sev 'Info'
        
        # Debug multipart body
        $debugBody = [System.Text.Encoding]::UTF8.GetString($mem.ToArray())
        Write-LogMessage -API 'NinjaOne' -message "Multipart body preview (first 500 chars): $($debugBody.Substring(0, [Math]::Min(500, $debugBody.Length)))" -Sev 'Info'
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
