function Remove-SherwebSubscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomerId,
        [Parameter(Mandatory = $true)]
        [string[]]$SubscriptionIds,
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
                throw 'This caller is not allowed to modify Sherweb Licenses.'
            }
        }
    }


    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Sherweb' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }
    $AuthHeader = Get-SherwebAuthentication
    $Body = ConvertTo-Json -Depth 10 -InputObject @{
        subscriptionIds = @($SubscriptionIds)
    }

    $Uri = "https://api.sherweb.com/service-provider/v1/billing/subscriptions/cancellations?customerId=$CustomerId"
    $Cancel = Invoke-RestMethod -Uri $Uri -Method POST -Headers $AuthHeader -Body $Body -ContentType 'application/json'
    return $Cancel
}
