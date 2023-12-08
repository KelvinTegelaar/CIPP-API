function Invoke-DisableGuestDirectory {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    If ($Settings.Remediate) {
        

        try {
            $body = '{guestUserRoleId: "2af84b1e-32c8-42b7-82bc-daa82404023b"}'
    (New-GraphPostRequest -tenantid $tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Type patch -Body $body -ContentType 'application/json')

            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Disabled Guest access to directory information.' -sev Info
        } catch {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to disable Guest access to directory information.: $($_.exception.message)" -sev 'Error'
        }
    }
    
    if ($Settings.Alert) {
        $CurrentInfo = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -tenantid $Tenant
        if ($CurrentInfo.guestUserRoleId -eq '2af84b1e-32c8-42b7-82bc-daa82404023b') {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guest access to directory information is disabled.' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Guest access to directory information is not disabled.' -sev Alert
        }
    }
}
