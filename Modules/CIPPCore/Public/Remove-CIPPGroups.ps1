function Remove-CIPPGroups {
    [CmdletBinding()]
    param(
        $Username,
        $TenantFilter,
        $APIName = 'Remove From Groups',
        $Headers,
        $UserID
    )

    try {

        $BulkInfoRequests = [System.Collections.Generic.List[object]]::new()

        if (-not $UserID) {
            $BulkInfoRequests.Add(@{
                    id     = 'getUserID'
                    method = 'GET'
                    url    = "users/$($Username)?`$select=id"
                })
        }

        $BulkInfoRequests.Add(
            @{
                id     = 'getAllGroups'
                method = 'GET'
                url    = "groups/?`$select=displayName,mailEnabled,id,groupTypes,assignedLicenses,onPremisesSyncEnabled,membershipRule&`$top=999"
            })
        $BulkInfoRequests.Add(@{
                id     = 'getUserGroups'
                method = 'GET'
                url    = "users/$($UserID ?? $Username)/memberOf/microsoft.graph.group?`$select=id"
            })

        $BulkGetResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkInfoRequests)

        $UserInfo = ($BulkGetResults | Where-Object { $_.id -eq 'getUserID' }).body
        if ($UserInfo) {
            $UserID = $UserInfo.id
        }
        $AllGroups = ($BulkGetResults | Where-Object { $_.id -eq 'getAllGroups' }).body.value
        $UserGroups = ($BulkGetResults | Where-Object { $_.id -eq 'getUserGroups' }).body.value

        #users/$($User.id)/memberOf/microsoft.graph.directoryRole
        if (-not $UserGroups) {
            $Returnval = "$($Username) is not a member of any groups."
            Write-LogMessage -headers $Headers -API $APIName -message "$($Username) is not a member of any groups" -Sev 'Info' -tenant $TenantFilter
            return $Returnval
        }

        Write-Information "Initiating group membership removal for user: $Username in tenant: $TenantFilter"

        # Initialize bulk request arrays and results
        $BulkRequests = [System.Collections.Generic.List[object]]::new()
        $ExoBulkRequests = [System.Collections.Generic.List[object]]::new()
        $GraphLogs = [System.Collections.Generic.List[object]]::new()
        $ExoLogs = [System.Collections.Generic.List[object]]::new()
        $Results = [System.Collections.Generic.List[string]]::new()

        # Process each group and prepare bulk requests
        foreach ($Group in $UserGroups) {
            $GroupInfo = $AllGroups | Where-Object -Property id -EQ $Group.id
            $GroupName = $GroupInfo.displayName
            $IsMailEnabled = $GroupInfo.mailEnabled
            $IsM365Group = $GroupInfo.groupTypes -and $GroupInfo.groupTypes -contains 'Unified'
            $IsLicensed = $GroupInfo.assignedLicenses.Count -gt 0
            $IsDynamic = -not [string]::IsNullOrWhiteSpace($GroupInfo.membershipRule)

            if ($IsLicensed) {
                $Results.Add("Could not remove $Username from group '$GroupName' because it has assigned licenses. These groups are removed during the license removal step.")
                Write-LogMessage -headers $Headers -API $APIName -message "Could not remove $Username from group '$GroupName' because it has assigned licenses. These groups are removed during the license removal step." -sev 'Warn' -tenant $TenantFilter
            } elseif ($IsDynamic) {
                $Results.Add("Error: Could not remove $Username from group '$GroupName' because it is a Dynamic Group.")
                Write-LogMessage -headers $Headers -API $APIName -message "Could not remove $Username from group '$GroupName' because it is a Dynamic Group." -sev 'Warn' -tenant $TenantFilter
            } elseif ($GroupInfo.onPremisesSyncEnabled) {
                $Results.Add("Error: Could not remove $Username from group '$GroupName' because it is synced with Active Directory.")
                Write-LogMessage -headers $Headers -API $APIName -message "Could not remove $Username from group '$GroupName' because it is synced with Active Directory." -sev 'Warn' -tenant $TenantFilter
            } else {
                if ($IsM365Group -or (-not $IsMailEnabled)) {
                    # Use Graph API for M365 Groups and Security Groups
                    $BulkRequests.Add(@{
                            id     = "removeFromGroup-$($Group.id)"
                            method = 'DELETE'
                            url    = "groups/$($Group.id)/members/$UserID/`$ref"
                        })
                    $GraphLogs.Add(@{
                            message   = "Removed $Username from $GroupName"
                            id        = "removeFromGroup-$($Group.id)"
                            groupName = $GroupName
                        })
                } elseif ($IsMailEnabled) {
                    # Use Exchange Online for Distribution Lists
                    $Params = @{
                        Identity                        = $GroupName
                        Member                          = $UserID
                        BypassSecurityGroupManagerCheck = $true
                    }
                    $ExoBulkRequests.Add(@{
                            CmdletInput = @{
                                CmdletName = 'Remove-DistributionGroupMember'
                                Parameters = $Params
                            }
                        })
                    $ExoLogs.Add(@{
                            message   = "Removed $Username from $GroupName"
                            target    = $UserID
                            groupName = $GroupName
                        })
                }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Error preparing bulk group removal requests: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        return "Error preparing bulk group removal requests: $($ErrorMessage.NormalizedError)"
    }

    # Execute Graph bulk requests
    if ($BulkRequests.Count -gt 0) {
        try {
            $RawGraphRequest = New-GraphBulkRequest -tenantid $TenantFilter -scope 'https://graph.microsoft.com/.default' -Requests @($BulkRequests) -asapp $true

            foreach ($GraphLog in $GraphLogs) {
                $GraphError = $RawGraphRequest | Where-Object { $_.id -eq $GraphLog.id -and $_.status -notmatch '^2[0-9]+' }
                if ($GraphError) {
                    $Message = Get-NormalizedError -message $GraphError.body.error
                    $Results.Add("Could not remove $Username from group '$($GraphLog.groupName)': $Message. This is likely because it's a Dynamic Group or synced with Active Directory")
                    Write-LogMessage -headers $Headers -API $APIName -message "Could not remove $Username from group '$($GraphLog.groupName)': $Message" -Sev 'Error' -tenant $TenantFilter
                } else {
                    $Results.Add("Successfully removed $Username from group '$($GraphLog.groupName)'")
                    Write-LogMessage -headers $Headers -API $APIName -message $GraphLog.message -Sev 'Info' -tenant $TenantFilter
                }
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-Information "Error executing bulk Graph requests: $($ErrorMessage | ConvertTo-Json -Depth 5)"
        }
    }

    # Execute Exchange Online bulk requests
    if ($ExoBulkRequests.Count -gt 0) {
        try {
            $RawExoRequest = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($ExoBulkRequests)
            $LastError = $RawExoRequest | Select-Object -Last 1

            foreach ($ExoError in $LastError.error) {
                $Results.Add("Error - $ExoError")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ExoError -Sev 'Error'
            }

            foreach ($ExoLog in $ExoLogs) {
                $ExoError = $LastError | Where-Object { $ExoLog.target -in $_.target -and $_.error }
                if (!$LastError -or ($LastError.error -and $LastError.target -notcontains $ExoLog.target)) {
                    $Results.Add("Successfully removed $Username from group $($ExoLog.groupName)")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ExoLog.message -Sev 'Info'
                } else {
                    $Results.Add("Could not remove $Username from $($ExoLog.groupName). This is likely because its a Dynamic Group or synched with active directory")
                    Write-LogMessage -headers $Headers -API $APIName -message "Could not remove $Username from $($ExoLog.groupName)" -Sev 'Error' -tenant $TenantFilter
                }
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -message "Error executing Exchange bulk requests: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add("Error executing bulk Exchange requests: $($ErrorMessage.NormalizedError)")
        }
    }

    return $Results
}
