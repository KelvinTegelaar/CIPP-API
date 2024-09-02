function Get-CIPPAlertInactiveLicensedUsers {
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
        try {

            $Lookup = (Get-Date).AddDays(-90).ToUniversalTime().ToString('o')
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$filter=(signInActivity/lastNonInteractiveSignInDateTime le $Lookup)&`$select=id,UserPrincipalName,signInActivity,mail,userType,accountEnabled,assignedLicenses" -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter | Where-Object { $_.assignedLicenses.skuId -ne $null }
            $AlertData = foreach ($user in $GraphRequest) {
                $Message = 'User {0} has been inactive for 90 days, but still has a license assigned.' -f $user.UserPrincipalName
                $user | Select-Object -Property userPrincipalname, signInActivity, @{Name = 'Message'; Expression = { $Message } }

            }
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

        } catch {}


    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check inactive users with licenses for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}
