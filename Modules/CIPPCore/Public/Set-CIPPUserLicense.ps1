function Set-CIPPUserLicense {
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName = 'Single', Mandatory)][string]$UserId,
        [Parameter(ParameterSetName = 'Single')][string]$UserPrincipalName,
        [Parameter(ParameterSetName = 'Single')][array]$AddLicenses = @(),
        [Parameter(ParameterSetName = 'Single')][array]$RemoveLicenses = @(),
        [Parameter(ParameterSetName = 'Bulk', Mandatory)][System.Collections.Generic.List[object]]$LicenseRequests,
        [Parameter(Mandatory)][string]$TenantFilter,
        $Headers,
        $APIName = 'Set User License'
    )

    # Handle single user request (legacy support)
    if ($PSCmdlet.ParameterSetName -eq 'Single') {
        $LicenseRequests = [System.Collections.Generic.List[object]]::new()
        $LicenseRequests.Add([PSCustomObject]@{
                UserId            = $UserId
                UserPrincipalName = $UserPrincipalName
                AddLicenses       = @($AddLicenses)
                RemoveLicenses    = @($RemoveLicenses)
                IsReplace         = $false
            })
    }

    $Results = [System.Collections.Generic.List[string]]::new()

    # Get default usage location once for all users
    $Table = Get-CippTable -tablename 'UserSettings'
    $UserSettings = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UserSettings' and RowKey eq 'allUsers'"
    if ($UserSettings) { $DefaultUsageLocation = (ConvertFrom-Json $UserSettings.JSON -Depth 5 -ErrorAction SilentlyContinue).usageLocation.value }
    $DefaultUsageLocation ??= 'US'

    # Normalize license arrays to avoid sending null skuIds to Graph
    foreach ($Request in $LicenseRequests) {
        $Request.AddLicenses = @(
            @($Request.AddLicenses) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        $Request.RemoveLicenses = @(
            @($Request.RemoveLicenses) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if ([string]::IsNullOrWhiteSpace($Request.UserPrincipalName)) {
            $Request.UserPrincipalName = $Request.UserId
        }
    }

    # Process Replace operations first (remove all licenses)
    $ReplaceRequests = $LicenseRequests | Where-Object { $_.IsReplace -and $_.RemoveLicenses.Count -gt 0 }
    if ($ReplaceRequests.Count -gt 0) {
        $RemoveBulkRequests = foreach ($Request in $ReplaceRequests) {
            @{
                id      = $Request.UserId
                method  = 'POST'
                url     = "/users/$($Request.UserId)/assignLicense"
                body    = @{
                    'addLicenses'    = @()
                    'removeLicenses' = $Request.RemoveLicenses
                }
                headers = @{ 'Content-Type' = 'application/json' }
            }
        }

        $RemoveResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($RemoveBulkRequests)

        foreach ($Result in $RemoveResults) {
            $Request = $ReplaceRequests | Where-Object { $_.UserId -eq $Result.id }
            if ($Result.status -ge 200 -and $Result.status -le 299) {
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Removed existing licenses for user $($Request.UserPrincipalName)" -Sev 'Info'
            } else {
                $Results.Add("Failed to remove licenses for user $($Request.UserPrincipalName): $($Result.body.error.message)")
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove licenses for user $($Request.UserPrincipalName): $($Result.body.error.message)" -Sev 'Error'
            }
        }
    }

    # Build bulk requests for license assignment
    $BulkRequests = foreach ($Request in $LicenseRequests) {
        $AddLicensesArray = foreach ($license in $Request.AddLicenses) {
            @{ 'disabledPlans' = @(); 'skuId' = $license }
        }

        @{
            id      = $Request.UserId
            method  = 'POST'
            url     = "/users/$($Request.UserId)/assignLicense"
            body    = @{
                'addLicenses'    = @($AddLicensesArray)
                'removeLicenses' = $Request.IsReplace ? @() : $Request.RemoveLicenses
            }
            headers = @{ 'Content-Type' = 'application/json' }
        }
    }

    # Execute bulk request
    $BulkResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests)

    # Collect users with usage location errors
    $UsageLocationErrors = [System.Collections.Generic.List[object]]::new()

    foreach ($Result in $BulkResults) {
        $Request = $LicenseRequests | Where-Object { $_.UserId -eq $Result.id }

        if ($Result.status -ge 200 -and $Result.status -le 299) {
            $Results.Add("Successfully set licenses for $($Request.UserPrincipalName). It may take 2–5 minutes before the changes become visible.")
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned licenses to user $($Request.UserPrincipalName). Added: $($Request.AddLicenses -join ', '); Removed: $($Request.RemoveLicenses -join ', ')" -Sev 'Info'
        } elseif ($Result.body.error.message -like '*invalid usage location*' -or $Result.body.error.message -like '*UsageLocation*') {
            $UsageLocationErrors.Add($Request)
        } else {
            $Results.Add("Failed to assign licenses for user $($Request.UserPrincipalName): $($Result.body.error.message)")
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to assign licenses for user $($Request.UserPrincipalName): $($Result.body.error.message)" -Sev 'Error'
        }
    }

    # Handle usage location errors
    if ($UsageLocationErrors.Count -gt 0) {
        # Set usage location for all users with errors
        $UsageLocationRequests = foreach ($Request in $UsageLocationErrors) {
            @{
                id      = $Request.UserId
                method  = 'PATCH'
                url     = "/users/$($Request.UserId)"
                body    = @{ 'usageLocation' = $DefaultUsageLocation }
                headers = @{ 'Content-Type' = 'application/json' }
            }
        }

        $UsageLocationResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($UsageLocationRequests)

        # Log usage location updates
        foreach ($Result in $UsageLocationResults) {
            $Request = $UsageLocationErrors | Where-Object { $_.UserId -eq $Result.id }
            if ($Result.status -ge 200 -and $Result.status -le 299) {
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Set usage location for user $($Request.UserPrincipalName) to $DefaultUsageLocation" -Sev 'Info'
            }
        }

        # Retry license assignment for users with fixed usage location
        $RetryBulkRequests = foreach ($Request in $UsageLocationErrors) {
            $AddLicensesArray = foreach ($license in $Request.AddLicenses) {
                @{ 'disabledPlans' = @(); 'skuId' = $license }
            }

            @{
                id      = $Request.UserId
                method  = 'POST'
                url     = "/users/$($Request.UserId)/assignLicense"
                body    = @{
                    'addLicenses'    = @($AddLicensesArray)
                    'removeLicenses' = $Request.IsReplace ? @() : $Request.RemoveLicenses
                }
                headers = @{ 'Content-Type' = 'application/json' }
            }
        }

        $RetryResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($RetryBulkRequests)

        foreach ($Result in $RetryResults) {
            $Request = $UsageLocationErrors | Where-Object { $_.UserId -eq $Result.id }

            if ($Result.status -ge 200 -and $Result.status -le 299) {
                $Results.Add("Successfully set licenses for $($Request.UserPrincipalName) after setting usage location. It may take 2–5 minutes before the changes become visible.")
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Assigned licenses to user $($Request.UserPrincipalName) after usage location fix. Added: $($Request.AddLicenses -join ', '); Removed: $($Request.RemoveLicenses -join ', ')" -Sev 'Info'
            } else {
                $Results.Add("Failed to assign licenses for user $($Request.UserPrincipalName) after setting usage location: $($Result.body.error.message)")
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to assign licenses for user $($Request.UserPrincipalName) after usage location fix: $($Result.body.error.message)" -Sev 'Error'
            }
        }
    }

    # Return single result for legacy support, or all results for bulk
    if ($PSCmdlet.ParameterSetName -eq 'Single') {
        return $Results[0]
    } else {
        return $Results
    }
}
