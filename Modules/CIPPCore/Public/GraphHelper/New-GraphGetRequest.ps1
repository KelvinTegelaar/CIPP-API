function New-GraphGetRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    Param(
        $uri,
        $tenantid,
        $scope,
        $AsApp,
        $noPagination,
        $NoAuthCheck,
        $skipTokenCache,
        [switch]$ComplexFilter,
        [switch]$CountOnly
    )

    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
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
                LastGraphError  = $null
                PartitionKey    = 'TenantFailed'
                RowKey          = 'Failed'
            }
        }

        $ReturnedData = do {
            try {
                $Data = (Invoke-RestMethod -Uri $nextURL -Method GET -Headers $headers -ContentType 'application/json; charset=utf-8')
                if ($CountOnly) {
                    $Data.'@odata.count'
                    $nextURL = $null
                } else {
                    if ($data.value) { $data.value } else { ($Data) }
                    if ($noPagination) { $nextURL = $null } else { $nextURL = $data.'@odata.nextLink' }
                }
            } catch {
                try {
                    $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
                } catch { $Message = $null }
                if ($Message -eq $null) { $Message = $($_.Exception.Message) }
                if ($Message -ne 'Request not applicable to target tenant.' -and $Tenant) {
                    $Tenant.LastGraphError = $Message
                    $Tenant.GraphErrorCount++
                    Update-AzDataTableEntity @TenantsTable -Entity $Tenant
                }
                throw $Message
            }
        } until ($null -eq $NextURL -or ' ' -eq $NextURL)
        $Tenant.LastGraphError = ''
        Update-AzDataTableEntity @TenantsTable -Entity $Tenant
        return $ReturnedData
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
