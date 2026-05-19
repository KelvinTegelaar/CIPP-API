function Push-UpdatePermissionsQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Status = 'Failed'
    $FailureMessage = $null
    $DomainRefreshRequired = $false

    try {
        if (!$Item.defaultDomainName) {
            $DomainRefreshRequired = $true
        }

        Write-Information "Applying permissions for $($Item.displayName)"
        $Table = Get-CIPPTable -TableName cpvtenants
        $CPVRows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Tenant -EQ $Item.customerId

        $Tenant = Get-Tenants -TenantFilter $Item.customerId -IncludeErrors

        if ((!$CPVRows -or $env:ApplicationID -notin $CPVRows.applicationId) -and $Tenant.delegatedPrivilegeStatus -ne 'directTenant') {
            Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message 'A New tenant has been added, or a new CIPP-SAM Application is in use' -Sev 'Warning' -API 'NewTenant'
            Write-Information 'Adding CPV permissions'
            Set-CIPPCPVConsent -Tenantfilter $Item.customerId
            $DomainRefreshRequired = $true
        }
        Write-Information 'Updating permissions'
        $AppResults = Add-CIPPApplicationPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -tenantfilter $Item.customerId
        $DelegatedResults = Add-CIPPDelegatedPermission -RequiredResourceAccess 'CIPPDefaults' -ApplicationId $env:ApplicationID -tenantfilter $Item.customerId

        # Check for permission failures (excluding service principal creation failures)
        $AllResults = @($AppResults) + @($DelegatedResults)
        $PermissionFailures = $AllResults | Where-Object {
            $_ -like '*Failed*' -and
            $_ -notlike '*Failed to create service principal*'
        }

        if ($PermissionFailures) {
            $Status = 'Failed'
            $FailureMessage = ($PermissionFailures -join '; ')
            Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message "Permission update completed with failures for $($Item.displayName): $FailureMessage" -Sev 'Warning' -API 'UpdatePermissionsQueue'
        } else {
            $Status = 'Success'
            Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message "Updated permissions for $($Item.displayName)" -Sev 'Info' -API 'UpdatePermissionsQueue'
        }

        if ($Item.defaultDomainName -ne 'PartnerTenant') {
            Write-Information 'Pushing CIPP-SAM admin roles'
            try {
                Set-CIPPSAMAdminRoles -TenantFilter $Item.customerId
            } catch {
                $SamRoleError = Get-CippException -Exception $_
                Write-Information "Failed to set CIPP-SAM admin roles for $($Item.displayName): $($_.Exception.Message)"
                Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message "Failed to set CIPP-SAM admin roles for $($Item.displayName) - $($_.Exception.Message)" -Sev 'Warning' -API 'UpdatePermissionsQueue' -LogData $SamRoleError
                if ($Status -eq 'Success') {
                    $Status = 'Failed'
                    $FailureMessage = "Set-CIPPSAMAdminRoles: $($_.Exception.Message)"
                }
            }
        }
    } catch {
        Write-Information "Error updating permissions for $($Item.displayName): $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message "Error updating permissions for $($Item.displayName) - $($_.Exception.Message)" -Sev 'Error' -API 'UpdatePermissionsQueue' -LogData (Get-CippException -Exception $_)
        $Status = 'Failed'
        if (-not $FailureMessage) {
            $FailureMessage = $_.Exception.Message
        }
    } finally {
        try {
            $CpvTable = Get-CIPPTable -TableName cpvtenants
            $unixtime = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
            $GraphRequest = @{
                LastApply     = "$unixtime"
                LastStatus    = "$Status"
                applicationId = "$($env:ApplicationID)"
                Tenant        = "$($Item.customerId)"
                PartitionKey  = 'Tenant'
                RowKey        = "$($Item.customerId)"
            }
            if ($FailureMessage) {
                $GraphRequest.LastError = "$FailureMessage"
            }
            Add-CIPPAzDataTableEntity @CpvTable -Entity $GraphRequest -Force
        } catch {
            Write-Information "Failed to persist cpvtenants row for $($Item.displayName): $($_.Exception.Message)"
        }

        if ($DomainRefreshRequired) {
            try {
                $UpdatedTenant = Get-Tenants -TenantFilter $Item.customerId -TriggerRefresh
                if ($UpdatedTenant.defaultDomainName) {
                    Write-Information "Updated tenant domains $($UpdatedTenant.defaultDomainName)"
                }
            } catch {
                Write-Information "Failed to refresh tenant domains for $($Item.displayName): $($_.Exception.Message)"
            }
        }
    }
}
