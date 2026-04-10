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
            $ModuleBase = Get-Module -Name CIPPCore | Select-Object -ExpandProperty ModuleBase
            $ConvertTable = Import-Csv (Join-Path $ModuleBase 'lib\data\ConversionTable.csv')
            $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)" -tenantid $tenantFilter
            $GroupMemberships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/memberOf/microsoft.graph.group?`$select=id,displayName,assignedLicenses" -tenantid $tenantFilter
            $LicenseGroups = $GroupMemberships | Where-Object { ($_.assignedLicenses | Measure-Object).Count -gt 0 }

            if ($LicenseGroups) {
                # remove user from groups with licenses, these can only be graph groups
                $RemoveRequests = foreach ($LicenseGroup in $LicenseGroups) {
                    @{
                        id     = $LicenseGroup.id
                        method = 'DELETE'
                        url    = "groups/$($LicenseGroup.id)/members/$($User.id)/`$ref"
                    }
                }

                Write-Information 'Removing user from groups with licenses'
                $RemoveResults = New-GraphBulkRequest -tenantid $tenantFilter -requests @($RemoveRequests)
                Write-Information ($RemoveResults | ConvertTo-Json -Depth 5)
                foreach ($Result in $RemoveResults) {
                    $Group = $LicenseGroups | Where-Object { $_.id -eq $Result.id }
                    $GroupName = $Group.displayName

                    if ($Result.status -eq 204) {
                        Write-LogMessage -headers $Headers -API $APIName -message "Removed $($User.displayName) from license group $GroupName" -Sev 'Info' -tenant $TenantFilter
                        "Removed $($User.displayName) from license group $GroupName"
                    } else {
                        Write-LogMessage -headers $Headers -API $APIName -message "Failed to remove $($User.displayName) from license group $GroupName. This is likely because its a Dynamic Group or synced with active directory." -Sev 'Error' -tenant $TenantFilter
                        "Failed to remove $($User.displayName) from license group $GroupName. This is likely because its a Dynamic Group or synced with active directory."
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
