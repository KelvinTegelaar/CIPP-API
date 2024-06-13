function Get-CIPPPerUserMFA {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $userId,
        $executingUser,
        $AllUsers = $false
    )
    try {
        if ($AllUsers -eq $true) {
            $AllUsers = New-graphGetRequest -Uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=UserPrincipalName,Id" -tenantid $tenantfilter
            $Requests = foreach ($id in $AllUsers.userPrincipalName) {
                @{
                    id     = $int++
                    method = 'GET'
                    url    = "users/$id/authentication/requirements"
                }
            }
            $Requests = New-GraphBulkRequest -tenantid $tenantfilter -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true
            if ($Requests.body) {
                $UsersWithoutMFA = $Requests.body | Select-Object peruserMFAState, @{Name = 'UserPrincipalName'; Expression = { [System.Web.HttpUtility]::UrlDecode($_.'@odata.context'.split("'")[1]) } }
                return $UsersWithoutMFA
            }
        } else {
            $MFAState = New-graphGetRequest -Uri "https://graph.microsoft.com/beta/users/$($userId)/authentication/requirements" -tenantid $tenantfilter
            return [PSCustomObject]@{
                PerUserMFAState   = $MFAState.perUserMfaState
                UserPrincipalName = $userId
            }
        }
    } catch {
        "Failed to get MFA State for $id : $_"
    }
}