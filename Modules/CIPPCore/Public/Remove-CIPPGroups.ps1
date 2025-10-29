function Remove-CIPPGroups {
    [CmdletBinding()]
    param(
        $Username,
        $TenantFilter,
        $APIName = 'Remove From Groups',
        $Headers,
        $UserID
    )

    if (-not $userid) {
        $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter).id
    }
    $AllGroups = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/?`$select=displayName,mailEnabled,id,groupTypes,assignedLicenses&`$top=999" -tenantid $TenantFilter)

    $Returnval = (New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserID)/GetMemberGroups" -tenantid $TenantFilter -type POST -body '{"securityEnabledOnly": false}').value | ForEach-Object -Parallel {
        Import-Module '.\Modules\AzBobbyTables'
        Import-Module '.\Modules\CIPPCore'
        $Group = $_

        try {
            $GroupName = ($using:AllGroups | Where-Object -Property id -EQ $Group).displayName
            $IsMailEnabled = ($using:AllGroups | Where-Object -Property id -EQ $Group).mailEnabled
            $IsM365Group = $null -ne ($using:AllGroups | Where-Object { $_.id -eq $Group -and $_.groupTypes -contains 'Unified' })
            $IsLicensed = ($using:AllGroups | Where-Object -Property id -EQ $Group).assignedLicenses.Count -gt 0

            if ($IsLicensed) {
                "Could not remove $($using:Username) from $GroupName. This is because the group has licenses assigned to it."
            } else {
                if ($IsM365Group) {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$_/members/$($using:UserID)/`$ref" -tenantid $using:TenantFilter -type DELETE -body '' -Verbose
                } elseif (-not $IsMailEnabled) {
                    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$_/members/$($using:UserID)/`$ref" -tenantid $using:TenantFilter -type DELETE -body '' -Verbose
                } elseif ($IsMailEnabled) {
                    $Params = @{ Identity = $GroupName; Member = $using:UserID ; BypassSecurityGroupManagerCheck = $true }
                    New-ExoRequest -tenantid $using:tenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true
                }

                Write-LogMessage -headers $using:Headers -API $($using:APIName) -message "Removed $($using:Username) from $GroupName" -Sev 'Info' -tenant $using:TenantFilter
                "Successfully removed $($using:Username) from group $GroupName"
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $using:Headers -API $($using:APIName) -message "Could not remove $($using:Username) from group $GroupName : $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $using:TenantFilter -LogData $ErrorMessage
            "Could not remove $($using:Username) from group $($GroupName): $($ErrorMessage.NormalizedError). This is likely because its a Dynamic Group or synched with active directory"
        }
    }
    if (-not $Returnval) {
        $Returnval = "$($Username) is not a member of any groups."
        Write-LogMessage -headers $Headers -API $APIName -message "$($Username) is not a member of any groups" -Sev 'Info' -tenant $TenantFilter
    }
    return $Returnval
}
