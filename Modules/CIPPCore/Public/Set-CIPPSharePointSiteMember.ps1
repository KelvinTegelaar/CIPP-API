function Set-CIPPSharePointSiteMember {
    <#
    .SYNOPSIS
    Adds users to, or removes them from, a SharePoint site role (Owners, Members or Visitors)

    .DESCRIPTION
    Group-connected sites manage Owners/Members through the backing M365 group via Graph;
    Visitors (and classic/communication sites entirely) are managed through the site's
    associated SharePoint role groups via the SharePoint REST API using certificate
    authentication. A removal of a user directly added to a role group on a group-connected
    site (MemberType 'User') targets that role group rather than the M365 group.

    Returns one message per user. Only throws when no user could be processed, so a partial
    failure still reports every outcome.

    .PARAMETER UserPrincipalName
    The UPN(s) to add or remove

    .PARAMETER Role
    The site role: Owners, Members or Visitors

    .PARAMETER Add
    Add the users when true, remove them when false

    .PARAMETER SharePointType
    The site's root web template. 'Group' marks a group-connected site.

    .PARAMETER GroupId
    The backing M365 group of a group-connected site, as an id or its mail/mailNickname

    .PARAMETER SiteUrl
    The site URL, required for Visitors and for sites that are not group-connected

    .PARAMETER MemberType
    The member type from ListSiteMembers, used on removals to target the SharePoint role group
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$UserPrincipalName,
        [string]$Role = 'Members',
        [bool]$Add = $true,
        [string]$SharePointType,
        [string]$GroupId,
        [string]$SiteUrl,
        [string]$MemberType,
        $Headers,
        [string]$APIName = 'Set SharePoint Site Member'
    )

    $AssociatedGroups = @{
        'Owners'   = 'associatedownergroup'
        'Members'  = 'associatedmembergroup'
        'Visitors' = 'associatedvisitorgroup'
    }
    $UPNs = @($UserPrincipalName | Where-Object { $_ })
    $FailedCount = 0

    try {
        if ($UPNs.Count -eq 0) { throw 'No user was selected.' }
        if (-not $AssociatedGroups.ContainsKey($Role)) {
            throw "Invalid role '$Role'. Valid roles are: $($AssociatedGroups.Keys -join ', ')."
        }

        $UseGraphGroup = $SharePointType -eq 'Group' -and $Role -ne 'Visitors' -and ($Add -or $MemberType -ne 'User')

        if ($UseGraphGroup) {
            if (-not $GroupId) {
                $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
                $GroupId = (New-GraphGetRequest -uri "$($RestContext.BaseUri)/site?`$select=GroupId" -tenantid $TenantFilter -scope $RestContext.Scope -extraHeaders $RestContext.Headers -UseCertificate -AsApp $true).GroupId
            }
            if ($GroupId -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
                $GroupId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$filter=mail eq '$GroupId' or proxyAddresses/any(x:endsWith(x,'$GroupId')) or mailNickname eq '$GroupId'" -ComplexFilter -tenantid $TenantFilter).id
            }

            if ($Role -eq 'Owners') {
                $Results = foreach ($UPN in $UPNs) {
                    try {
                        $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UPN`?`$select=id" -tenantid $TenantFilter).id
                        if ($Add) {
                            $OwnerBody = ConvertTo-Json -Compress -InputObject @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$UserID" }
                            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId/owners/`$ref" -tenantid $TenantFilter -type POST -body $OwnerBody
                            $Message = "Successfully added $UPN as an owner of the M365 group backing the site."
                        } else {
                            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId/owners/$UserID/`$ref" -tenantid $TenantFilter -type DELETE -body ''
                            $Message = "Successfully removed $UPN as an owner of the M365 group backing the site."
                        }
                        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Info
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        $Message = "Failed to $(if ($Add) { 'add' } else { 'remove' }) $UPN as an owner. Error: $($ErrorMessage.NormalizedError)"
                        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error -LogData $ErrorMessage
                        $FailedCount++
                    }
                    $Message
                }
            } else {
                if ($Add) {
                    $Results = Add-CIPPGroupMember -GroupType 'Team' -GroupID $GroupId -Member $UPNs -TenantFilter $TenantFilter -Headers $Headers
                } else {
                    $Results = Remove-CIPPGroupMember -GroupType 'Team' -GroupID $GroupId -Member $UPNs -TenantFilter $TenantFilter -Headers $Headers
                }
            }
        } else {
            if (-not $SiteUrl) { throw 'No site URL was provided for this site.' }

            $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
            $Scope = $RestContext.Scope
            $JsonAccept = $RestContext.Headers
            $BaseUri = $RestContext.BaseUri
            $RoleGroup = $AssociatedGroups[$Role]
            $RoleLabel = $Role.ToLower().TrimEnd('s')
            $Article = if ($RoleLabel -match '^[aeiou]') { 'an' } else { 'a' }

            $Results = foreach ($UPN in $UPNs) {
                try {
                    try {
                        $EnsureBody = ConvertTo-Json -Compress -InputObject @{ logonName = "i:0#.f|membership|$UPN" }
                        $EnsuredUser = New-GraphPostRequest -uri "$BaseUri/web/ensureuser" -tenantid $TenantFilter -scope $Scope -type POST -body $EnsureBody -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                    } catch {
                        throw "Could not resolve $UPN on the site (ensureuser): $($_.Exception.Message)"
                    }
                    if (-not $EnsuredUser.Id) {
                        throw "Could not resolve $UPN on the site."
                    }

                    if ($Add) {
                        # Same shape PnP sends: an SP.User entity posted to the group's users
                        # collection, which requires the odata=verbose content type.
                        $AddBody = ConvertTo-Json -Compress -Depth 5 -InputObject @{
                            '__metadata' = @{ 'type' = 'SP.User' }
                            'LoginName'  = $EnsuredUser.LoginName
                        }
                        try {
                            $null = New-GraphPostRequest -uri "$BaseUri/web/$RoleGroup/users" -tenantid $TenantFilter -scope $Scope -type POST -body $AddBody -contentType 'application/json;odata=verbose' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                        } catch {
                            throw "Could not add $UPN to the site $Role group: $($_.Exception.Message)"
                        }
                        $Message = "Successfully added $UPN as $Article $RoleLabel of $SiteUrl."
                    } else {
                        try {
                            $null = New-GraphPostRequest -uri "$BaseUri/web/$RoleGroup/users/removebyid($($EnsuredUser.Id))" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                        } catch {
                            if ($_.Exception.Message -match 'Can not find the user') {
                                throw "$UPN is not in the site's $Role group."
                            }
                            throw "Could not remove $UPN from the site $Role group: $($_.Exception.Message)"
                        }
                        $Message = "Successfully removed $UPN as $Article $RoleLabel of $SiteUrl."
                    }
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Info
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Failed to $(if ($Add) { 'add' } else { 'remove' }) $UPN. Error: $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error -LogData $ErrorMessage
                    $FailedCount++
                }
                $Message
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to modify $Role for $($SiteUrl ?? $GroupId). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error -LogData $ErrorMessage
        throw $Message
    }

    if ($FailedCount -eq $UPNs.Count) {
        throw ($Results -join ' ')
    }
    return $Results
}
