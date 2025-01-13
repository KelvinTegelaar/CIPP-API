function New-GraphGetRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    Param(
        [string]$uri,
        [string]$tenantid,
        [string]$scope,
        [bool]$AsApp,
        [bool]$noPagination,
        [bool]$NoAuthCheck,
        [bool]$skipTokenCache,
        $Caller,
        [switch]$ComplexFilter,
        [switch]$CountOnly,
        [switch]$IncludeResponseHeaders
    )
    $IsAuthorised = Get-AuthorisedRequest -Uri $uri -TenantID $tenantid

    if ($NoAuthCheck -eq $true -or $IsAuthorised) {
        if ($scope -eq 'ExchangeOnline') {
            $AccessToken = Get-ClassicAPIToken -resource 'https://outlook.office365.com' -Tenantid $tenantid
            $headers = @{ Authorization = "Bearer $($AccessToken.access_token)" }
        } else {
            $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp -SkipCache $skipTokenCache
        }

        if ($ComplexFilter) {
            $headers['ConsistencyLevel'] = 'eventual'
        }
        $nextURL = $uri

        # Track consecutive Graph API failures
        $TenantsTable = Get-CippTable -tablename Tenants
        $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
        $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
        if (!$Tenant) {
            $Tenant = @{
                GraphErrorCount = 0
                LastGraphError  = ''
                PartitionKey    = 'TenantFailed'
                RowKey          = 'Failed'
            }
        }

        $ReturnedData = do {
            try {
                $GraphRequest = @{
                    Uri         = $nextURL
                    Method      = 'GET'
                    Headers     = $headers
                    ContentType = 'application/json; charset=utf-8'
                }
                if ($IncludeResponseHeaders) {
                    $GraphRequest.ResponseHeadersVariable = 'ResponseHeaders'
                }
                $Data = (Invoke-RestMethod @GraphRequest)
                if ($CountOnly) {
                    $Data.'@odata.count'
                    $NextURL = $null
                } else {
                    if ($Data.PSObject.Properties.Name -contains 'value') { $data.value } else { $Data }
                    if ($noPagination) {
                        if ($Caller -eq 'Get-GraphRequestList') {
                            @{ 'nextLink' = $data.'@odata.nextLink' }
                        }
                        $nextURL = $null
                    } else {
                        $NextPageUriFound = $false
                        if ($IncludeResponseHeaders) {
                            if ($ResponseHeaders.NextPageUri) {
                                $NextURL = $ResponseHeaders.NextPageUri
                                $NextPageUriFound = $true
                            }
                        }
                        if (!$NextPageUriFound) {
                            $nextURL = $data.'@odata.nextLink'
                        }
                    }
                }
            } catch {
                try {
                    $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
                } catch { $Message = $null }
                if ($Message -eq $null) { $Message = $($_.Exception.Message) }
                if ($Message -ne 'Request not applicable to target tenant.' -and $Tenant) {
                    $Tenant.LastGraphError = $Message
                    if ($Tenant.PSObject.Properties.Name -notcontains 'GraphErrorCount') {
                        $Tenant | Add-Member -MemberType NoteProperty -Name 'GraphErrorCount' -Value 0 -Force
                    }
                    $Tenant.GraphErrorCount++
                    Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
                }
                throw $Message
            }
        } until ([string]::IsNullOrEmpty($NextURL) -or $NextURL -is [object[]] -or ' ' -eq $NextURL)
        if ($Tenant.PSObject.Properties.Name -notcontains 'LastGraphError') {
            $Tenant | Add-Member -MemberType NoteProperty -Name 'LastGraphError' -Value '' -Force
        } else {
            $Tenant.LastGraphError = ''
        }
        if ($Tenant.PSObject.Properties.Name -notcontains 'GraphErrorCount') {
            $Tenant | Add-Member -MemberType NoteProperty -Name 'GraphErrorCount' -Value 0 -Force
        } else {
            $Tenant.GraphErrorCount = 0
        }
        Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
        return $ReturnedData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
