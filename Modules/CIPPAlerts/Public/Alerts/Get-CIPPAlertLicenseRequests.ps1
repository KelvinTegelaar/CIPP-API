function Get-CIPPAlertLicenseRequests {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        $Tenant = @(Get-Tenants -TenantFilter $TenantFilter -SkipDomains)[0]
        $Uri = "https://admin.microsoft.com/fd/m365licensing/v1/tenants/$($Tenant.customerId)/self-service-requests?state=Pending"
        $PendingRequests = @((New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -tenantid $TenantFilter -uri $Uri).items).Where({ $_ })

        $AlertData = @()
        if ($PendingRequests.Count -gt 0) {
            $SkuNames = @{}
            foreach ($Sku in Get-CIPPLicenseSkuName -SkuIds @($PendingRequests.skuId) -TenantFilter $TenantFilter) { $SkuNames[$Sku.skuId] = $Sku.displayName }

            $Users = @{}
            $UserIds = @(@($PendingRequests.requestedBy).Where({ $_ -as [guid] }) | Sort-Object -Unique)
            $DbTable = Get-CIPPTable -TableName 'CippReportingDB'
            # One range query per user: OR-ed RowKey conditions make the table scan the whole partition
            foreach ($UserId in $UserIds) {
                try {
                    $Rows = @(Get-CIPPAzDataTableEntity @DbTable -Filter "PartitionKey eq '$($Tenant.defaultDomainName)' and RowKey ge 'Users-$UserId' and RowKey lt 'Users-$UserId.'")
                    foreach ($User in New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' -Rows $Rows -Fields 'id', 'userPrincipalName', 'displayName') { $Users[$User.id] = $User }
                } catch {
                    Write-Information "LicenseRequests: user cache lookup failed for $UserId in $($TenantFilter): $($_.Exception.Message)"
                }
            }
            $Uncached = @($UserIds.Where({ -not $Users.ContainsKey($_) }))
            for ($i = 0; $i -lt $Uncached.Count; $i += 15) {
                $Ids = @(foreach ($UserId in $Uncached[$i..([Math]::Min($i + 14, $Uncached.Count - 1))]) { "'$UserId'" }) -join ','
                try {
                    foreach ($User in New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=id in ($Ids)&`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter) {
                        $Users[$User.id] = $User
                    }
                } catch {
                    Write-Information "LicenseRequests: user lookup failed for $($TenantFilter): $($_.Exception.Message)"
                }
            }

            $LicenseRequestsUrl = "https://admin.cloud.microsoft/?delegatedOrg=$($Tenant.initialDomainName)#/licenserequest"

            $AlertData = foreach ($Request in $PendingRequests) {
                $Product = $SkuNames[([string]$Request.skuId).ToLowerInvariant()] ?? $Request.productId
                $User = $Users[[string]$Request.requestedBy]
                $UserLabel = $User.userPrincipalName ?? $Request.requestedBy

                [PSCustomObject]@{
                    Message            = "$UserLabel requested a license for $Product"
                    # UPN, not UserPrincipalName, so the request Id stays the lifecycle key
                    Id                 = $Request.requestId
                    UPN                = $User.userPrincipalName
                    DisplayName        = $User.displayName
                    UserId             = $Request.requestedBy
                    Product            = $Product
                    ProductId          = $Request.productId
                    SkuId              = $Request.skuId
                    Reason             = $Request.requestReason
                    RequestDate        = $Request.createdTime
                    LicenseRequestsUrl = $LicenseRequestsUrl
                    Tenant             = $TenantFilter
                }
            }
        }

        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if (Test-CippTransientError -Message $ErrorMessage.NormalizedError) {
            Write-AlertMessage -message "LicenseRequests: $($ErrorMessage.NormalizedError) (transient, will retry next run)" -tenant $TenantFilter -LogData $ErrorMessage
        } else {
            Write-AlertMessage -message "LicenseRequests alert failed: $($ErrorMessage.NormalizedError)" -tenant $TenantFilter -LogData $ErrorMessage
        }
    }
}
