
function New-GraphPOSTRequest ($uri, $tenantid, $body, $type, $scope, $AsApp, $NoAuthCheck, $skipTokenCache, $AddedHeaders, $contentType) {
    <#
    .FUNCTIONALITY
    Internal
    #>
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

        if (!$contentType) {
            $contentType = 'application/json; charset=utf-8'
        }
        try {
            $ReturnedData = (Invoke-RestMethod -Uri $($uri) -Method $TYPE -Body $body -Headers $headers -ContentType $contentType)
        } catch {
            $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error
            if ($Message.innerError) { $Message = $Message.Innererror.Message } else { $Message = $Message.Message.Error }
            if ($Message -eq $null) { 
                try {
                    $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).message
                } catch {
                    $Message = $($_.Exception.Message) 
                }
            }
            throw $Message
        }
        return $ReturnedData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'

    }
}