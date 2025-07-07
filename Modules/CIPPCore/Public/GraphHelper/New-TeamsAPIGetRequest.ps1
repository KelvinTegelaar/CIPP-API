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
                # Use .NET HttpClient directly to bypass PowerShell HTTP handling issues
                $httpClient = New-Object System.Net.Http.HttpClient
                $httpClient.DefaultRequestHeaders.Add('Authorization', $token.Authorization)
                $httpClient.DefaultRequestHeaders.Add('x-ms-client-request-id', [guid]::NewGuid().ToString())
                $httpClient.DefaultRequestHeaders.Add('x-ms-client-session-id', [guid]::NewGuid().ToString())
                $httpClient.DefaultRequestHeaders.Add('x-ms-correlation-id', [guid]::NewGuid().ToString())
                $httpClient.DefaultRequestHeaders.Add('X-Requested-With', 'XMLHttpRequest')
                $httpClient.DefaultRequestHeaders.Add('x-ms-tnm-applicationid', '045268c0-445e-4ac1-9157-d58f67b167d9')
                $httpClient.DefaultRequestHeaders.Add('Accept', 'application/json')
                $httpClient.DefaultRequestHeaders.Add('Accept-Encoding', 'identity')
                $httpClient.DefaultRequestHeaders.Add('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36')

                # Disable automatic decompression to prevent .NET compression issues
                $handler = New-Object System.Net.Http.HttpClientHandler
                $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::None
                $httpClient.Dispose()
                $httpClient = New-Object System.Net.Http.HttpClient($handler)

                # Re-add headers after creating new client with handler
                $httpClient.DefaultRequestHeaders.Add('Authorization', $token.Authorization)
                $httpClient.DefaultRequestHeaders.Add('x-ms-client-request-id', [guid]::NewGuid().ToString())
                $httpClient.DefaultRequestHeaders.Add('x-ms-client-session-id', [guid]::NewGuid().ToString())
                $httpClient.DefaultRequestHeaders.Add('x-ms-correlation-id', [guid]::NewGuid().ToString())
                $httpClient.DefaultRequestHeaders.Add('X-Requested-With', 'XMLHttpRequest')
                $httpClient.DefaultRequestHeaders.Add('x-ms-tnm-applicationid', '045268c0-445e-4ac1-9157-d58f67b167d9')
                $httpClient.DefaultRequestHeaders.Add('Accept', 'application/json')
                $httpClient.DefaultRequestHeaders.Add('Accept-Encoding', 'identity')
                $httpClient.DefaultRequestHeaders.Add('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36')

                $response = $httpClient.GetAsync($NextURL).Result
                $contentString = $response.Content.ReadAsStringAsync().Result

                # Clean up
                $httpClient.Dispose() | Out-Null
                $handler.Dispose() | Out-Null

                # Parse JSON
                $Data = $contentString | ConvertFrom-Json
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
