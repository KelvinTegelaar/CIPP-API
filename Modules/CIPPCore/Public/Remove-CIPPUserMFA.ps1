function Remove-CIPPUserMFA {
    <#
    .SYNOPSIS
    Remove MFA methods for a user

    .DESCRIPTION
    Remove MFA methods for a user using individual requests to the Microsoft Graph API

    .PARAMETER UserPrincipalName
    UserPrincipalName of the user to remove MFA methods for

    .PARAMETER TenantFilter
    Tenant where the user resides

    .EXAMPLE
    Remove-CIPPUserMFA -UserPrincipalName testuser@contoso.com -TenantFilter contoso.com

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
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

    $RemovableMethods = $AuthMethods | Where-Object { $_.'@odata.type' -and $_.'@odata.type' -ne '#microsoft.graph.passwordAuthenticationMethod' }

    if (($RemovableMethods | Measure-Object).Count -eq 0) {
        $Results = "No MFA methods found for user $UserPrincipalName"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev 'Info'
        return $Results
    }

    if ($PSCmdlet.ShouldProcess("Remove MFA methods for $UserPrincipalName")) {
        $Failed = [System.Collections.Generic.List[string]]::new()
        $Succeeded = [System.Collections.Generic.List[string]]::new()
        foreach ($Method in $RemovableMethods) {
            $MethodType = ($Method.'@odata.type' -split '\.')[-1] -replace 'Authentication', ''
            switch ($MethodType) {
                'qrCodePinMethod' {
                    $Uri = 'https://graph.microsoft.com/beta/users/{0}/authentication/{1}' -f $UserPrincipalName, $MethodType
                    break
                }
                default {
                    $Uri = 'https://graph.microsoft.com/v1.0/users/{0}/authentication/{1}s/{2}' -f $UserPrincipalName, $MethodType, $Method.id
                }
            }
            try {
                $null = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -type DELETE -AsApp $true
                $Succeeded.Add($MethodType)
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove $MethodType for $UserPrincipalName. Error: $($ErrorMessage.NormalizedError)" -sev 'Error' -LogData $ErrorMessage
                $Failed.Add($MethodType)
            }
        }

        if ($Failed.Count -gt 0) {
            $Message = if ($Succeeded.Count -gt 0) {
                "Successfully removed MFA methods ($($Succeeded -join ', ')) for user $UserPrincipalName. However, failed to remove ($($Failed -join ', ')). User may still have MFA methods assigned."
            } else {
                "Failed to remove MFA methods ($($Failed -join ', ')) for user $UserPrincipalName"
            }
            throw $Message
        }

        $Message = "Successfully removed MFA methods ($($Succeeded -join ', ')) for user $UserPrincipalName. User must supply MFA at next logon"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev 'Info'
        return $Message
    }
}
