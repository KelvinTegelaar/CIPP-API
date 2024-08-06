function Get-CIPPAlertMFAAlertUsers {
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

        $users = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/reports/authenticationMethods/userRegistrationDetails?$top=999&filter=isMfaRegistered eq false and userType eq ''member''&$select=userPrincipalName,lastUpdatedDateTime,isMfaRegistered' -tenantid $($TenantFilter)
        if ($users.UserPrincipalName) {
            $AlertData = "The following $($users.Count) users do not have MFA registered: $($users.UserPrincipalName -join ', ')"
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

        }

    } catch {
        Write-LogMessage -message "Failed to check MFA status for all users: $($_.exception.message)" -API 'MFA Alerts - Informational' -tenant $TenantFilter -sev Info
    }

}
