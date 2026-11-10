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
        # Users ask for a license with the "Ask for a license" button in Microsoft 365 apps. When the tenant has no
        # custom license request policy, Microsoft keeps each request in this pending list and shows it only under
        # Billing > License requests in the admin center, so the MSP is never told. This alert reads that list.
        $Tenant = Get-Tenants -TenantFilter $TenantFilter -SkipDomains | Select-Object -First 1
        $Uri = "https://admin.microsoft.com/fd/m365licensing/v1/tenants/$($Tenant.customerId)/self-service-requests?state=Pending"
        $PendingRequests = @((New-GraphGetRequest -scope 'https://admin.microsoft.com/.default' -tenantid $TenantFilter -uri $Uri).items | Where-Object { $_ })

        $AlertData = @()
        if ($PendingRequests.Count -gt 0) {
            $ConvertTable = Import-Csv (Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')
            # Product IDs seen in the admin center whose SKU is not in the conversion table yet.
            $KnownProducts = @{ 'CFQ7TTC0MM8R' = 'Microsoft 365 Copilot' }

            # Requester names: cached users first, then a live lookup for anyone the cache does not have.
            $Users = @{}
            try {
                foreach ($CachedUser in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'userPrincipalName', 'displayName')) {
                    if ($CachedUser.id) { $Users[$CachedUser.id] = $CachedUser }
                }
            } catch {
                Write-Information "LicenseRequests: user cache not available for $($TenantFilter): $($_.Exception.Message)"
            }
            foreach ($UserId in @($PendingRequests.requestedBy | Where-Object { $_ -and -not $Users.ContainsKey($_) } | Select-Object -Unique)) {
                try {
                    $Users[$UserId] = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)?`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter -noPagination $true
                } catch {
                    Write-Information "LicenseRequests: could not look up user $UserId in $($TenantFilter): $($_.Exception.Message)"
                }
            }

            $LicenseRequestsUrl = "https://admin.cloud.microsoft/?delegatedOrg=$($Tenant.initialDomainName)#/licenserequest"

            $AlertData = foreach ($Request in $PendingRequests) {
                $Product = ($ConvertTable | Where-Object { $_.GUID -eq $Request.skuId } | Select-Object -Last 1).Product_Display_Name
                if (-not $Product) { $Product = $KnownProducts[[string]$Request.productId] }
                if (-not $Product) { $Product = $Request.productId }
                $User = $Users[[string]$Request.requestedBy]
                $UserLabel = if ($User.userPrincipalName) { $User.userPrincipalName } else { $Request.requestedBy }

                [PSCustomObject]@{
                    Message            = "$UserLabel requested a license for $Product"
                    # Id (the request ID) keys the alert lifecycle, so each request alerts once, even when one user
                    # asks for several products. UPN (not UserPrincipalName) is used so it does not take over the key.
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

        # Called on every successful run, also with no requests, so requests that were handled are resolved.
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
