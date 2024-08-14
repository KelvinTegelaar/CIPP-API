function Set-CIPPUserLicense {
    [CmdletBinding()]
    param (
        $userid,
        $TenantFilter,
        $Licenses
    )

    Write-Host "Lics are: $licences"
    $LicenseBody = if ($licenses.count -ge 2) {
        $liclist = foreach ($license in $Licenses) { '{"disabledPlans": [],"skuId": "' + $license + '" },' }
        '{"addLicenses": [' + $LicList + '], "removeLicenses": [ ] }'
    } else {
        '{"addLicenses": [ {"disabledPlans": [],"skuId": "' + $licenses + '" }],"removeLicenses": [ ]}'
    }
    Write-Host $LicenseBody
    try {
        $LicRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserId)/assignlicense" -tenantid $TenantFilter -type POST -body $LicenseBody -verbose
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($UserObj.tenantid) -message "Failed to assign the license. Error:$($_.Exception.Message)" -Sev 'Error'
        throw "Failed to assign the license. $($_.Exception.Message)"
    }
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($UserObj.tenantid) -message "Assigned user $($UserObj.DisplayName) license $($licences)" -Sev 'Info'
    return 'Assigned licenses.'
}
