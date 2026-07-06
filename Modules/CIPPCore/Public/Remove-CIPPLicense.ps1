function Remove-CIPPLicense {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        $Headers,
        $userid,
        $username,
        $APIName = 'Remove License',
        $TenantFilter,
        [switch]$Schedule
    )

    if ($Schedule.IsPresent) {
        $ScheduledTask = @{
            TenantFilter  = $TenantFilter
            Name          = "Remove License: $Username"
            Command       = @{
                value = 'Remove-CIPPLicense'
            }
            Parameters    = [pscustomobject]@{
                userid   = $userid
                username = $username
                APIName  = 'Scheduled License Removal'
                Headers  = $Headers
            }
            ScheduledTime = [int64](([datetime]::UtcNow).AddMinutes(5) - (Get-Date '1/1/1970')).TotalSeconds
            PostExecution = @{
                Webhook = $false
                Email   = $false
                PSA     = $false
            }
        }
        Add-CIPPScheduledTask -Task $ScheduledTask -hidden $false -DisallowDuplicateName $true
        return "Scheduled license removal for $username"
    } else {
        try {
            $ConvertTable = [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')) | ConvertFrom-Csv
            $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -tenantid $tenantFilter
            $GroupMemberships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/memberOf/microsoft.graph.group?`$select=id,displayName,assignedLicenses,mailEnabled,groupTypes" -tenantid $tenantFilter
            $LicenseGroups = $GroupMemberships | Where-Object { ($_.assignedLicenses | Measure-Object).Count -gt 0 }

            if ($LicenseGroups) {
                # remove user from license groups. Mail-enabled security groups can't be modified through Graph, so those go through Exchange Online instead
                $GraphRemoveRequests = [System.Collections.Generic.List[object]]::new()
                $ExoRemoveRequests = [System.Collections.Generic.List[object]]::new()
                $ExoGroups = [System.Collections.Generic.List[object]]::new()

                foreach ($LicenseGroup in $LicenseGroups) {
                    $IsM365Group = $LicenseGroup.groupTypes -contains 'Unified'
                    if ($LicenseGroup.mailEnabled -and -not $IsM365Group) {
                        $ExoRemoveRequests.Add(@{
                                CmdletInput = @{
                                    CmdletName = 'Remove-DistributionGroupMember'
                                    Parameters = @{
                                        Identity                        = $LicenseGroup.id
                                        Member                          = $User.id
                                        BypassSecurityGroupManagerCheck = $true
                                    }
                                }
                            })
                        $ExoGroups.Add($LicenseGroup)
                    } else {
                        $GraphRemoveRequests.Add(@{
                                id     = $LicenseGroup.id
                                method = 'DELETE'
                                url    = "groups/$($LicenseGroup.id)/members/$($User.id)/`$ref"
                            })
                    }
                }

                Write-Information 'Removing user from groups with licenses'

                if ($GraphRemoveRequests.Count -gt 0) {
                    $RemoveResults = New-GraphBulkRequest -tenantid $tenantFilter -requests @($GraphRemoveRequests)
                    Write-Information ($RemoveResults | ConvertTo-Json -Depth 5)
                    foreach ($Result in $RemoveResults) {
                        $GroupName = ($LicenseGroups | Where-Object { $_.id -eq $Result.id }).displayName
                        if ($Result.status -eq 204) {
                            Write-LogMessage -headers $Headers -API $APIName -message "Removed $($User.displayName) from license group $GroupName" -Sev 'Info' -tenant $TenantFilter
                            "Removed $($User.displayName) from license group $GroupName"
                        } else {
                            Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove $($User.displayName) from license group $GroupName. This is likely because its a Dynamic Group or synced with active directory." -Sev 'Error' -tenant $TenantFilter
                            "Failed to remove $($User.displayName) from license group $GroupName. This is likely because its a Dynamic Group or synced with active directory."
                        }
                    }
                }

                if ($ExoRemoveRequests.Count -gt 0) {
                    $RawExoRequest = New-ExoBulkRequest -tenantid $tenantFilter -cmdletArray @($ExoRemoveRequests)
                    $LastError = $RawExoRequest | Select-Object -Last 1
                    foreach ($ExoGroup in $ExoGroups) {
                        if (!$LastError -or ($LastError.error -and $LastError.target -notcontains $User.id)) {
                            Write-LogMessage -headers $Headers -API $APIName -message "Removed $($User.displayName) from mail-enabled license group $($ExoGroup.displayName)" -Sev 'Info' -tenant $TenantFilter
                            "Removed $($User.displayName) from mail-enabled license group $($ExoGroup.displayName)"
                        } else {
                            Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove $($User.displayName) from mail-enabled license group $($ExoGroup.displayName). This is likely because its a Dynamic Group or synced with active directory." -Sev 'Error' -tenant $TenantFilter
                            "Failed to remove $($User.displayName) from mail-enabled license group $($ExoGroup.displayName)."
                        }
                    }
                }
            }

            if (!$username) { $username = $User.userPrincipalName }

            # Re-fetch user to get current license state after group removals
            $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)?`$select=id,displayName,userPrincipalName,assignedLicenses,licenseAssignmentStates" -tenantid $tenantFilter

            # Separate directly-assigned vs group-inherited licenses
            $DirectLicenseSkuIds = @(($User.licenseAssignmentStates | Where-Object { $null -eq $_.assignedByGroup -and $_.state -eq 'Active' }).skuId | Select-Object -Unique)
            $GroupLicenseSkuIds = @(($User.licenseAssignmentStates | Where-Object { $null -ne $_.assignedByGroup -and $_.state -eq 'Active' }).skuId | Select-Object -Unique)

            if ($GroupLicenseSkuIds) {
                $GroupLicenseNames = $(($ConvertTable | Where-Object { $_.guid -in $GroupLicenseSkuIds }).'Product_Display_Name' | Sort-Object -Unique) -join ', '
                Write-LogMessage -headers $Headers -API $APIName -message "Licenses inherited from groups for $($username) will be removed when group membership changes are processed: $GroupLicenseNames" -Sev 'Info' -tenant $TenantFilter
            }

            $CurrentLicenses = $DirectLicenseSkuIds
            $ConvertedLicense = $(($ConvertTable | Where-Object { $_.guid -in $CurrentLicenses }).'Product_Display_Name' | Sort-Object -Unique) -join ', '
            if ($CurrentLicenses) {
                $LicensePayload = [PSCustomObject]@{
                    addLicenses    = @()
                    removeLicenses = @($CurrentLicenses)
                }
                if ($PSCmdlet.ShouldProcess($userid, "Remove licenses: $ConvertedLicense")) {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/assignlicense" -tenantid $tenantFilter -type POST -body (ConvertTo-Json -InputObject $LicensePayload -Compress -Depth 5) -verbose
                    Write-LogMessage -headers $Headers -API $APIName -message "Removed directly assigned licenses for $($username): $ConvertedLicense" -Sev 'Info' -tenant $TenantFilter
                }
                $ResultMessage = "Removed directly assigned licenses for $($Username): $ConvertedLicense"
                if ($GroupLicenseSkuIds) {
                    $ResultMessage = '{0}. Group-inherited licenses ({1}) will be removed automatically when group membership changes are processed.' -f $ResultMessage, $GroupLicenseNames
                }
                return $ResultMessage
            } else {
                if ($GroupLicenseSkuIds) {
                    return "No directly assigned licenses to remove for $username. Group-inherited licenses ($GroupLicenseNames) will be removed automatically when group membership changes are processed."
                }
                Write-LogMessage -headers $Headers -API $APIName -message "No licenses to remove for $username" -Sev 'Info' -tenant $TenantFilter
                return "No licenses to remove for $username"
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -message "Could not remove license for $username. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            return "Could not remove license for $($username). Error: $($ErrorMessage.NormalizedError)"
        }
    }
}
