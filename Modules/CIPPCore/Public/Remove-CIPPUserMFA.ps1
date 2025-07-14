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
        $Headers,
        [Parameter(Mandatory = $false)]
        $APIName = 'Remove MFA Methods'
    )

    Write-Information "Getting auth methods for $UserPrincipalName"
    try {
        $AuthMethods = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UserPrincipalName/authentication/methods" -tenantid $TenantFilter -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to get MFA methods for user $UserPrincipalName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev 'Error' -LogData $ErrorMessage
        throw $Message
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
        $Results = "No MFA methods found for user $UserPrincipalName"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev 'Info'
        return $Results
    } else {
        if ($PSCmdlet.ShouldProcess("Remove MFA methods for $UserPrincipalName")) {
            try {
                $Results = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true -ErrorAction Stop
                if ($Results.status -eq 204) {
                    $Message = "Successfully removed MFA methods for user $UserPrincipalName. User must supply MFA at next logon"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev 'Info'
                    return $Message
                } else {
                    $FailedAuthMethods = (($Results | Where-Object { $_.status -ne 204 }).id -split '-')[0] -join ', '
                    $Message = "Failed to remove MFA methods for $FailedAuthMethods on user $UserPrincipalName"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev 'Error'
                    throw $Message
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Message = "Failed to remove MFA methods for user $UserPrincipalName. Error: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev 'Error' -LogData $ErrorMessage
                throw $Message
            }
        }
    }
}
