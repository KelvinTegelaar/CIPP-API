
function New-GraphPOSTRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param(
        $uri,
        $tenantid,
        $body,
        $type = 'POST',
        $scope,
        $AsApp,
        $NoAuthCheck,
        $skipTokenCache,
        $AddedHeaders,
        $contentType,
        $IgnoreErrors = $false,
        $returnHeaders = $false,
        $maxRetries = 1
    )

    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        if ($AddedHeaders) {
            foreach ($header in $AddedHeaders.GetEnumerator()) {
                $headers.Add($header.Key, $header.Value)
            }
        }

        if (!$contentType) {
            $contentType = 'application/json; charset=utf-8'
        }

        $body = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $body -EscapeForJson

        $x = 0
        do {
            try {
                Write-Information "$($type.ToUpper()) [ $uri ] | tenant: $tenantid | attempt: $($x + 1) of $maxRetries"
                $success = $false
                $ReturnedData = (Invoke-RestMethod -Uri $($uri) -Method $TYPE -Body $body -Headers $headers -ContentType $contentType -SkipHttpErrorCheck:$IgnoreErrors -ResponseHeadersVariable responseHeaders)
                $success = $true
            } catch {

                $Message = if ($_.ErrorDetails.Message) {
                    Get-NormalizedError -Message $_.ErrorDetails.Message
                } else {
                    $_.Exception.message
                }
                $x++
                Start-Sleep -Seconds (2 * $x)
            }
        } while (($x -lt $maxRetries) -and ($success -eq $false))

        if ($success -eq $false) {
            throw $Message
        }

        if ($returnHeaders) {
            return $responseHeaders
        } else {
            return $ReturnedData
        }
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
