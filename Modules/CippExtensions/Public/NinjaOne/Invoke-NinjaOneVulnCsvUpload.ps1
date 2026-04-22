function Invoke-NinjaOneVulnCsvUpload {
    <#
    .SYNOPSIS
        Upload CVE CSV to NinjaOne vulnerability scan group via multipart POST,
        then poll until processing completes. Retries the full upload+poll cycle
        on transient failures or a FAILED processing status.
    .PARAMETER Uri
        Full NinjaOne API upload URI including scan group ID.
    .PARAMETER PollUri
        NinjaOne API URI for the scan group (GET) used to poll processing status.
    .PARAMETER CsvBytes
        UTF-8 encoded CSV payload as a byte array.
    .PARAMETER Headers
        Hashtable of HTTP headers including Authorization bearer token.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$PollUri,
        [Parameter(Mandatory)][byte[]]$CsvBytes,
        [Parameter(Mandatory)][hashtable]$Headers
    )

    $Boundary    = [System.Guid]::NewGuid().ToString()
    $LF          = "`r`n"
    $MaxRetries  = 5
    $RetryDelay  = 5
    $PollDelay   = 10
    $MaxPolls    = 18
    $Attempt     = 0

    $BodyLines = @(
    "--$Boundary"
    'Content-Disposition: form-data; name="csv"; filename="cve.csv"'
    'Content-Type: text/csv'
    ''
    )

    $HeaderText  = $BodyLines -join $LF
    $HeaderBytes = [System.Text.Encoding]::UTF8.GetBytes($HeaderText + $LF)

    $TrailerText  = "$LF--$Boundary--$LF"
    $TrailerBytes = [System.Text.Encoding]::UTF8.GetBytes($TrailerText)

    while ($Attempt -le $MaxRetries) {
        $Mem = [System.IO.MemoryStream]::new()
        try {
            $Mem.Write($HeaderBytes, 0, $HeaderBytes.Length)
            $Mem.Write($CsvBytes,    0, $CsvBytes.Length)
            $Mem.Write($TrailerBytes, 0, $TrailerBytes.Length)
            $Mem.Position = 0

            if ($Attempt -eq 0) {
                Write-LogMessage -API 'NinjaOne' -message "Uploading CVE CSV to NinjaOne ($($CsvBytes.Length) bytes)" -sev 'Debug'
            } else {
                Write-LogMessage -API 'NinjaOne' -message "Retrying CVE CSV upload (attempt $Attempt of $MaxRetries)" -sev 'Warning'
            }

            $Resp = Invoke-RestMethod -Method POST -Uri $Uri `
                -Headers $Headers `
                -ContentType "multipart/form-data; boundary=$Boundary" `
                -Body $Mem `
                -ErrorAction Stop

        } catch {
            $ErrorMessage = Get-CippException -Exception $_

            # Do not retry on 404 — scan group not found is a config issue, not transient
            if ($_.Exception.Response.StatusCode.value__ -eq 404) {
                Write-LogMessage -API 'NinjaOne' -message "CSV upload failed (404 — scan group not found, not retrying): $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
                throw
            }

            if ($Attempt -lt $MaxRetries) {
                Write-LogMessage -API 'NinjaOne' -message "CSV upload failed (attempt $Attempt of $MaxRetries), retrying in ${RetryDelay}s: $($ErrorMessage.NormalizedError)" -sev 'Warning' -LogData $ErrorMessage
                Start-Sleep -Seconds $RetryDelay
                $Attempt++
                continue
            } else {
                Write-LogMessage -API 'NinjaOne' -message "CSV upload failed after $MaxRetries retries: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
                throw
            }
        } finally {
            $Mem.Dispose()
        }

        # Upload accepted — poll until no longer IN_PROGRESS
        if ($Resp.status -eq 'IN_PROGRESS') {
            Write-LogMessage -API 'NinjaOne' -message "Upload accepted, polling for completion (max $($MaxPolls * $PollDelay)s)" -sev 'Debug'

            $PollCount = 0
            while ($Resp.status -eq 'IN_PROGRESS' -and $PollCount -lt $MaxPolls) {
                Start-Sleep -Seconds $PollDelay
                $PollCount++
                try {
                    $Resp = Invoke-RestMethod -Method Get -Uri $PollUri -Headers $Headers -ErrorAction Stop
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'NinjaOne' -message "Poll failed on attempt $PollCount — will retry: $($ErrorMessage.NormalizedError)" -sev 'Warning' -LogData $ErrorMessage
                }
            }

            if ($Resp.status -eq 'IN_PROGRESS') {
                # Timed out waiting — upload succeeded but processing is still running
                Write-LogMessage -API 'NinjaOne' -message "Polling timed out after $($MaxPolls * $PollDelay)s — upload accepted by NinjaOne but processing status unknown" -sev 'Warning'
                return $Resp
            }
        }

        # FAILED status — treat as retryable
        if ($Resp.status -eq 'FAILED') {
            if ($Attempt -lt $MaxRetries) {
                Write-LogMessage -API 'NinjaOne' -message "NinjaOne returned FAILED status (attempt $Attempt of $MaxRetries), retrying in ${RetryDelay}s" -sev 'Warning'
                Start-Sleep -Seconds $RetryDelay
                $Attempt++
                continue
            } else {
                Write-LogMessage -API 'NinjaOne' -message "NinjaOne returned FAILED status after $MaxRetries retries — giving up" -sev 'Error'
                return $Resp
            }
        }

        # COMPLETE or any other terminal status — return
        return $Resp
    }
}
