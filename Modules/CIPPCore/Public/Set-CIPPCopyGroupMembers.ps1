function Set-CIPPCopyGroupMembers(
    [string]$ExecutingUser,
    [string]$UserId,
    [string]$CopyFromId,
    [string]$TenantFilter,
    [string]$APIName = "Copy User Groups"
) {
    $MemberIDs = "https://graph.microsoft.com/v1.0/directoryObjects/" + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$UserId" -tenantid $TenantFilter).id 
    $AddMemberBody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
    
    $Results = New-Object System.Collections.ArrayList
    (New-GraphGETRequest -uri "https://graph.microsoft.com/beta/users/$CopyFromId/memberOf" -tenantid $TenantFilter) | Where-Object { $_.GroupTypes -notin "DynamicMemberShip" } | ForEach-Object {
        try {
            $MailGroup = $_
            if ($MailGroup.MailEnabled -and $Mailgroup.ResourceProvisioningOptions -notin "Team") {
                $Params = @{ Identity = $MailGroup.mail; Member = $UserId; BypassSecurityGroupManagerCheck = $true }
                New-ExoRequest -tenantid $TenantFilter -cmdlet "Add-DistributionGroupMember" -cmdParams $params -UseSystemMailbox $true             
            }
            else {
                $GroupResult = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($_.id)" -tenantid $TenantFilter -type patch -body $AddMemberBody -Verbose
            }
            Write-LogMessage -user $ExecutingUser -API $APIName -message "Added $UserId to group $($_.displayName)" -Sev "Info"  -tenant $TenantFilter
            $Results.Add("Added group: $($MailGroup.displayName)") | Out-Null
        }
        catch {
            $NormalizedError = Get-NormalizedError -message  $($_.Exception.Message)
            $Results.Add("We've failed to add the group $($MailGroup.displayName): $NormalizedError") | Out-Null
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Group adding failed for group $($_.displayName):  $($_.Exception.Message)" -Sev "Error"
        }
    }

    return $Results
}
