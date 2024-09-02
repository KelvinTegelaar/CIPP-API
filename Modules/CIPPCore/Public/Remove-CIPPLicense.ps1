function Remove-CIPPLicense {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = 'Remove License',
        $TenantFilter
    )

    try {
        $ConvertTable = Import-Csv ConversionTable.csv
        $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -tenantid $tenantFilter
        if (!$username) { $username = $User.userPrincipalName }
        $CurrentLicenses = $User.assignedlicenses.skuid
        $ConvertedLicense = $(($ConvertTable | Where-Object { $_.guid -in $CurrentLicenses }).'Product_Display_Name' | Sort-Object -Unique) -join ', '
        if ($CurrentLicenses) {
            $LicensePayload = [PSCustomObject]@{
                addLicenses    = @()
                removeLicenses = @($CurrentLicenses)
            }
            if ($PSCmdlet.ShouldProcess($userid, "Remove licenses: $ConvertedLicense")) {
                $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/assignlicense" -tenantid $tenantFilter -type POST -body (ConvertTo-Json -InputObject $LicensePayload -Compress -Depth 5) -verbose
                Write-LogMessage -user $ExecutingUser -API $APIName -message "Removed licenses for $($username): $ConvertedLicense" -Sev 'Info' -tenant $TenantFilter
            }
            return "Removed licenses for $($Username): $ConvertedLicense"
        } else {
            Write-LogMessage -user $ExecutingUser -API $APIName -message "No licenses to remove for $username" -Sev 'Info' -tenant $TenantFilter
            return "No licenses to remove for $username"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not remove license for $username. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Could not remove license for $($username). Error: $($ErrorMessage.NormalizedError)"
    }
}
