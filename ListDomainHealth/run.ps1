using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

Import-Module .\DNSHelper.psm1

$UserCreds = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$StatusCode = [HttpStatusCode]::OK
try {
    if ($Request.Query.Action) {
        if ($Request.Query.Domain -match '^(((?!-))(xn--|_{1,1})?[a-z0-9-]{0,61}[a-z0-9]{1,1}\.)*(xn--)?([a-z0-9][a-z0-9\-]{0,60}|[a-z0-9-]{1,30}\.[a-z]{2,})$') {
            $DomainTable = Get-CIPPTable -Table 'Domains'
            $DomainQuery = @{
                Table      = $DomainTable
                ColumnName = 'RowKey'
                Value      = $Request.Query.Domain
                Operator   = 'Equal'
            }
            $DomainInfo = Get-AzTableRow @DomainQuery
            switch ($Request.Query.Action) {
                'ReadSpfRecord' {
                    $SpfQuery = @{
                        Domain = $Request.Query.Domain
                    }

                    if ($Request.Query.ExpectedInclude) {
                        $SpfQuery.ExpectedInclude = $Request.Query.ExpectedInclude
                    }

                    if ($Request.Query.Record) {
                        $SpfQuery.Record = $Request.Query.Record
                    }

                    $Body = Read-SpfRecord @SpfQuery
                }
                'ReadDmarcPolicy' {
                    $Body = Read-DmarcPolicy -Domain $Request.Query.Domain
                }
                'ReadDkimRecord' {
                    $DkimQuery = @{
                        Domain = $Request.Query.Domain
                    }
                    if ($Request.Query.Selector) {
                        $DkimQuery.Selectors = ($Request.Query.Selector).trim() -split '\s*,\s*'
                        
                        if ('admin' -in $UserCreds.userRoles -or 'editor' -in $UserCreds.userRoles) {
                            $DomainInfo.DkimSelectors = ($DkimQuery.Selectors | ConvertTo-Json)
                            $DomainInfo | Update-AzTableRow -Table $DomainTable
                        }
                    }
                    elseif (![string]::IsNullOrEmpty($DomainInfo.DkimSelectors)) {
                        $DkimQuery.Selectors = ($DomainInfo.DkimSelectors | ConvertFrom-Json)
                    }
                    $Body = Read-DkimRecord @DkimQuery
                }
                'ReadMXRecord' {
                    $Body = Read-MXRecord -Domain $Request.Query.Domain
                }
                'TestDNSSEC' {
                    $Body = Test-DNSSEC -Domain $Request.Query.Domain
                }
                'ReadWhoisRecord' {
                    $Body = Read-WhoisRecord -Query $Request.Query.Domain
                }
                'ReadNSRecord' {
                    $Body = Read-NSRecord -Domain $Request.Query.Domain
                }
                'TestHttpsCertificate' {
                    $HttpsQuery = @{
                        Domain = $Request.Query.Domain
                    }
                    if ($Request.Query.Subdomains) {
                        $HttpsQuery.Subdomains = ($Request.Query.Subdomains).trim() -split '\s*,\s*'
                    }
                    else {
                        $HttpsQuery.Subdomains = 'www'
                    }

                    $Body = Test-HttpsCertificate @HttpsQuery
                }
                'TestMtaSts' {
                    $HttpsQuery = @{
                        Domain = $Request.Query.Domain
                    }
                    $Body = Test-MtaSts @HttpsQuery
                }
            }
        }
        else {
            $body = [pscustomobject]@{'Results' = "Domain: $($Request.Query.Domain) is invalid" }
            $StatusCode = [HttpStatusCode]::BadRequest
        }
    }
}
catch {
    Log-Request -API $APINAME -tenant $($name) -user $request.headers.'x-ms-client-principal' -message "DNS Helper API failed. $($_.Exception.Message)" -Sev 'Error'
    $body = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    $StatusCode = [HttpStatusCode]::BadRequest
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $body
    })
