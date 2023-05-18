param($tenant)

try {
    $body = '{guestUserRoleId: "2af84b1e-32c8-42b7-82bc-daa82404023b"}'
    (New-GraphPostRequest -tenantid $tenant -Uri "https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy" -Type patch -Body $body -ContentType "application/json")

    Write-LogMessage -API "Standards" -tenant $tenant -message "Disabled Guest access to directory information." -sev Info
}
catch {
    Write-LogMessage -API "Standards" -tenant $tenant -message  "Failed to disable Guest access to directory information.: $($_.exception.message)"
}
