function New-CIPPGroup {
    <#
    .SYNOPSIS
    Creates a new group in Microsoft 365 or Exchange Online

    .DESCRIPTION
    Unified function for creating groups that handles all group types consistently.
    Used by both direct group creation and group template application.

    .PARAMETER GroupObject
    Object containing group properties (displayName, description, groupType, etc.)

    .PARAMETER TenantFilter
    The tenant domain name where the group should be created

    .PARAMETER APIName
    The API name for logging purposes

    .PARAMETER ExecutingUser
    The user executing the request (for logging)

    .EXAMPLE
    New-CIPPGroup -GroupObject $GroupData -TenantFilter 'contoso.com' -APIName 'AddGroup'

    .NOTES
    Supports all group types: Generic, Security, AzureRole, Dynamic, M365, Distribution, DynamicDistribution
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$GroupObject,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$APIName = 'New-CIPPGroup',

        [Parameter(Mandatory = $false)]
        [string]$ExecutingUser = 'CIPP'
    )

    try {
        # Normalize group type for consistent handling (accept camelCase from templates)
        $NormalizedGroupType = switch -Wildcard ($GroupObject.groupType.ToLower()) {
            '*dynamicdistribution*' { 'DynamicDistribution'; break }  # Check this first before *dynamic* and *distribution*
            '*dynamic*' { 'Dynamic'; break }
            '*generic*' { 'Generic'; break }
            '*security*' { 'Security'; break }
            '*azurerole*' { 'AzureRole'; break }
            '*m365*' { 'M365'; break }
            '*unified*' { 'M365'; break }
            '*microsoft*' { 'M365'; break }
            '*distribution*' { 'Distribution'; break }
            '*mail*' { 'Distribution'; break }
            default { $GroupObject.groupType }
        }

        # Determine if this group type needs an email address
        $GroupTypesNeedingEmail = @('M365', 'Distribution', 'DynamicDistribution')
        $NeedsEmail = $NormalizedGroupType -in $GroupTypesNeedingEmail

        # Determine email address only for group types that need it
        $Email = if ($NeedsEmail) {
            if ($GroupObject.primDomain.value) {
                "$($GroupObject.username)@$($GroupObject.primDomain.value)"
            } elseif ($GroupObject.primaryEmailAddress) {
                $GroupObject.primaryEmailAddress
            } elseif ($GroupObject.username -like '*@*') {
                # Username already contains an email address (e.g., from templates with @%tenantfilter%)
                $GroupObject.username
            } else {
                "$($GroupObject.username)@$($TenantFilter)"
            }
        } else {
            $null
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Creating group $($GroupObject.displayName) of type $NormalizedGroupType$(if ($NeedsEmail) { " with email $Email" })" -Sev Info

        # Handle Graph API groups (Security, Generic, AzureRole, Dynamic, M365)
        if ($NormalizedGroupType -in @('Generic', 'Security', 'AzureRole', 'Dynamic', 'M365')) {
            Write-Information "Creating group $($GroupObject.displayName) of type $NormalizedGroupType$(if ($NeedsEmail) { " with email $Email" })"
            $BodyParams = [PSCustomObject]@{
                'displayName'        = $GroupObject.displayName
                'description'        = $GroupObject.description
                'mailNickname'       = $GroupObject.username
                'mailEnabled'        = $false
                'securityEnabled'    = $true
                'isAssignableToRole' = ($NormalizedGroupType -eq 'AzureRole')
            }

            # Handle dynamic membership
            if ($GroupObject.membershipRules) {
                $BodyParams | Add-Member -NotePropertyName 'membershipRule' -NotePropertyValue $GroupObject.membershipRules
                $BodyParams | Add-Member -NotePropertyName 'membershipRuleProcessingState' -NotePropertyValue 'On'

                if ($NormalizedGroupType -eq 'M365') {
                    $BodyParams | Add-Member -NotePropertyName 'groupTypes' -NotePropertyValue @('Unified', 'DynamicMembership')
                    $BodyParams.mailEnabled = $true
                } else {
                    $BodyParams | Add-Member -NotePropertyName 'groupTypes' -NotePropertyValue @('DynamicMembership')
                }

                # Skip adding static members for dynamic groups
                $SkipStaticMembers = $true
            } elseif ($NormalizedGroupType -eq 'M365') {
                # Static M365 group
                $BodyParams | Add-Member -NotePropertyName 'groupTypes' -NotePropertyValue @('Unified')
                $BodyParams.mailEnabled = $true
            }

            # Add owners
            if ($GroupObject.owners -and $GroupObject.owners.Count -gt 0) {
                $OwnerBindings = $GroupObject.owners | ForEach-Object {
                    if ($_.value) {
                        "https://graph.microsoft.com/v1.0/users/$($_.value)"
                    } elseif ($_ -is [string]) {
                        "https://graph.microsoft.com/v1.0/users/$_"
                    }
                } | Where-Object { $_ }

                if ($OwnerBindings) {
                    $BodyParams | Add-Member -NotePropertyName 'owners@odata.bind' -NotePropertyValue @($OwnerBindings)
                }
            }

            # Add members (only for non-dynamic groups)
            if ($GroupObject.members -and $GroupObject.members.Count -gt 0 -and -not $SkipStaticMembers) {
                $MemberBindings = $GroupObject.members | ForEach-Object {
                    if ($_.value) {
                        "https://graph.microsoft.com/v1.0/users/$($_.value)"
                    } elseif ($_ -is [string]) {
                        "https://graph.microsoft.com/v1.0/users/$_"
                    }
                } | Where-Object { $_ }

                if ($MemberBindings) {
                    $BodyParams | Add-Member -NotePropertyName 'members@odata.bind' -NotePropertyValue @($MemberBindings)
                }
            }

            # Create the group via Graph API
            $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantFilter -type POST -body (ConvertTo-Json -InputObject $BodyParams -Depth 10)

            $Result = [PSCustomObject]@{
                Success   = $true
                Message   = "Successfully created group $($GroupObject.displayName)"
                GroupId   = $GraphRequest.id
                GroupType = $NormalizedGroupType
                Email     = if ($NeedsEmail) { $Email } else { $null }
            }

        } else {
            # Handle Exchange Online groups (Distribution, DynamicDistribution)

            if ($NormalizedGroupType -eq 'DynamicDistribution') {
                Write-Information "Creating dynamic distribution group $($GroupObject.displayName) with email $Email"
                $ExoParams = @{
                    Name               = $GroupObject.displayName
                    RecipientFilter    = $GroupObject.membershipRules
                    PrimarySmtpAddress = $Email
                }
                $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DynamicDistributionGroup' -cmdParams $ExoParams

                # Set external sender restrictions if specified
                if ($null -ne $GroupObject.allowExternal -and $GroupObject.allowExternal -eq $true -and $GraphRequest.Identity) {
                    $SetParams = @{
                        RequireSenderAuthenticationEnabled = [bool]!$GroupObject.allowExternal
                        Identity                           = $GraphRequest.Identity
                    }
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DynamicDistributionGroup' -cmdParams $SetParams
                }

            } else {
                # Regular Distribution Group
                Write-Information "Creating distribution group $($GroupObject.displayName) with email $Email"

                $ExoParams = @{
                    Name                               = $GroupObject.displayName
                    Alias                              = $GroupObject.username
                    Description                        = $GroupObject.description
                    PrimarySmtpAddress                 = $Email
                    Type                               = $GroupObject.groupType
                    RequireSenderAuthenticationEnabled = [bool]!$GroupObject.allowExternal
                }

                # Add owners
                if ($GroupObject.owners -and $GroupObject.owners.Count -gt 0) {
                    $OwnerEmails = $GroupObject.owners | ForEach-Object {
                        if ($_.value) { $_.value } elseif ($_ -is [string]) { $_ }
                    } | Where-Object { $_ }

                    if ($OwnerEmails) {
                        $ExoParams.ManagedBy = @($OwnerEmails)
                    }
                }

                # Add members
                if ($GroupObject.members -and $GroupObject.members.Count -gt 0) {
                    $MemberEmails = $GroupObject.members | ForEach-Object {
                        if ($_.value) { $_.value } elseif ($_ -is [string]) { $_ }
                    } | Where-Object { $_ }

                    if ($MemberEmails) {
                        $ExoParams.Members = @($MemberEmails)
                    }
                }

                $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DistributionGroup' -cmdParams $ExoParams
            }

            $Result = [PSCustomObject]@{
                Success   = $true
                Message   = "Successfully created group $($GroupObject.displayName)"
                GroupId   = $GraphRequest.Identity
                GroupType = $NormalizedGroupType
                Email     = $Email
            }
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Created group $($GroupObject.displayName) with id $($Result.GroupId)" -Sev Info
        return $Result

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Group creation failed for $($GroupObject.displayName): $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage

        return [PSCustomObject]@{
            Success   = $false
            Message   = "Failed to create group $($GroupObject.displayName): $($ErrorMessage.NormalizedError)"
            Error     = $ErrorMessage.NormalizedError
            GroupType = $NormalizedGroupType
        }
    }
}
