function Invoke-ListPartnerTenants {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.Read
    .DESCRIPTION
        Lists configured partner (CSP) tenants. Metadata and token health only - never
        secret values.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Flag = Get-CIPPFeatureFlag -Id 'MultiPartner'
        if (-not $Flag.Enabled) {
            throw 'The Multiple Partner Tenants feature is not enabled.'
        }
        $null = Get-CIPPAuthentication

        $Table = Get-CIPPTable -tablename 'PartnerTenants'
        $Rows = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Partners'"

        $TenantsTable = Get-CIPPTable -tablename 'Tenants'
        # Customer rows only: no partner rows, no direct tenants. A blank partnerTenantId
        # means the tenant belongs to the primary partner.
        $TenantRows = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and Excluded eq false" |
            Where-Object { $_.delegatedPrivilegeStatus -ne 'directTenant' -and $_.customerId -notin @($Rows.RowKey) -and $_.customerId -ne $env:TenantID }

        $Partners = foreach ($Row in $Rows) {
            $IsPrimaryRow = $Row.RowKey -eq $env:TenantID
            [PSCustomObject]@{
                partnerTenantId                = $Row.RowKey
                displayName                    = $Row.displayName
                defaultDomainName              = $Row.defaultDomainName
                authenticatedUserPrincipalName = $Row.authenticatedUserPrincipalName
                addedDate                      = $Row.addedDate
                lastTokenRefresh               = $Row.lastTokenRefresh
                Enabled                        = $Row.Enabled -ne $false
                Managed                        = $Row.Managed -ne $false
                IsPrimary                      = $IsPrimaryRow
                tenantCount                    = @($TenantRows | Where-Object { $_.partnerTenantId -eq $Row.RowKey -or ($IsPrimaryRow -and [string]::IsNullOrEmpty($_.partnerTenantId)) }).Count
            }
        }
        # The primary partner always exists even before its row is seeded
        if (-not ($Partners | Where-Object { $_.IsPrimary })) {
            $Partners = @($Partners) + [PSCustomObject]@{
                partnerTenantId                = "$env:TenantID"
                displayName                    = '*Partner Tenant'
                defaultDomainName              = $null
                authenticatedUserPrincipalName = $null
                addedDate                      = $null
                lastTokenRefresh               = $null
                Enabled                        = $true
                IsPrimary                      = $true
                tenantCount                    = @($TenantRows | Where-Object { [string]::IsNullOrEmpty($_.partnerTenantId) -or $_.partnerTenantId -eq $env:TenantID }).Count
            }
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = @($Partners | Sort-Object -Property @{Expression = 'IsPrimary'; Descending = $true }, displayName) }
    } catch {
        Write-LogMessage -API 'ListPartnerTenants' -message "Failed to list partner tenants: $($_.Exception.Message)" -LogData (Get-CippException -Exception $_) -sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = @("Failed to list partner tenants: $($_.Exception.Message)") }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
