function Get-ClassicAPIToken($tenantID, $Resource) {
    <#
    .FUNCTIONALITY
    Internal
    #>
    # Initialize the synchronized cache once at the top to avoid a race between the null-check and assignment.
    if (-not $script:classictoken) {
        $script:classictoken = [HashTable]::Synchronized(@{})
    }

    $TokenKey = '{0}-{1}' -f $TenantID, $Resource
    if ($script:classictoken.$TokenKey -and [int](Get-Date -UFormat %s -Millisecond 0) -lt $script:classictoken.$TokenKey.expires_on) {
        return $script:classictoken.$TokenKey
    } else {
        $uri = "https://login.microsoftonline.com/$($TenantID)/oauth2/token"
        $Body = @{
            client_id     = $env:ApplicationID
            client_secret = $env:ApplicationSecret
            resource      = $Resource
            refresh_token = $env:RefreshToken
            grant_type    = 'refresh_token'
        }
        try {
            $script:classictoken[$TokenKey] = Invoke-CIPPRestMethod -Uri $uri -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction SilentlyContinue -Method post
            return $script:classictoken[$TokenKey]
        } catch {
            # Track consecutive Graph API failures
            $TenantsTable = Get-CippTable -tablename Tenants
            $Filter = "PartitionKey eq 'Tenants' and (defaultDomainName eq '{0}' or customerId eq '{0}')" -f $tenantid
            $Tenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter
            if (!$Tenant) {
                $Tenant = @{
                    GraphErrorCount     = $null
                    LastGraphTokenError = $null
                    LastGraphError      = $null
                    PartitionKey        = 'TenantFailed'
                    RowKey              = 'Failed'
                }
            }
            $Tenant.LastGraphError = $_.Exception.Message
            $Tenant.GraphErrorCount++

            Update-AzDataTableEntity -Force @TenantsTable -Entity $Tenant
            Throw "Failed to obtain Classic API Token for $TenantID - $_"
        }
    }
}
