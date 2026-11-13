function Invoke-ExecAssignPartnerTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    .DESCRIPTION
        Reassigns which partner tenant owns a customer tenant. Validates against
        knownPartners, pins the assignment as manual, and clears the customer's token cache.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Flag = Get-CIPPFeatureFlag -Id 'MultiPartner'
        if (-not $Flag.Enabled) {
            throw 'The Multiple Partner Tenants feature is not enabled.'
        }
        $null = Get-CIPPAuthentication

        $CustomerId = $Request.Body.customerId
        $PartnerTenantId = $Request.Body.partnerTenantId
        foreach ($Guid in @($CustomerId, $PartnerTenantId)) {
            if ($Guid -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                throw 'customerId and partnerTenantId must be tenant ids (GUIDs).'
            }
        }

        $PartnerTable = Get-CIPPTable -tablename 'PartnerTenants'
        $Partner = Get-CIPPAzDataTableEntity @PartnerTable -Filter "PartitionKey eq 'Partners' and RowKey eq '$PartnerTenantId'"
        $IsPrimaryTarget = $PartnerTenantId -eq $env:TenantID
        if (-not $IsPrimaryTarget -and (-not $Partner -or $Partner.Enabled -eq $false)) {
            throw "Partner tenant $PartnerTenantId is not configured or is disabled."
        }

        $TenantsTable = Get-CIPPTable -tablename 'Tenants'
        $Row = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$CustomerId'"
        if (-not $Row) {
            throw "Tenant $CustomerId was not found in the tenant cache."
        }
        if ($Row.delegatedPrivilegeStatus -eq 'directTenant') {
            throw 'Direct tenants authenticate with their own credentials and cannot be assigned to a partner.'
        }
        if ($Row.isPartnerTenantRow -eq $true) {
            throw 'Partner tenant rows cannot be reassigned.'
        }

        $KnownPartners = @("$($Row.knownPartners)" -split ',' | Where-Object { $_ })
        if ($KnownPartners -notcontains $PartnerTenantId) {
            throw "Partner tenant $PartnerTenantId has no active GDAP relationship with $($Row.displayName). Refresh the tenant list if the relationship was recently created."
        }

        $PreviousOwner = if ($Row.partnerTenantId) { $Row.partnerTenantId } else { "$env:TenantID" }
        $Row | Add-Member -MemberType NoteProperty -Name 'partnerTenantId' -Value "$PartnerTenantId" -Force
        $Row | Add-Member -MemberType NoteProperty -Name 'partnerAssignmentMode' -Value 'manual' -Force
        Add-CIPPAzDataTableEntity @TenantsTable -Entity $Row -Force | Out-Null

        $null = Clear-CippTokenCache -TenantFilter $CustomerId

        Write-LogMessage -API 'ExecAssignPartnerTenant' -headers $Request.Headers -message "Reassigned tenant $($Row.displayName) ($CustomerId) from partner $PreviousOwner to partner $PartnerTenantId" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = @("Reassigned $($Row.displayName) to partner tenant $PartnerTenantId. Token cache cleared - new tokens will use the new partner immediately.") }
    } catch {
        Write-LogMessage -API 'ExecAssignPartnerTenant' -headers $Request.Headers -message "Failed to reassign partner: $($_.Exception.Message)" -LogData (Get-CippException -Exception $_) -sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = @("Failed to reassign partner: $($_.Exception.Message)") }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
