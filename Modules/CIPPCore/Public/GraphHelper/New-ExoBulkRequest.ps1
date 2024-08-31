

function New-ExoBulkRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        $tenantid,
        $cmdletArray,
        $useSystemMailbox,
        $Anchor,
        $NoAuthCheck,
        $Select,
        [switch]$Compliance,
        [switch]$AsApp
    )
    if ((Get-AuthorisedRequest -TenantID $tenantid) -or $NoAuthCheck -eq $True) {
        if ($Compliance.IsPresent) {
            $Resource = 'https://ps.compliance.protection.outlook.com'
        } else {
            $Resource = 'https://outlook.office365.com'
        }
        $Token = Get-GraphToken -Tenantid $tenantid -scope "$Resource/.default" -AsApp:$AsApp.IsPresent

        $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $tenantid -or $_.customerId -eq $tenantid }
        $Headers = @{
            Authorization             = $Token.Authorization
            Prefer                    = 'odata.maxpagesize = 1000;odata.continue-on-error'
            'parameter-based-routing' = $true
            'X-AnchorMailbox'         = $Anchor
        }

        if ($Compliance.IsPresent) {
            if (!$Anchor) {
                if (!$Tenant.initialDomainName -or $Tenant.initialDomainName -notlike '*onmicrosoft.com*') {
                    $OnMicrosoft = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $tenantid -NoAuthCheck $NoAuthCheck | Where-Object -Property isInitial -EQ $true).id
                } else {
                    $OnMicrosoft = $Tenant.initialDomainName
                }
                $Headers.Anchor = "UPN:SystemMailbox{bb558c35-97f1-4cb9-8ff7-d53741dc928c}@$($OnMicrosoft)"
            }
            if (!$Tenant.ComplianceUrl) {
                Write-Verbose "Getting Compliance URL for $($tenant.defaultDomainName)"
                $URL = "$Resource/adminapi/$ApiVersion/$($tenant.customerId)/EXOBanner('AutogenSession')?Version=$ModuleVersion"
                Invoke-RestMethod -ResponseHeadersVariable ComplianceHeaders -MaximumRedirection 0 -ErrorAction SilentlyContinue -Uri $URL -Headers $Headers -SkipHttpErrorCheck | Out-Null
                $RedirectedHost = ([System.Uri]($ComplianceHeaders.Location | Select-Object -First 1)).Host
                $RedirectedHostname = '{0}.ps.compliance.protection.outlook.com' -f ($RedirectedHost -split '\.' | Select-Object -First 1)
                $Resource = "https://$($RedirectedHostname)"
                try {
                    $null = [System.Uri]$Resource
                    $Tenant | Add-Member -MemberType NoteProperty -Name ComplianceUrl -Value $Resource
                    $TenantTable = Get-CIPPTable -tablename 'Tenants'
                    Add-CIPPAzDataTableEntity @TenantTable -Entity $Tenant -Force
                } catch {
                    Write-Error "Failed to get the Compliance URL for $($tenant.defaultDomainName), invalid URL - check the Anchor and try again."
                    return
                }
            } else {
                $Resource = $Tenant.ComplianceUrl
            }
            Write-Verbose "Redirecting to $Resource"
        }

        try {
            if ($Select) { $Select = "`$select=$Select" }
            $URL = "$Resource/adminapi/beta/$($tenant.customerId)/InvokeCommand?$Select"
            $BatchURL = "$Resource/adminapi/beta/$($tenant.customerId)/`$batch"
            $BatchBodyObj = @{
                requests = @()
            }
            # Split the cmdletArray into batches of 10
            $batches = [System.Collections.ArrayList]@()
            for ($i = 0; $i -lt $cmdletArray.Length; $i += 10) {
                $null = $batches.Add($cmdletArray[$i..[math]::Min($i + 9, $cmdletArray.Length - 1)])
            }

            # Process each batch
            $ReturnedData = foreach ($batch in $batches) {
                $BatchBodyObj.requests = [System.Collections.ArrayList]@()
                foreach ($cmd in $batch) {
                    $cmdparams = $cmd.CmdletInput.Parameters
                    if ($cmdparams.Identity) { $Anchor = $cmdparams.Identity }
                    if ($cmdparams.anr) { $Anchor = $cmdparams.anr }
                    if ($cmdparams.User) { $Anchor = $cmdparams.User }
                    if (!$Anchor -or $useSystemMailbox) {
                        $OnMicrosoft = $Tenant.initialDomainName
                        $Anchor = "UPN:SystemMailbox{8cc370d3-822a-4ab8-a926-bb94bd0641a9}@$($OnMicrosoft)"
                    }
                    $headers['X-AnchorMailbox'] = $Anchor
                    $Headers['X-CmdletName'] = $cmd.CmdletInput.CmdletName
                    $headers['Accept'] = 'application/json; odata.metadata=minimal'
                    $headers['Accept-Encoding'] = 'gzip'
                    $BatchRequest = @{
                        url     = $URL
                        method  = 'POST'
                        body    = $cmd
                        headers = $Headers.Clone()
                        id      = "$(New-Guid)"
                    }
                    $null = $BatchBodyObj['requests'].add($BatchRequest)
                }
                $Results = Invoke-RestMethod $BatchURL -ResponseHeadersVariable responseHeaders -Method POST -Body (ConvertTo-Json -InputObject $BatchBodyObj -Depth 10) -Headers $Headers -ContentType 'application/json; charset=utf-8'
                $Results
                Write-Host "Batch #$($batches.IndexOf($batch) + 1) of $($batches.Count) processed"
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
        $FinalData = foreach ($item in $ReturnedData.responses.body) {
            if ($item.'@adminapi.warnings') {
                Write-Warning $($item.'@adminapi.warnings' | Out-String)
            }
            if ($item.error) {
                if ($item.error.details.message) {
                    $msg = [pscustomobject]@{error = $item.error.details.message; target = $item.error.details.target }
                } else {
                    $msg = [pscustomobject]@{error = $item.error.message; target = $item.error.details.target }
                }
                $item | Add-Member -MemberType NoteProperty -Name 'value' -Value $msg -Force
            }
            [pscustomobject]$item.value
        }
        return $FinalData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
