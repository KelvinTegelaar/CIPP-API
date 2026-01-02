function Invoke-CippTestZTNA21868 {
    <#
    .SYNOPSIS
    Guests do not own apps in the tenant
    #>
    param($Tenant)

    try {
        $Guests = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Guests'
        $Apps = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Apps'
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'

        if (-not $Guests -or -not $Apps -or -not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21868' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Guests do not own apps in the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
            return
        }

        # Create a HashSet of guest user IDs for fast lookups
        $GuestUserIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($guest in $Guests) {
            [void]$GuestUserIds.Add($guest.id)
        }

        # Initialize lists for guest owners
        $GuestAppOwners = [System.Collections.Generic.List[object]]::new()
        $GuestSpOwners = [System.Collections.Generic.List[object]]::new()

        # Check applications for guest owners
        foreach ($app in $Apps) {
            if ($app.owners -and $app.owners.Count -gt 0) {
                foreach ($owner in $app.owners) {
                    if ($GuestUserIds.Contains($owner.id)) {
                        $ownerInfo = [PSCustomObject]@{
                            id                = $owner.id
                            displayName       = $owner.displayName
                            userPrincipalName = $owner.userPrincipalName
                            appDisplayName    = $app.displayName
                            appObjectId       = $app.id
                            appId             = $app.appId
                        }
                        $GuestAppOwners.Add($ownerInfo)
                    }
                }
            }
        }

        # Check service principals for guest owners
        foreach ($sp in $ServicePrincipals) {
            if ($sp.owners -and $sp.owners.Count -gt 0) {
                foreach ($owner in $sp.owners) {
                    if ($GuestUserIds.Contains($owner.id)) {
                        $ownerInfo = [PSCustomObject]@{
                            id                = $owner.id
                            displayName       = $owner.displayName
                            userPrincipalName = $owner.userPrincipalName
                            spDisplayName     = $sp.displayName
                            spObjectId        = $sp.id
                            spAppId           = $sp.appId
                        }
                        $GuestSpOwners.Add($ownerInfo)
                    }
                }
            }
        }

        $HasGuestAppOwners = $GuestAppOwners.Count -gt 0
        $HasGuestSpOwners = $GuestSpOwners.Count -gt 0

        if ($HasGuestAppOwners -or $HasGuestSpOwners) {
            $Status = 'Failed'
            $Result = "Guest users own applications or service principals`n`n"

            if ($HasGuestAppOwners -and $HasGuestSpOwners) {
                $Result += "## Guest users own both applications and service principals`n`n"
                $Result += "### Applications owned by guest users`n`n"
                $Result += "| User Display Name | User Principal Name | Application |`n"
                $Result += "| :---------------- | :------------------ | :---------- |`n"
                $Result += ($GuestAppOwners | ForEach-Object { "| $($_.displayName) | $($_.userPrincipalName) | $($_.appDisplayName) |" }) -join "`n"
                $Result += "`n`n### Service principals owned by guest users`n`n"
                $Result += "| User Display Name | User Principal Name | Service Principal |`n"
                $Result += "| :---------------- | :------------------ | :---------------- |`n"
                $Result += ($GuestSpOwners | ForEach-Object { "| $($_.displayName) | $($_.userPrincipalName) | $($_.spDisplayName) |" }) -join "`n"
            } elseif ($HasGuestAppOwners) {
                $Result += "## Guest users own applications`n`n"
                $Result += "| User Display Name | User Principal Name | Application |`n"
                $Result += "| :---------------- | :------------------ | :---------- |`n"
                $Result += ($GuestAppOwners | ForEach-Object { "| $($_.displayName) | $($_.userPrincipalName) | $($_.appDisplayName) |" }) -join "`n"
            } elseif ($HasGuestSpOwners) {
                $Result += "## Guest users own service principals`n`n"
                $Result += "| User Display Name | User Principal Name | Service Principal |`n"
                $Result += "| :---------------- | :------------------ | :---------------- |`n"
                $Result += ($GuestSpOwners | ForEach-Object { "| $($_.displayName) | $($_.userPrincipalName) | $($_.spDisplayName) |" }) -join "`n"
            }
        } else {
            $Status = 'Passed'
            $Result = 'No guest users own any applications or service principals in the tenant'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21868' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Guests do not own apps in the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21868' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guests do not own apps in the tenant' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'External collaboration'
    }
}
