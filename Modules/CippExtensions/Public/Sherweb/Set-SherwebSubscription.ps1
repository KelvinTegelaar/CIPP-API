function Set-SherwebSubscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string]$SKU,
        [int]$Quantity,
        [int]$Add,
        [int]$Remove,
        [string]$TenantFilter,
        $Headers
    )

    if ($Headers) {
        # Get extension config and check for AllowedCustomRoles
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $ExtensionConfig = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json
        $Config = $ExtensionConfig.Sherweb

        $AllowedRoles = $Config.AllowedCustomRoles.value
        if ($AllowedRoles) {
            # Resolve caller roles for both interactive users and direct API clients,
            # mirroring the principal detection Test-CIPPAccess/Test-CippApiClientRoleGrant use.
            if ($Headers.'x-ms-client-principal-idp' -eq 'aad' -and $Headers.'x-ms-client-principal-name' -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                $Client = Get-CippApiClient -AppId $Headers.'x-ms-client-principal-name'
                $CallerRoles = if ($Client.Role) { @($Client.Role) } else { @('cipp-api') }
            } elseif ($Headers.'x-ms-client-principal') {
                $CallerRoles = @(Get-CIPPAccessRole -Headers $Headers)
            } else {
                $CallerRoles = @()
            }

            $Allowed = $false
            foreach ($Role in $CallerRoles) {
                if ($AllowedRoles -contains $Role) {
                    Write-Information "Caller has allowed CIPP role: $Role"
                    $Allowed = $true
                    break
                }
            }
            if (-not $Allowed) {
                throw 'This caller is not allowed to modify Sherweb subscriptions.'
            }
        }
    }

    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }
    $AuthHeader = Get-SherwebAuthentication
    $ExistingSubscription = Get-SherwebCurrentSubscription -CustomerId $CustomerId -SKU $SKU

    if (-not $ExistingSubscription) {
        if ($Add -or $Remove) {
            throw "Unable to Add or Remove. No existing subscription with SKU '$SKU' found."
        }

        if (-not $Quantity -or $Quantity -le 0) {
            throw 'A valid Quantity must be specified to create a new subscription when none currently exists.'
        }
        $OrderBody = ConvertTo-Json -Depth 10 -InputObject @{
            cartItems = @(
                @{
                    sku      = $SKU
                    quantity = $Quantity
                }
            )
            orderedBy = 'CIPP-API'
        }
        $OrderUri = "https://api.sherweb.com/service-provider/v1/orders?customerId=$CustomerId"
        $Order = Invoke-RestMethod -Uri $OrderUri -Method POST -Headers $AuthHeader -Body $OrderBody -ContentType 'application/json'
        if ($Order -match 'Internal Server Error' -and $Add -gt 0) {
            throw 'An error occurred while attempting to create a new subscription. Please check the Cumulus portal to ensure this customer has been provisioned for Microsoft 365.'
        }
        return $Order

    } else {
        $SubscriptionId = $ExistingSubscription[0].id
        $CurrentQuantity = $ExistingSubscription[0].quantity

        if ($Add) {
            $FinalQuantity = $CurrentQuantity + $Add
        } elseif ($Remove) {
            $FinalQuantity = $CurrentQuantity - $Remove
            if ($FinalQuantity -lt 0) {
                throw "Cannot remove more licenses than currently allocated. Current: $CurrentQuantity, Attempting to remove: $Remove."
            }

            # Committed subscriptions (NCE) can only be decreased in the days right after a purchase or
            # renewal. Sherweb publishes the current floor; refuse up front with a plain explanation
            # rather than relaying the raw 412 commitment-term-violations error.
            $Minimum = Get-SherwebMinimumQuantity -Subscription $ExistingSubscription[0]
            if ($Minimum -and $FinalQuantity -lt $Minimum.MinimumQuantity) {
                $ProductName = $ExistingSubscription[0].productName
                $RenewalText = if ($Minimum.RenewsOn) { " The term next renews on $($Minimum.RenewsOn.ToString('yyyy-MM-dd'))." } else { '' }
                if ($Minimum.MinimumQuantity -ge $CurrentQuantity) {
                    throw "Sherweb will not accept this decrease: '$ProductName' is on a $($Minimum.TermType) commitment term and its quantity of $CurrentQuantity is locked until the term renews. Committed subscriptions can only be decreased in the first days after a purchase or renewal.$RenewalText Use the 'Schedule decrease at next renewal' action to run the decrease just after that date."
                }
                $UntilText = if ($Minimum.AllowedUntil) { " until $($Minimum.AllowedUntil.ToString('yyyy-MM-dd'))" } else { '' }
                throw "Sherweb will not accept this decrease: '$ProductName' is on a $($Minimum.TermType) commitment term and can currently only be decreased to $($Minimum.MinimumQuantity) license(s)$UntilText, not to $FinalQuantity. Committed subscriptions can only be decreased in the first days after a purchase or renewal.$RenewalText"
            }
        } else {
            if (-not $Quantity -or $Quantity -le 0) {
                throw 'A valid Quantity must be specified if Add/Remove are not used.'
            }
            $FinalQuantity = $Quantity
        }
        $Body = ConvertTo-Json -Depth 10 -InputObject @{
            subscriptionAmendmentParameters = @(
                @{
                    subscriptionId = $SubscriptionId
                    newQuantity    = $FinalQuantity
                }
            )
        }
        $Uri = "https://api.sherweb.com/service-provider/v1/billing/subscriptions/amendments?customerId=$CustomerId"
        $Update = Invoke-RestMethod -Uri $Uri -Method POST -Headers $AuthHeader -Body $Body -ContentType 'application/json'
        return $Update
    }
}
