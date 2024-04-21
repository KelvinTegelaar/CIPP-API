

function New-ExoBulkRequest ($tenantid, $cmdletArray, $useSystemMailbox, $Anchor, $NoAuthCheck, $Select, $IgnoreResponse = $false) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    if ((Get-AuthorisedRequest -TenantID $tenantid) -or $NoAuthCheck -eq $True) {
        $token = Get-ClassicAPIToken -resource 'https://outlook.office365.com' -Tenantid $tenantid
        $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $tenantid -or $_.customerId -eq $tenantid }
        if (!$Anchor) {
            $cmdparams = [pscustomobject]$cmdletArray[-1].parameters
            Write-Host "cmdparams are $cmdparams"
            if ($cmdparams.Identity) { $Anchor = $cmdparams.Identity }
            if ($cmdparams.anr) { $Anchor = $cmdparams.anr }
            if ($cmdparams.User) { $Anchor = $cmdparams.User }
            if (!$Anchor -or $useSystemMailbox) {
                if (!$Tenant.initialDomainName) {
                    $OnMicrosoft = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $tenantid -NoAuthCheck $NoAuthCheck | Where-Object -Property isInitial -EQ $true).id
                } else {
                    $OnMicrosoft = $Tenant.initialDomainName
                }
                $anchor = "UPN:SystemMailbox{8cc370d3-822a-4ab8-a926-bb94bd0641a9}@$($OnMicrosoft)"
            }
        }
        Write-Host "Using $Anchor for bulk request"
        $Headers = @{
            Authorization             = "Bearer $($token.access_token)"
            Prefer                    = 'odata.maxpagesize = 1000;odata.continue-on-error'
            'parameter-based-routing' = $true
            'X-AnchorMailbox'         = $anchor
        }
        try {
            if ($Select) { $Select = "`$select=$Select" }
            $URL = "https://outlook.office365.com/adminapi/beta/$($tenant.customerId)/InvokeCommand?$Select"
            $BatchURL = "https://outlook.office365.com/adminapi/beta/$($tenant.customerId)/`$batch"
            $BatchBodyObj = @{
                requests = @()
            }
            $BatchBodyObj.requests = [System.Collections.ArrayList]@()
            $i = 0
            #The maximum batch size is 10, so we need to split the requests into batches of 10.
            $cmdletArray | ForEach-Object {
                $BatchRequest = @{}
                $BatchRequest['url'] = $URL
                $BatchRequest['method'] = 'POST'
                $BatchRequest['body'] = $_
                $BatchRequest['headers'] = $Headers
                $BatchRequest['id'] = "$(New-Guid)"
                $null = $BatchBodyObj['requests'].add($BatchRequest)
            }
            $ReturnedData = Invoke-RestMethod $BatchURL -ResponseHeadersVariable responseHeaders -Method POST -Body (ConvertTo-Json -InputObject $BatchBodyObj -Depth 10) -Headers $Headers -ContentType 'application/json; charset=utf-8'
        
        
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

        if ($IgnoreResponse -eq $true) {
            return 'Task sent to exchange'
        }
        if ($ReturnedData.value) {
            Write-Host 'found value'
        } else {
            $boundary = "--$($responseHeaders.'Content-Type' -split 'boundary=' | Select-Object -Last 1)"
            Write-Host "boundary is $boundary"
            $parts = $ReturnedData -split $boundary | Where-Object { $_.Trim() -ne '' }
            $ReturnedDataSplit = foreach ($part in $parts) {
                $jsonString = $part -split '\r?\n\r?\n' | Where-Object { $_ -like '*{*' } | Out-String
                $jsonObject = $jsonString | ConvertFrom-Json
                if ($jsonObject.'@adminapi.warnings') {
                    $jsonObject.value = $jsonObject.'@adminapi.warnings'
                }
                if ($jsonObject.error) {
                    $jsonObject | Add-Member -MemberType NoteProperty -Name 'value' -Value $jsonObject.error.message -Force
                }
                $jsonObject.value
            }
            return $ReturnedDataSplit 
        }
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}