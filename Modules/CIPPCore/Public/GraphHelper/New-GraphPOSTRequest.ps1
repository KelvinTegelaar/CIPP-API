
function New-GraphPOSTRequest ($uri, $tenantid, $body, $type, $scope, $AsApp, $NoAuthCheck, $skipTokenCache, $AddedHeaders, $contentType, $IgnoreErrors = $false, $returnHeaders = $false) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        if ($AddedHeaders) {
            foreach ($header in $AddedHeaders.GetEnumerator()) {
                $headers.Add($header.Key, $header.Value)
            }
        }

        if (!$type) {
            $type = 'POST'
        }

        Write-Information "$($type.ToUpper()) [ $uri ] | tenant: $tenantid"

        if (!$contentType) {
            $contentType = 'application/json; charset=utf-8'
        }
        try {
            $body = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $body -EscapeForJson
            $ReturnedData = (Invoke-RestMethod -Uri $($uri) -Method $TYPE -Body $body -Headers $headers -ContentType $contentType -SkipHttpErrorCheck:$IgnoreErrors -ResponseHeadersVariable responseHeaders)
        } catch {
            $Message = if ($_.ErrorDetails.Message) {
                Get-NormalizedError -Message $_.ErrorDetails.Message
            } else {
                $_.Exception.message
            }

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
