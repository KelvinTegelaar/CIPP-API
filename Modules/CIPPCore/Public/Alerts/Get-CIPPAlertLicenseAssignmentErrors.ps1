function Get-CIPPAlertLicenseAssignmentErrors {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        $TenantFilter,
        [Alias('input')]
        $InputValue
    )

    # Define error code translations for human-readable messages
    $ErrorTranslations = @(
        @{
            ErrorCode = "CountViolation"
            Description = "Not enough licenses available - the organization has exceeded the number of available licenses for this SKU"
        },
        @{
            ErrorCode = "MutuallyExclusiveViolation"
            Description = "Conflicting licenses assigned - this license cannot be assigned alongside another license the user already has"
        },
        @{
            ErrorCode = "ProhibitedInUsageLocationViolation"
            Description = "License not available in user's location - this license cannot be assigned to users in the user's current usage location"
        },
        @{
            ErrorCode = "UniquenessViolation"
            Description = "Duplicate license assignment - this license can only be assigned once per user"
        },
        @{
            ErrorCode = "Unknown"
            Description = "Unknown license assignment error - an unspecified error occurred during license assignment"
        }
    )

    try {
        # Get all users with license assignment states from Graph API
        $Users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,displayName,licenseAssignmentStates&`$top=999" -tenantid $TenantFilter

        # Filter users who have license assignment violations
        $UsersWithViolations = $Users | Where-Object {
            $_.licenseAssignmentStates -and
            ($_.licenseAssignmentStates | Where-Object {
                $_.error -and (
                    $_.error -like "*CountViolation*" -or
                    $_.error -like "*MutuallyExclusiveViolation*" -or
                    $_.error -like "*ProhibitedInUsageLocationViolation*" -or
                    $_.error -like "*UniquenessViolation*" -or
                    $_.error -like "*Unknown*"
                )
            })
        }

        # Build alert messages for users with violations
        $LicenseAssignmentErrors = foreach ($User in $UsersWithViolations) {
            $ViolationErrors = $User.licenseAssignmentStates | Where-Object {
                $_.error -and (
                    $_.error -like "*CountViolation*" -or
                    $_.error -like "*MutuallyExclusiveViolation*" -or
                    $_.error -like "*ProhibitedInUsageLocationViolation*" -or
                    $_.error -like "*UniquenessViolation*" -or
                    $_.error -like "*Unknown*"
                )
            }

            foreach ($Violation in $ViolationErrors) {
                # Find matching error translation
                $ErrorTranslation = $ErrorTranslations | Where-Object { $Violation.error -like "*$($_.ErrorCode)*" } | Select-Object -First 1
                $HumanReadableError = if ($ErrorTranslation) {
                    $ErrorTranslation.Description
                } else {
                    "Unknown license assignment error: $($Violation.error)"
                }

                $PrettyName = Convert-SKUname -skuID $Violation.skuId

                "$($User.userPrincipalName): $HumanReadableError (License: $PrettyName)"
            }
        }

        # If errors are found, write alert
        if ($LicenseAssignmentErrors) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $LicenseAssignmentErrors
        }

    } catch {
        Write-LogMessage -message "Failed to check license assignment errors: $($_.exception.message)" -API 'License Assignment Alerts' -tenant $TenantFilter -sev Error
    }
}
