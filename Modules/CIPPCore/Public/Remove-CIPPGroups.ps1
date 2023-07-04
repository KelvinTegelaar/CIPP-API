function Remove-CIPPGroups {
    [CmdletBinding()]
    param(
        $userid,
        $tenantFilter,
        $APIName = "Remove From Groups",
        $ExecutingUser
    )

    $AllGroups = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/?$select=DisplayName,mailEnabled" -tenantid $tenantFilter)

    (New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($userid)/GetMemberGroups" -tenantid $tenantFilter -type POST -body '{"securityEnabledOnly": false}').value | ForEach-Object -Parallel {
        Import-Module '.\GraphHelper.psm1'
        $group = $_
        
        try { 
            $Groupname = ($using:AllGroups | Where-Object -Property id -EQ $group).displayName
            $IsMailEnabled = ($using:AllGroups | Where-Object -Property id -EQ $group).mailEnabled
            $IsM365Group = ($using:AllGroups | Where-Object { $_.id -eq $group -and $_.groupTypes -contains "Unified" }) -ne $null

            if ($IsM365Group) {
                $RemoveRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$_/members/$($using:userid)/`$ref" -tenantid $using:tenantFilter -type DELETE -body '' -Verbose
            }
            elseif (-not $IsMailEnabled) {
                $RemoveRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$_/members/$($using:userid)/`$ref" -tenantid $using:tenantFilter -type DELETE -body '' -Verbose
            }
            elseif ($IsMailEnabled) {
                $Params = @{ Identity = $Groupname; Member = $using:userid ; BypassSecurityGroupManagerCheck = $true }
                New-ExoRequest -tenantid $using:tenantFilter -cmdlet "Remove-DistributionGroupMember" -cmdParams $params  -UseSystemMailbox $true
            }

            Write-LogMessage -user $using:ExecutingUser -API $($using:APIName) -message "Removed $($using:userid) from $groupname" -Sev "Info"  -tenant $using:TenantFilter
            return "Successfully removed user from group $Groupname"
        }
        catch {
            Write-LogMessage -user $using:ExecutingUser -API $($using:APIName) -message "Could not remove $($using:userid) from group $groupname" -Sev "Error" -tenant $using:TenantFilter
            return "Could not remove user from group $($Groupname): $($_.Exception.Message). This is likely because its a Dynamic Group or synched with active directory"
        }
    }
}
