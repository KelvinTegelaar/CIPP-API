function New-ExoRequest ($tenantid, $cmdlet, $cmdParams, $useSystemMailbox, $Anchor, $NoAuthCheck, $Select) {
   
    if ((Get-AuthorisedRequest -TenantID $tenantid) -or $NoAuthCheck -eq $True) {
        $token = Get-ClassicAPIToken -resource 'https://outlook.office365.com' -Tenantid $tenantid
        $tenant = (get-tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $tenantid -or $_.customerId -eq $tenantid }).customerId
        if ($cmdParams) {
            $Params = $cmdParams
        } else {
            $Params = @{}
        }
        $ExoBody = ConvertTo-Json -Depth 5 -InputObject @{
            CmdletInput = @{
                CmdletName = $cmdlet
                Parameters = $Params
            }
        }
        if (!$Anchor) {
            if ($cmdparams.Identity) { $Anchor = $cmdparams.Identity }
            if ($cmdparams.anr) { $Anchor = $cmdparams.anr }
            if ($cmdparams.User) { $Anchor = $cmdparams.User }

            if (!$Anchor -or $useSystemMailbox) {
                $OnMicrosoft = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $tenantid -NoAuthCheck $NoAuthCheck | Where-Object -Property isInitial -EQ $true).id

                $anchor = "UPN:SystemMailbox{8cc370d3-822a-4ab8-a926-bb94bd0641a9}@$($OnMicrosoft)"


            }
        }
        Write-Host "Using $Anchor"
        $Headers = @{
            Authorization             = "Bearer $($token.access_token)"
            Prefer                    = 'odata.maxpagesize = 1000'
            'parameter-based-routing' = $true
            'X-AnchorMailbox'         = $anchor

        }
        try {
            if ($Select) { $Select = "`$select=$Select" }
            $URL = "https://outlook.office365.com/adminapi/beta/$($tenant)/InvokeCommand?$Select"
            
            $ReturnedData = 
            do {
                $Return = Invoke-RestMethod $URL -Method POST -Body $ExoBody -Headers $Headers -ContentType 'application/json; charset=utf-8'
                $URL = $Return.'@odata.nextLink'
                $Return
            } until ($null -eq $URL)

            if ($ReturnedData.'@adminapi.warnings' -and $ReturnedData.value -eq $null) {
                $ReturnedData.value = $ReturnedData.'@adminapi.warnings'
            }
        } catch {
            $ErrorMess = $($_.Exception.Message)
            $ReportedError = ($_.ErrorDetails | ConvertFrom-Json -ErrorAction SilentlyContinue)
            $Message = if ($ReportedError.error.details.message) {
                $ReportedError.error.details.message
            } elseif ($ReportedError.error.message) { $ReportedError.error.message }
            else { $ReportedError.error.innererror.internalException.message }
            if ($null -eq $Message) { $Message = $ErrorMess }
            throw $Message
        }
        return $ReturnedData.value
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}