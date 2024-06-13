function Invoke-CIPPStandardPerUserMFA {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)

    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$top=999&`$select=UserPrincipalName,accountEnabled" -scope 'https://graph.microsoft.com/.default' -tenantid $Tenant | Where-Object { $_.AccountEnabled -EQ $true }
    $int = 0    
    $Requests = foreach ($id in $GraphRequest.userPrincipalName) {
        @{
            id     = $int++
            method = 'GET'
            url    = "/users/$id/authentication/requirements"
        }
    }
    $UsersWithoutMFA = (New-GraphBulkRequest -tenantid $tenant -scope 'https://graph.microsoft.com/.default' -Requests @($Requests) -asapp $true).body | Where-Object { $_.perUserMfaState -ne 'enforced' } | Select-Object peruserMFAState, @{Name = 'UserPrincipalName'; Expression = { [System.Web.HttpUtility]::UrlDecode($_.'@odata.context'.split("'")[1]) } }
    If ($Settings.remediate -eq $true) {
        if ($UsersWithoutMFA) {
            try {
                $MFAMessage = Set-CIPPPeruserMFA -TenantFilter $Tenant -UserId $GraphRequest.UserPrincipalName -State 'Enforced'
                Write-LogMessage -API 'Standards' -tenant $tenant -message $MFAMessage -sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enforce MFA for all users: $ErrorMessage" -sev Error
            }
        }
    }
    if ($Settings.alert -eq $true) {

        if ($GraphRequest) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Guests accounts with a login longer than 90 days ago: $($GraphRequest.count)" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'No guests accounts with a login longer than 90 days ago.' -sev Info
        }
    }
    if ($Settings.report -eq $true) {
        $filtered = $GraphRequest | Select-Object -Property UserPrincipalName, id, signInActivity, mail, userType, accountEnabled
        Add-CIPPBPAField -FieldName 'DisableGuests' -FieldValue $filtered -StoreAs json -Tenant $tenant
    }
}
