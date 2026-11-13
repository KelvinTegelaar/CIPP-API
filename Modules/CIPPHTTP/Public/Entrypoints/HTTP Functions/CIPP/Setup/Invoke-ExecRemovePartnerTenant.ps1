function Invoke-ExecRemovePartnerTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    .DESCRIPTION
        Removes an additional partner tenant and its stored refresh token. RemoveTenants
        also deletes its customer tenant rows immediately.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Flag = Get-CIPPFeatureFlag -Id 'MultiPartner'
        if (-not $Flag.Enabled) {
            throw 'The Multiple Partner Tenants feature is not enabled.'
        }
        $null = Get-CIPPAuthentication

        $PartnerTenantId = $Request.Body.partnerTenantId ?? $Request.Query.partnerTenantId
        if ($PartnerTenantId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            throw 'partnerTenantId must be a tenant id (GUID).'
        }

        $Results = [System.Collections.Generic.List[string]]::new()
        $Results.Add((Remove-CIPPPartnerTenant -PartnerTenantId $PartnerTenantId))

        if ($Request.Body.RemoveTenants -eq $true) {
            $TenantsTable = Get-CIPPTable -tablename 'Tenants'
            $OwnedRows = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and partnerTenantId eq '$PartnerTenantId'"
            foreach ($Row in $OwnedRows) {
                Remove-CIPPAzDataTableEntity -Force @TenantsTable -Entity $Row
            }
            $Results.Add("Removed $(@($OwnedRows).Count) tenant(s) owned by partner $PartnerTenantId from the tenant cache.")
        }

        Write-LogMessage -API 'ExecRemovePartnerTenant' -headers $Request.Headers -message "Removed partner tenant $PartnerTenantId" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = @($Results) }
    } catch {
        Write-LogMessage -API 'ExecRemovePartnerTenant' -headers $Request.Headers -message "Failed to remove partner tenant: $($_.Exception.Message)" -LogData (Get-CippException -Exception $_) -sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = @("Failed to remove partner tenant: $($_.Exception.Message)") }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
