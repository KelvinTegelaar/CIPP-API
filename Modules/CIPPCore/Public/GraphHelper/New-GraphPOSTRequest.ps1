
function New-GraphPOSTRequest ($uri, $tenantid, $body, $type, $scope, $AsApp, $NoAuthCheck, $skipTokenCache, $AddedHeaders) {
    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        if ($AddedHeaders) {
            foreach ($header in $AddedHeaders.getenumerator()) {
                $headers.Add($header.Key, $header.Value)
            }
        }
        Write-Verbose "Using $($uri) as url"
        if (!$type) {
            $type = 'POST'
        }

        try {
            $ReturnedData = (Invoke-RestMethod -Uri $($uri) -Method $TYPE -Body $body -Headers $headers -ContentType 'application/json; charset=utf-8')
        } catch {
            $ErrorMess = $($_.Exception.Message)
            $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
            if (!$Message) { $Message = $ErrorMess }
            throw $Message
        }
        return $ReturnedData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}