Function Invoke-ListInactiveAccounts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'ListInactiveAccounts'
    $TenantFilter = $Request.Query.tenantFilter
    $InactiveDays = if ($Request.Query.InactiveDays) { [int]$Request.Query.InactiveDays } else { 180 }

    try {
        $Lookup = (Get-Date).AddDays(-$InactiveDays).ToUniversalTime()

        if ($TenantFilter -eq 'AllTenants') {
            # Get all tenants that have user data
            $AllUserItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Users'
            $Tenants = @($AllUserItems | Where-Object { $_.RowKey -ne 'Users-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()

            foreach ($Tenant in $Tenants) {
                try {
                    Write-Information "Processing tenant: $Tenant"
                    $TenantResults = Get-InactiveUsersFromDB -TenantFilter $Tenant -InactiveDays $InactiveDays -Lookup $Lookup

                    foreach ($Result in $TenantResults) {
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "Failed to get inactive users: $($_.Exception.Message)" -sev Warning
                }
            }

            $GraphRequest = @($AllResults)
        } else {
            $GraphRequest = Get-InactiveUsersFromDB -TenantFilter $TenantFilter -InactiveDays $InactiveDays -Lookup $Lookup
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to retrieve inactive accounts: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}

# Helper function to get inactive users from the database for a specific tenant
function Get-InactiveUsersFromDB {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [int]$InactiveDays,

        [Parameter(Mandatory = $true)]
        [DateTime]$Lookup
    )

    # Get users from database
    $Users = New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users'

    if (-not $Users) {
        Write-Information "No user data found in database for tenant $TenantFilter"
        return @()
    }

    # Get tenant info for display name
    $TenantInfo = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
    $TenantDisplayName = $TenantInfo.displayName ?? $TenantFilter

    $InactiveUsers = foreach ($User in $Users) {
        # Skip disabled users by default
        if ($User.accountEnabled -eq $false) { continue }

        # Skip guest users
        if ($User.userType -eq 'Guest') { continue }

        # Determine last sign-in
        $lastInteractive = $User.signInActivity.lastSignInDateTime
        $lastNonInteractive = $User.signInActivity.lastNonInteractiveSignInDateTime

        $lastSignIn = $null
        if ($lastInteractive -and $lastNonInteractive) {
            $lastSignIn = if ([DateTime]$lastInteractive -gt [DateTime]$lastNonInteractive) {
                $lastInteractive
            } else {
                $lastNonInteractive
            }
        } elseif ($lastInteractive) {
            $lastSignIn = $lastInteractive
        } elseif ($lastNonInteractive) {
            $lastSignIn = $lastNonInteractive
        }

        # Check if user is inactive
        $isInactive = (-not $lastSignIn) -or ([DateTime]$lastSignIn -le $Lookup)

        if ($isInactive) {
            # Calculate days since last sign-in
            $daysSinceSignIn = if ($lastSignIn) {
                [Math]::Round(((Get-Date) - [DateTime]$lastSignIn).TotalDays)
            } else {
                $null
            }

            # Count assigned licenses
            $numberOfAssignedLicenses = if ($User.assignedLicenses) {
                $User.assignedLicenses.Count
            } else {
                0
            }

            [PSCustomObject]@{
                tenantId                         = $TenantFilter
                tenantDisplayName                = $TenantDisplayName
                azureAdUserId                    = $User.id
                userPrincipalName                = $User.userPrincipalName
                displayName                      = $User.displayName
                userType                         = $User.userType
                createdDateTime                  = $User.createdDateTime
                lastSignInDateTime               = $lastInteractive
                lastNonInteractiveSignInDateTime = $lastNonInteractive
                lastRefreshedDateTime            = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                numberOfAssignedLicenses         = $numberOfAssignedLicenses
                daysSinceLastSignIn              = $daysSinceSignIn
                accountEnabled                   = $User.accountEnabled
            }
        }
    }

    return @($InactiveUsers)
}
