function New-TeamsAPIGetRequest($Uri, $tenantID, $Method = 'GET', $Resource = '48ac35b8-9aa8-4d74-927d-1f4a14a0b239', $ContentType = 'application/json') {
    <#
    .FUNCTIONALITY
    Internal
    #>

    if ((Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $token = Get-GraphToken -TenantID $tenantID -Scope "$Resource/.default"

        $NextURL = $Uri
        $ReturnedData = do {
            try {
                # Use Invoke-WebRequest first to get full response control
                $Response = Invoke-WebRequest -ContentType "$ContentType;charset=UTF-8" -Uri $NextURL -Method $Method -Headers @{
                    Authorization            = $token.Authorization
                    'x-ms-client-request-id' = [guid]::NewGuid().ToString()
                    'x-ms-client-session-id' = [guid]::NewGuid().ToString()
                    'x-ms-correlation-id'    = [guid]::NewGuid()
                    'X-Requested-With'       = 'XMLHttpRequest'
                    'x-ms-tnm-applicationid' = '045268c0-445e-4ac1-9157-d58f67b167d9'
                    'Accept'                 = 'application/json'
                    'Accept-Encoding'        = 'identity'
                    'User-Agent'             = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'
                }

                # Handle response content - check for gzip encoding first
                Write-Information "Response Headers: $($Response.Headers | ConvertTo-Json -Depth 10)"

                if ($Response.Headers['Content-Encoding'] -contains 'gzip') {
                    # Get raw bytes for proper gzip decompression
                    $bytes = $Response.RawContentStream.ToArray()
                    try {
                        $memoryStream = New-Object System.IO.MemoryStream(, $bytes)
                        $gzipStream = New-Object System.IO.Compression.GzipStream($memoryStream, [System.IO.Compression.CompressionMode]::Decompress)
                        $reader = New-Object System.IO.StreamReader($gzipStream, [System.Text.Encoding]::UTF8)
                        $ContentString = $reader.ReadToEnd()
                        $reader.Close()
                        $gzipStream.Close()
                        $memoryStream.Close()
                    } catch {
                        # Fallback: try to use the content as-is if decompression fails
                        Write-Warning "Gzip decompression failed, using content as-is: $($_.Exception.Message)"
                        $ContentString = $Response.Content
                    }
                } else {
                    # Content is not gzipped, use as-is
                    $ContentString = $Response.Content
                }

                # Parse the content as JSON
                $Data = $ContentString | ConvertFrom-Json
                $Data
                if ($noPagination) { $nextURL = $null } else { $nextURL = $data.NextLink }
            } catch {
                throw "Failed to make Teams API Get Request $_"
            }
        } until ($null -eq $NextURL)
        return $ReturnedData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
