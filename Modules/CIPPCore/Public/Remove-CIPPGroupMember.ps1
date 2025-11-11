function Remove-CIPPGroupMember(
    $Headers,
    [string]$GroupType,
    [string]$GroupId,
    [string]$Member,
    [string]$TenantFilter,
    [string]$APIName = 'Remove Group Member'
) {
    try {
        if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
            $Params = @{ Identity = $GroupId; Member = $Member; BypassSecurityGroupManagerCheck = $true }
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $Params -UseSystemMailbox $true
        } else {
            if ($Member -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                Write-Information "Member $Member is a GUID, proceeding with removal."
            } else {
                Write-Information "Member $Member is not a GUID, attempting to resolve to object ID."
                if ($Member -like '*#EXT#*') { $Member = [System.Web.HttpUtility]::UrlEncode($Member) }
                $UserObject = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Member)?`$select=id" -tenantid $TenantFilter
                if ($null -eq $UserObject.id) {
                    throw "Could not resolve user $Member to an object ID."
                }
                $Member = $UserObject.id
                Write-Information "Resolved member to object ID: $Member"
            }
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)/members/$($Member)/`$ref" -tenantid $TenantFilter -type DELETE -body '{}' -Verbose
        }
        $Results = "Successfully removed user $($Member) from $($GroupId)."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Info
        return $Results

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to remove user $($Member) from $($GroupId): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        throw $Results
    }
}
