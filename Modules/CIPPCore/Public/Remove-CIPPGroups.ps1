function Remove-CIPPGroups {
    [CmdletBinding()]
    param(
        $Username,
        $tenantFilter,
        $APIName = 'Remove From Groups',
        $Headers,
        $userid
    )

    if (-not $userid) {
        $userid = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $Tenantfilter).id
    }
    $AllGroups = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/?`$select=displayName,mailEnabled,id,groupTypes,assignedLicenses&`$top=999" -tenantid $tenantFilter)

    $Returnval = (New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/GetMemberGroups" -tenantid $tenantFilter -type POST -body '{"securityEnabledOnly": false}').value | ForEach-Object -Parallel {
        Import-Module '.\Modules\AzBobbyTables'
        Import-Module '.\Modules\CIPPCore'
        $group = $_

        try {
            $Groupname = ($using:AllGroups | Where-Object -Property id -EQ $group).displayName
            $IsMailEnabled = ($using:AllGroups | Where-Object -Property id -EQ $group).mailEnabled
            $IsM365Group = $null -ne ($using:AllGroups | Where-Object { $_.id -eq $group -and $_.groupTypes -contains 'Unified' })
            $IsLicensed = ($using:AllGroups | Where-Object -Property id -EQ $group).assignedLicenses.Count -gt 0

            if ($IsLicensed) {
                "Could not remove $($using:Username) from $Groupname. This is because the group has licenses assigned to it."
            } else {
                if ($IsM365Group) {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$_/members/$($using:userid)/`$ref" -tenantid $using:tenantFilter -type DELETE -body '' -Verbose
                } elseif (-not $IsMailEnabled) {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$_/members/$($using:userid)/`$ref" -tenantid $using:tenantFilter -type DELETE -body '' -Verbose
                } elseif ($IsMailEnabled) {
                    $Params = @{ Identity = $Groupname; Member = $using:userid ; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $using:tenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                }

                Write-LogMessage -headers $using:Headers -API $($using:APIName) -message "Removed $($using:Username) from $groupname" -Sev 'Info' -tenant $using:TenantFilter
                "Successfully removed $($using:Username) from group $Groupname"
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $using:Headers -API $($using:APIName) -message "Could not remove $($using:Username) from group $groupname : $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $using:TenantFilter -LogData $ErrorMessage
            "Could not remove $($using:Username) from group $($Groupname): $($ErrorMessage.NormalizedError). This is likely because its a Dynamic Group or synched with active directory"
        }
    }
    if (!$Returnval) {
        $Returnval = "$($Username) is not a member of any groups."
        Write-LogMessage -headers $Headers -API $APIName -message "$($Username) is not a member of any groups" -Sev 'Info' -tenant $TenantFilter
    }
    return $Returnval
}
