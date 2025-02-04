function New-GraphBulkRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    Param(
        $tenantid,
        $NoAuthCheck,
        $scope,
        $asapp,
        $Requests
    )

    if ($NoAuthCheck -or (Get-AuthorisedRequest -Uri $uri -TenantID $tenantid)) {
        $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp

        $URL = 'https://graph.microsoft.com/beta/$batch'

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
        try {
            $ReturnedData = for ($i = 0; $i -lt $Requests.count; $i += 20) {
                $req = @{}
                # Use select to create hashtables of id, method and url for each call
                $req['requests'] = ($Requests[$i..($i + 19)])
                $ReqBody = (ConvertTo-Json -InputObject $req -Compress -Depth 100)
                $Return = Invoke-RestMethod -Uri $URL -Method POST -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $ReqBody
                if ($Return.headers.'retry-after') {
                    #Revist this when we are pushing this data into our custom schema instead.
                    $headers = Get-GraphToken -tenantid $tenantid -scope $scope -AsApp $asapp
                    Invoke-RestMethod -Uri $URL -Method POST -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $ReqBody
                }
                $Return
            }
            foreach ($MoreData in $ReturnedData.Responses | Where-Object { $_.body.'@odata.nextLink' }) {
                Write-Host 'Getting more'
                Write-Host $MoreData.body.'@odata.nextLink'
                $AdditionalValues = New-GraphGetRequest -ComplexFilter -uri $MoreData.body.'@odata.nextLink' -tenantid $tenantid -NoAuthCheck $NoAuthCheck -scope $scope -AsApp $asapp
                $NewValues = [System.Collections.Generic.List[PSCustomObject]]$MoreData.body.value
                $AdditionalValues | ForEach-Object { $NewValues.add($_) }
                $MoreData.body.value = $NewValues
            }

        } catch {
            $Message = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error.message
            if ($null -eq $Message) { $Message = $($_.Exception.Message) }
            if ($Message -ne 'Request not applicable to target tenant.') {
                $Tenant.LastGraphError = $Message ?? ''
                $Tenant.GraphErrorCount++
                Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
            }
            throw $Message
        }

        if ($Tenant.PSObject.Properties.Name -notcontains 'LastGraphError') {
            $Tenant | Add-Member -MemberType NoteProperty -Name 'LastGraphError' -Value '' -Force
        } else {
            $Tenant.LastGraphError = ''
        }
        Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant

        return $ReturnedData.responses
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
