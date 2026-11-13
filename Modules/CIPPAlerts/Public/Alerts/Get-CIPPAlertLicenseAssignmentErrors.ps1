function Get-CIPPAlertLicenseAssignmentErrors {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        $TenantFilter,
        [Alias('input')]
        $InputValue
    )

    # Define error code translations for human-readable messages
    $ErrorTranslations = @(
        @{
            ErrorCode   = 'CountViolation'
            Description = 'Not enough licenses available - the organization has exceeded the number of available licenses for this SKU'
        },
        @{
            ErrorCode   = 'MutuallyExclusiveViolation'
            Description = 'Conflicting licenses assigned - this license cannot be assigned alongside another license the user already has'
        },
        @{
            ErrorCode   = 'ProhibitedInUsageLocationViolation'
            Description = "License not available in user's location - this license cannot be assigned to users in the user's current usage location"
        },
        @{
            ErrorCode   = 'UniquenessViolation'
            Description = 'Duplicate license assignment - this license can only be assigned once per user'
        },
        @{
            ErrorCode   = 'DependencyViolation'
            Description = 'Missing dependency - this license or one of its service plans requires another license or service plan that is not assigned'
        },
        @{
            ErrorCode   = 'Other'
            Description = 'Unknown license assignment error - an unspecified error occurred during license assignment'
        }
    )

    try {
        # Get all users with license assignment states from Graph API
        $Users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,licenseAssignmentStates&`$top=999" -tenantid $TenantFilter

        # Build alert messages for users with violations
        $LicenseAssignmentErrors = foreach ($User in $Users) {
            # A healthy assignment has error null or 'None'; anything else is a failure, whatever the code.
            $ViolationErrors = $User.licenseAssignmentStates | Where-Object { $_.error -and $_.error -ne 'None' }

            foreach ($Violation in $ViolationErrors) {
                # Find matching error translation
                $ErrorTranslation = $ErrorTranslations | Where-Object { $Violation.error -like "*$($_.ErrorCode)*" } | Select-Object -First 1
                $HumanReadableError = if ($ErrorTranslation) {
                    $ErrorTranslation.Description
                } else {
                    "Unknown license assignment error: $($Violation.error)"
                }

                $PrettyName = (Get-CIPPLicenseSkuName -SkuIds @($Violation.skuId) -TenantFilter $TenantFilter).displayName ?? $Violation.skuId

                $Message = "$($User.userPrincipalName): $HumanReadableError (License: $PrettyName)"
                [PSCustomObject]@{
                    Message           = $Message
                    UserPrincipalName = $User.userPrincipalName
                    Error             = $HumanReadableError
                    LicenseName       = $PrettyName
                    SkuId             = $Violation.skuId
                    DisplayName       = $User.displayName
                    Id                = $User.id
                    Tenant            = $TenantFilter
                }
            }
        }

        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $LicenseAssignmentErrors

    } catch {
        Write-LogMessage -message "Failed to check license assignment errors: $($_.exception.message)" -API 'License Assignment Alerts' -tenant $TenantFilter -sev Error
    }
}
