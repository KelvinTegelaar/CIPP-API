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
        
        Write-LogMessage -API 'NinjaOne' -message "Initial upload response received" -Sev 'Info'
        
        # Log the initial response
        if ($resp) {
            Write-LogMessage -API 'NinjaOne' -message "Initial upload response: $($resp | ConvertTo-Json -Compress)" -Sev 'Debug'
        } else {
            Write-LogMessage -API 'NinjaOne' -message "Initial upload response was null or empty" -Sev 'Warning'
        }
        
        # Extract scan group ID from URI for status checking
        if ($Uri -match '/scan-groups/(\d+)/upload') {
            $ScanGroupId = $Matches[1]
            Write-LogMessage -API 'NinjaOne' -message "Extracted scan group ID: $ScanGroupId" -Sev 'Debug'
            
            # Poll for completion status
            $StatusUri = $Uri -replace '/upload$', ''  # Remove /upload to get base scan group URI
            $MaxAttempts = 30  # 30 attempts = ~5 minutes max wait
            $AttemptCount = 0
            $Status = $null
            
            Write-LogMessage -API 'NinjaOne' -message "Starting status poll (max $MaxAttempts attempts)" -Sev 'Info'
            
            while ($AttemptCount -lt $MaxAttempts) {
                Start-Sleep -Seconds 10
                $AttemptCount++
                
                try {
                    $ScanGroupStatus = Invoke-RestMethod -Method GET -Uri $StatusUri -Headers $Headers -TimeoutSec 30
                    $Status = $ScanGroupStatus.status  # lowercase 'status' per API docs
                    
                    # Log full response for debugging
                    Write-LogMessage -API 'NinjaOne' -message "Status poll attempt $AttemptCount/$MaxAttempts - Full response: $($ScanGroupStatus | ConvertTo-Json -Compress)" -Sev 'Debug'
                    Write-LogMessage -API 'NinjaOne' -message "Status poll attempt $AttemptCount/$MaxAttempts - Status: $Status" -Sev 'Info'
                    
                    if ($Status -eq 'COMPLETE') {  # All caps per API docs
                        Write-LogMessage -API 'NinjaOne' -message "Upload processing completed successfully" -Sev 'Info'
                        
                        # Log records processed
                        if ($ScanGroupStatus.recordsProcessed) {
                            Write-LogMessage -API 'NinjaOne' -message "NinjaOne processed $($ScanGroupStatus.recordsProcessed) records" -Sev 'Info'
                        }
                        
                        # Log what we're returning
                        Write-LogMessage -API 'NinjaOne' -message "Returning final status response to caller: $($ScanGroupStatus | ConvertTo-Json -Compress)" -Sev 'Debug'
                        
                        # Return the final status response instead of initial upload response
                        return $ScanGroupStatus
                    }
                    elseif ($Status -eq 'FAILED') {  # Assuming all caps for consistency
                        Write-LogMessage -API 'NinjaOne' -message "Upload FAILED - Full response: $($ScanGroupStatus | ConvertTo-Json -Compress)" -Sev 'Error'
                        throw "NinjaOne upload processing failed. Status: FAILED. Details: $($ScanGroupStatus | ConvertTo-Json -Compress)"
                    }
                    elseif ($Status -ne 'IN_PROGRESS') {
                        # Unknown status - log it
                        Write-LogMessage -API 'NinjaOne' -message "Unknown status encountered: $Status - Full response: $($ScanGroupStatus | ConvertTo-Json -Compress)" -Sev 'Warning'
                    }
                    # Continue polling for IN_PROGRESS or other intermediate states
                }
                catch {
                    $ErrorDetails = $_.Exception.Message
                    if ($_.Exception.Response) {
                        try {
                            $ErrorStream = $_.Exception.Response.GetResponseStream()
                            $Reader = New-Object System.IO.StreamReader($ErrorStream)
                            $ErrorBody = $Reader.ReadToEnd()
                            $ErrorDetails = "$ErrorDetails - Response body: $ErrorBody"
                        }
                        catch {
                            # Couldn't read error body, just use message
                        }
                    }
                    
                    Write-LogMessage -API 'NinjaOne' -message "Status check failed (attempt $AttemptCount): $ErrorDetails" -Sev 'Warning'
                    
                    # If we're failing consistently, might be a real error
                    if ($AttemptCount -ge 5) {
                        Write-LogMessage -API 'NinjaOne' -message "Status check has failed $AttemptCount times. This may indicate a real problem." -Sev 'Error'
                    }
                    
                    # Continue polling - might be a transient error
                }
            }
            
            # Max attempts reached
            Write-LogMessage -API 'NinjaOne' -message "WARNING: Status polling timed out after $MaxAttempts attempts. Last status: $Status. Upload may still succeed - check NinjaOne UI." -Sev 'Warning'
            
            # Return response but note the timeout
            if ($resp) {
                $resp | Add-Member -NotePropertyName 'PollingTimedOut' -NotePropertyValue $true -Force
            }
        }
        else {
            Write-LogMessage -API 'NinjaOne' -message "Could not extract scan group ID from URI for status polling" -Sev 'Warning'
        }
        
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
