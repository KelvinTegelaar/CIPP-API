function Invoke-CIPPStandardUsageLocation {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) UsageLocation
    .SYNOPSIS
        (Label) Usage location for all users
    .DESCRIPTION
        (Helptext) Sets the Entra usage location (the two-letter country code that licensing and security tools such as Huntress ITDR depend on) on every member account. Optionally limit the sweep to members of named groups, skip members of named groups (users legitimately based in another country), or only fill in accounts that have no usage location yet.
        (DocsDescription) Sets the usage location on every member account; guest accounts are ignored. Group names are resolved per tenant by display name and expanded to their transitive user members: include groups restrict the sweep to those members, exclude groups remove them from it. A configured group that does not exist in a tenant, or a failed membership lookup, skips the run rather than sweeping the wrong accounts. With 'only set when blank' enabled, accounts that already carry any usage location are left as they are. Directory-synced accounts are included: usage location is cloud-managed and stays writable for them unless a custom sync rule maps it from on-premises.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Ensures every employee account records the country it is used from, which Microsoft requires before licences can be assigned and which security monitoring uses to recognise sign-ins from unexpected locations. Staff based in other countries are exempted through a group.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"required":true,"name":"standards.UsageLocation.usageLocation","label":"Usage location","api":{"url":"/countryList.json","labelField":"Name","valueField":"Code"}}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.UsageLocation.includeGroups","label":"Only apply to members of these groups (display names; blank = all member accounts)"}
            {"type":"autoComplete","multiple":true,"creatable":true,"required":false,"name":"standards.UsageLocation.excludeGroups","label":"Skip members of these groups (display names; users legitimately located elsewhere)"}
            {"type":"switch","name":"standards.UsageLocation.onlyWhenBlank","label":"Only set accounts that have no usage location (never overwrite an existing value)","required":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2026-09-16
        POWERSHELLEQUIVALENT
            Update-MgUser -UserId user@domain.com -UsageLocation 'US'
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $UsageLocation = "$($Settings.usageLocation.value ?? $Settings.usageLocation)".Trim().ToUpperInvariant()
    if ($UsageLocation -notmatch '^[A-Z]{2}$') {
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "UsageLocation: '$UsageLocation' is not a two-letter country code. Skipping run." -Sev Error
        return
    }
    $OnlyWhenBlank = [bool]($Settings.onlyWhenBlank -eq $true)

    $ToNames = {
        param($Value)
        @(@($Value) | ForEach-Object {
                if ($_ -is [string]) { $_ } else { "$($_.value ?? $_.label)" }
            } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
    }
    $IncludeNames = & $ToNames $Settings.includeGroups
    $ExcludeNames = & $ToNames $Settings.excludeGroups

    try {
        $AllUsers = @(New-CIPPDbRequest -TenantFilter $Tenant -Type 'Users' | Where-Object { $_ })
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the UsageLocation state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Group scoping: names resolve live by display name (a template applies to many tenants,
    # so an id would only ever match one) and expand to TRANSITIVE user members. An
    # unresolved name or a failed lookup aborts the run - sweeping with half a scope is how
    # an overseas office ends up with the wrong country and broken licences.
    $IncludedIds = @{}
    $ExcludedIds = @{}
    if ($IncludeNames.Count -gt 0 -or $ExcludeNames.Count -gt 0) {
        try {
            $MemberRequests = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($Scope in @(@{ Prefix = 'include'; Names = $IncludeNames }, @{ Prefix = 'exclude'; Names = $ExcludeNames })) {
                foreach ($Name in $Scope.Names) {
                    $EscapedName = $Name -replace "'", "''"
                    $GroupFilter = [System.Uri]::EscapeDataString("displayName eq '$EscapedName'")
                    $Groups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups?`$filter=$GroupFilter&`$select=id,displayName" -tenantid $Tenant | Where-Object { $_.id })
                    if ($Groups.Count -eq 0) { throw "the group '$Name' does not exist in this tenant" }
                    foreach ($Group in $Groups) {
                        $MemberRequests.Add(@{ id = "$($Scope.Prefix)-$($Group.id)"; method = 'GET'; url = "groups/$($Group.id)/transitiveMembers/microsoft.graph.user?`$select=id&`$top=999" })
                    }
                }
            }
            $Responses = @(New-GraphBulkRequest -tenantid $Tenant -Requests @($MemberRequests) -asapp $true -Version 'v1.0')
            foreach ($Response in $Responses) {
                if ([int]$Response.status -lt 200 -or [int]$Response.status -gt 299) {
                    throw "membership lookup for $($Response.id) returned $($Response.status) $($Response.body.error.message)"
                }
                $Bucket = if ("$($Response.id)".StartsWith('include-')) { $IncludedIds } else { $ExcludedIds }
                foreach ($MemberId in @($Response.body.value.id | Where-Object { $_ })) { $Bucket["$MemberId"] = $true }
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "UsageLocation: could not resolve the configured groups, refusing to run with a partial scope. Error: $ErrorMessage" -Sev Error
            return
        }
    }

    $Candidates = @($AllUsers | Where-Object { $_.userType -eq 'Member' -and $_.id })
    if ($IncludeNames.Count -gt 0) { $Candidates = @($Candidates | Where-Object { $IncludedIds.ContainsKey("$($_.id)") }) }
    if ($ExcludeNames.Count -gt 0) { $Candidates = @($Candidates | Where-Object { -not $ExcludedIds.ContainsKey("$($_.id)") }) }

    $IncorrectUsers = @($Candidates | Where-Object {
            $Location = "$($_.usageLocation)".Trim().ToUpperInvariant()
            if ($OnlyWhenBlank) { [string]::IsNullOrWhiteSpace($Location) } else { $Location -ne $UsageLocation }
        })

    if ($Settings.remediate -eq $true) {
        if ($IncorrectUsers.Count -gt 0) {
            $UpdateDB = $false
            $Index = 0
            $BulkRequests = foreach ($User in $IncorrectUsers) {
                @{
                    id      = "$Index"
                    method  = 'PATCH'
                    url     = "users/$($User.id)"
                    body    = @{ usageLocation = $UsageLocation }
                    headers = @{ 'Content-Type' = 'application/json' }
                }
                $Index++
            }

            try {
                $BulkResults = @(New-GraphBulkRequest -tenantid $Tenant -Requests @($BulkRequests) -asapp $true)
                foreach ($Result in $BulkResults) {
                    $User = $IncorrectUsers[[int]$Result.id]
                    if ($Result.status -eq 200 -or $Result.status -eq 204) {
                        $UpdateDB = $true
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Usage location for $($User.userPrincipalName) has been set to $UsageLocation" -sev Info
                    } else {
                        $ErrorMsg = if ($Result.body.error.message) { $Result.body.error.message } else { "Unknown error (Status: $($Result.status))" }
                        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set usage location for $($User.userPrincipalName): $ErrorMsg" -sev Error
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set usage location to $UsageLocation for all users: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }

            if ($UpdateDB) {
                try {
                    Set-CIPPDBCacheUsers -TenantFilter $Tenant
                } catch {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to refresh user cache after remediation: $($_.Exception.Message)" -sev Warning
                }
            }
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All in-scope users already have the usage location set to $UsageLocation." -sev Info
        }
    }

    if ($Settings.alert -eq $true) {
        if ($IncorrectUsers.Count -gt 0) {
            Write-StandardsAlert -message "The following accounts do not have the usage location set to $UsageLocation" -object $IncorrectUsers -tenant $Tenant -standardName 'UsageLocation' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "The following accounts do not have the usage location set to $UsageLocation : $($IncorrectUsers.userPrincipalName -join ', ')" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "All in-scope accounts have the usage location set to $UsageLocation." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $FieldValue = @($IncorrectUsers | Select-Object -Property userPrincipalName, displayName, usageLocation, userType)
        Add-CIPPBPAField -FieldName 'UsageLocationIncorrectUsers' -FieldValue $FieldValue -StoreAs json -Tenant $Tenant

        $CurrentValue = @{
            usageLocation  = $UsageLocation
            incorrectUsers = @($FieldValue)
        }
        $ExpectedValue = @{
            usageLocation  = $UsageLocation
            incorrectUsers = @()
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.UsageLocation' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
