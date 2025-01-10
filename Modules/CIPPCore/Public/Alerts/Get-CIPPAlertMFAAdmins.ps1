function Get-CIPPAlertMFAAdmins {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $CAPolicies = (New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$top=999' -tenantid $TenantFilter -ErrorAction Stop)
        foreach ($Policy in $CAPolicies) {
            if ($policy.grantControls.customAuthenticationFactors -eq 'RequireDuoMfa') {
                $DuoActive = $true
            }
        }
        if (!$DuoActive) {
            $users = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?$top=999&$filter=IsAdmin eq true and userDisplayName ne ''On-Premises Directory Synchronization Service Account''' -tenantid $($TenantFilter) | Where-Object -Property 'isMfaRegistered' -EQ $false
            if ($users.UserPrincipalName) {
                $AlertData = "The following admins do not have MFA registered: $($users.UserPrincipalName -join ', ')"
                Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

            }
        } else {
            Write-LogMessage -message 'Potentially using Duo for MFA, could not check MFA status for Admins with 100% accuracy' -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Info
        }
    } catch {
        Write-LogMessage -message "Failed to check MFA status for Admins: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Error
    }
}
