function Remove-CIPPUserMFA {
    <#
    .SYNOPSIS
    Remove MFA methods for a user

    .DESCRIPTION
    Remove MFA methods for a user using bulk requests to the Microsoft Graph API

    .PARAMETER UserPrincipalName
    UserPrincipalName of the user to remove MFA methods for

    .PARAMETER TenantFilter
    Tenant where the user resides

    .EXAMPLE
    Remove-CIPPUserMFA -UserPrincipalName testuser@contoso.com -TenantFilter contoso.com

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$UserPrincipalName,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $false)]
        [string]$ExecutingUser = 'CIPP'
    )

    Write-Information "Getting auth methods for $UserPrincipalName"
    try {
        $AuthMethods = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UserPrincipalName/authentication/methods" -tenantid $TenantFilter -AsApp $true
    } catch {
        Write-LogMessage -API 'Remove-CIPPUserMFA' -tenant $TenantFilter -message "Failed to get MFA methods for user $UserPrincipalName" -sev 'Error' -LogData (Get-CippException -Exception $_)
        return "Failed to get MFA methods for user $UserPrincipalName - $($_.Exception.Message)"
    }
    $Requests = [System.Collections.Generic.List[object]]::new()
    foreach ($Method in $AuthMethods) {
        if ($Method.'@odata.type' -and $Method.'@odata.type' -ne '#microsoft.graph.passwordAuthenticationMethod') {
            $MethodType = ($Method.'@odata.type' -split '\.')[-1] -replace 'Authentication', ''
            $Requests.Add(@{
                    id     = "$MethodType-$($Method.id)"
                    method = 'DELETE'
                    url    = ('users/{0}/authentication/{1}s/{2}' -f $UserPrincipalName, $MethodType, $Method.id)
                })
        }
    }
    if (($Requests | Measure-Object).Count -eq 0) {
        Write-LogMessage -API 'Remove-CIPPUserMFA' -tenant $TenantFilter -message "No MFA methods found for user $UserPrincipalName" -sev 'Info'
        $Results = "No MFA methods found for user $($UserPrincipalName)"
    } else {
        if ($PSCmdlet.ShouldProcess("Remove MFA methods for $UserPrincipalName")) {
            $Results = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true -erroraction stop
            if ($Results.status -eq 204) {
                Write-LogMessage -API 'Remove-CIPPUserMFA' -tenant $TenantFilter -message "Successfully removed MFA methods for user $UserPrincipalName" -sev 'Info'
                $Results = [pscustomobject]@{'Results' = "Successfully completed request. User $($Request.Query.ID) must supply MFA at next logon" }
            } else {
                $FailedAuthMethods = (($Results | Where-Object { $_.status -ne 204 }).id -split '-')[0] -join ', '
                Write-LogMessage -API 'Remove-CIPPUserMFA' -tenant $TenantFilter -message "Failed to remove MFA methods for $FailedAuthMethods" -sev 'Error'
                $Results = "Failed to reset MFA methods for $FailedAuthMethods"
            }
        }
    }

    return $Results
}
