function Push-UpdatePermissionsQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Status = 'Failed'
    $FailureMessage = $null
    $DomainRefreshRequired = $false

    # Read by the finally block, so they must survive an early throw in the try.
    $ConsentRow = $null
    $ConsentAttempted = $false
    $Attempts = 0
    $ResetSP = $false

    try {
        if (!$Item.defaultDomainName) {
            $DomainRefreshRequired = $true
        }

        Write-Information "Applying permissions for $($Item.displayName)"
        $Table = Get-CIPPTable -TableName cpvtenants
        $CPVRows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Tenant -EQ $Item.customerId

        $Tenant = Get-Tenants -TenantFilter $Item.customerId -IncludeErrors

        $ConsentRow = $CPVRows | Where-Object { $_.applicationId -eq $env:ApplicationID } | Select-Object -First 1

        # The finally block writes a row even on failure, so existence alone does not prove
        # consent. -eq 'Failed' so status-less legacy rows don't re-consent the estate on deploy.
        $NeedsConsent = !$ConsentRow -or $ConsentRow.LastStatus -eq 'Failed'

        if ($NeedsConsent -and $Tenant.delegatedPrivilegeStatus -ne 'directTenant') {
            # Only a reset can fix an entry that exists but is wrong ('Permission entry already
            # exists' short-circuits a plain re-consent). Escalate on a known consent error or
            # after a failed re-consent; at most one reset per week since it briefly drops access.
            $ConsentAttempted = $true
            $Attempts = if ($ConsentRow.ConsentAttempts) { [int]$ConsentRow.ConsentAttempts } else { 0 }
            $KnownConsentError = [bool]($ConsentRow -and $ConsentRow.LastError -match 'AADSTS(65001|90094|500011)|Insufficient privileges|Authorization_RequestDenied')
            $ResetAllowed = $true
            if ($ConsentRow.LastResetUtc) {
                try { $ResetAllowed = ([datetime]::UtcNow - [datetime]::Parse($ConsentRow.LastResetUtc)).TotalDays -ge 7 } catch { $ResetAllowed = $true }
            }
            $ResetSP = [bool]($ConsentRow -and $ResetAllowed -and ($KnownConsentError -or $Attempts -ge 1))

            $ConsentReason = if (!$ConsentRow) { 'A New tenant has been added, or a new CIPP-SAM Application is in use' }
            elseif ($ResetSP) { "The last permissions run failed and re-applying consent has not fixed it (attempt $($Attempts + 1)), resetting the service principal" }
            else { 'The last permissions run failed, re-applying CPV consent' }
            Write-LogMessage -tenant $Item.defaultDomainName -tenantId $Item.customerId -message $ConsentReason -Sev 'Warning' -API 'NewTenant'
            Write-Information 'Adding CPV permissions'
            Set-CIPPCPVConsent -Tenantfilter $Item.customerId -ResetSP $ResetSP
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

            # Failed re-consent counter drives the reset escalation; cleared on success.
            if ($Status -eq 'Success') {
                $GraphRequest.ConsentAttempts = '0'
            } elseif ($ConsentAttempted) {
                $GraphRequest.ConsentAttempts = "$($Attempts + 1)"
            } elseif ($ConsentRow.ConsentAttempts) {
                $GraphRequest.ConsentAttempts = "$($ConsentRow.ConsentAttempts)"
            }
            # The row is replaced, not merged - carry these forward or the weekly limit re-arms.
            if ($ResetSP) { $GraphRequest.LastResetUtc = ([datetime]::UtcNow.ToString('o')) }
            elseif ($ConsentRow.LastResetUtc) { $GraphRequest.LastResetUtc = "$($ConsentRow.LastResetUtc)" }

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
