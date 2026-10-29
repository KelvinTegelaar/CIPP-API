function Invoke-ExecCPVPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Body.tenantFilter

    $Tenant = Get-Tenants -TenantFilter $TenantFilter -IncludeErrors
    $StatusCode = [HttpStatusCode]::OK

    if ($Tenant) {
        Write-Host "Our tenant is $($Tenant.displayName) - $($Tenant.defaultDomainName)"

        $CPVConsentParams = @{
            TenantFilter = $TenantFilter
        }
        if ($Request.Query.ResetSP -eq $true) {
            $CPVConsentParams.ResetSP = $true
        }

        $CpvKey = "$($Tenant.customerId)"
        $CpvTable = Get-CIPPTable -TableName cpvtenants
        $ExistingCpvRow = $null
        $PermissionResults = @()
        $FailureMessage = $null
        $GraphRequest = try {
            $ExistingCpvRow = Get-CIPPAzDataTableEntity @CpvTable -Filter "PartitionKey eq 'Tenant' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $CpvKey)'"
            if ($TenantFilter -notin @('PartnerTenant', $env:TenantID)) {
                Set-CIPPCPVConsent @CPVConsentParams
            } else {
                $TenantFilter = $env:TenantID
                $Tenant = [PSCustomObject]@{
                    displayName       = '*Partner Tenant'
                    defaultDomainName = $env:TenantID
                }
            }
            $PermissionResults = @(Add-CIPPApplicationPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -tenantfilter $TenantFilter) +
            @(Add-CIPPDelegatedPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -tenantfilter $TenantFilter)
            $PermissionResults
            if ($TenantFilter -notin @('PartnerTenant', $env:TenantID)) {
                Set-CIPPSAMAdminRoles -TenantFilter $TenantFilter
            }
        } catch {
            $FailureMessage = $_.Exception.Message
            "Failed to update permissions for $($Tenant.displayName): $($_.Exception.Message)"
        }

        # Same failure rule as the nightly permission update, which reads this row's status.
        $PermissionFailures = @($PermissionResults | Where-Object { $_ -like '*Failed*' -and $_ -notlike '*Failed to create service principal*' })
        $StatusCode = if ($FailureMessage) { [HttpStatusCode]::InternalServerError } else { Get-CippBulkStatusCode -Total $PermissionResults.Count -Failed $PermissionFailures.Count }
        $Success = $StatusCode -eq [HttpStatusCode]::OK
        if (-not $FailureMessage -and $PermissionFailures.Count -gt 0) { $FailureMessage = $PermissionFailures -join '; ' }

        try {
            $CpvRow = @{
                PartitionKey  = 'Tenant'
                RowKey        = $CpvKey
                Tenant        = $CpvKey
                applicationId = "$($env:ApplicationID)"
                LastApply     = "$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
                LastStatus    = $Success ? 'Success' : 'Failed'
            }
            if ($FailureMessage) { $CpvRow.LastError = "$FailureMessage" }
            if ($Success) { $CpvRow.ConsentAttempts = '0' } elseif ($ExistingCpvRow.ConsentAttempts) { $CpvRow.ConsentAttempts = "$($ExistingCpvRow.ConsentAttempts)" }
            if ($CPVConsentParams.ResetSP) { $CpvRow.LastResetUtc = [datetime]::UtcNow.ToString('o') } elseif ($ExistingCpvRow.LastResetUtc) { $CpvRow.LastResetUtc = "$($ExistingCpvRow.LastResetUtc)" }
            Add-CIPPAzDataTableEntity @CpvTable -Entity $CpvRow -Force
        } catch {
            Write-Information "Failed to persist cpvtenants row for $($Tenant.displayName): $($_.Exception.Message)"
        }

        $Tenant = Get-Tenants -IncludeAll | Where-Object -Property customerId -EQ $TenantFilter | Select-Object -First 1

    } else {
        $GraphRequest = 'Tenant not found'
        $Success = $false
        $StatusCode = [HttpStatusCode]::NotFound
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{
                Results  = $GraphRequest
                Metadata = @{
                    Heading = ('CPV Permission - {0} ({1})' -f $Tenant.displayName, $Tenant.defaultDomainName)
                    Success = $Success
                }
            }
        })

}
