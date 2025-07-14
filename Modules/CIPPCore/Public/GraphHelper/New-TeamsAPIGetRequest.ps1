function New-TeamsAPIGetRequest($Uri, $tenantID, $Method = 'GET', $Resource = '48ac35b8-9aa8-4d74-927d-1f4a14a0b239', $ContentType = 'application/json') {
    <#
    .FUNCTIONALITY
    Internal
    #>

    if ((Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $token = Get-GraphToken -TenantID $tenantID -Scope "$Resource/.default"
        $NextURL = $Uri
        $ReturnedData = do {
            $handler = $null
            $httpClient = $null
            $response = $null
            try {
                # Create handler and client with compression disabled
                $handler = New-Object System.Net.Http.HttpClientHandler
                $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::None
                $httpClient = New-Object System.Net.Http.HttpClient($handler)

                # Add all required headers
                $headers = @{
                    'Authorization'          = $token.Authorization
                    'x-ms-client-request-id' = [guid]::NewGuid().ToString()
                    'x-ms-client-session-id' = [guid]::NewGuid().ToString()
                    'x-ms-correlation-id'    = [guid]::NewGuid().ToString()
                    'X-Requested-With'       = 'XMLHttpRequest'
                    'x-ms-tnm-applicationid' = '045268c0-445e-4ac1-9157-d58f67b167d9'
                    'Accept'                 = 'application/json'
                    'Accept-Encoding'        = 'identity'
                    'User-Agent'             = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36'
                }

                foreach ($header in $headers.GetEnumerator()) {
                    $httpClient.DefaultRequestHeaders.Add($header.Key, $header.Value)
                }

                $response = $httpClient.GetAsync($NextURL).Result
                $contentString = $response.Content.ReadAsStringAsync().Result

                # Parse JSON and return data
                $Data = $contentString | ConvertFrom-Json

                $Data
                if ($noPagination) { $nextURL = $null } else { $nextURL = $data.NextLink }
            } catch {
                throw "Failed to make Teams API Get Request $_"
            } finally {
                # Proper cleanup in finally block to ensure disposal even on exceptions
                if ($response) { $response.Dispose() }
                if ($httpClient) { $httpClient.Dispose() }
                if ($handler) { $handler.Dispose() }
            }
        } until ($null -eq $NextURL)
        return $ReturnedData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
