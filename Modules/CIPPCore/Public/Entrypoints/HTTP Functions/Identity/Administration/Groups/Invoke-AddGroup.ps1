using namespace System.Net

function Invoke-AddGroup {
    <#
    .SYNOPSIS
    Create a new group in Microsoft 365 or Exchange Online for one or more tenants
    
    .DESCRIPTION
    Creates a new group (security, Microsoft 365, dynamic, or distribution) in Microsoft 365 or Exchange Online for one or more tenants, supporting both static and dynamic membership, owners, and members.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.ReadWrite
    
    .NOTES
    Group: Identity Management
    Summary: Add Group
    Description: Creates a new group (security, Microsoft 365, dynamic, or distribution) in Microsoft 365 or Exchange Online for one or more tenants, supporting static/dynamic membership, owners, and members. Handles both Graph API and Exchange Online scenarios.
    Tags: Identity,Groups,Microsoft 365,Exchange Online
    Parameter: body (object) [body] - Group object containing displayName, username, groupType, description, owners, members, membershipRules, primDomain, tenantFilter
    Response: Returns a response object with the following properties:
    Response: - Results (array): Array of status messages for each tenant
    Response: On success: "Successfully created group [displayName] for [tenant]"
    Response: On error: "Failed to create group. [displayName] for [tenant] [error details]"
    Example: {
      "Results": [
        "Successfully created group Marketing for contoso.onmicrosoft.com",
        "Failed to create group Sales for fabrikam.onmicrosoft.com [error details]"
      ]
    }
    Error: Returns error details if the operation fails to create the group for any tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $SelectedTenants = if ('AllTenants' -in $SelectedTenants) { (Get-Tenants).defaultDomainName } else { $Request.body.tenantFilter.value ? $Request.body.tenantFilter.value : $Request.body.tenantFilter }
    Write-LogMessage -headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev Debug


    $GroupObject = $Request.body

    $Results = foreach ($tenant in $SelectedTenants) {
        try {
            $Email = if ($GroupObject.primDomain.value) { "$($GroupObject.username)@$($GroupObject.primDomain.value)" } else { "$($GroupObject.username)@$($tenant)" }
            if ($GroupObject.groupType -in 'Generic', 'azurerole', 'dynamic', 'm365') {

                $BodyParams = [pscustomobject] @{
                    'displayName'      = $GroupObject.displayName
                    'description'      = $GroupObject.description
                    'mailNickname'     = $GroupObject.username
                    mailEnabled        = [bool]$false
                    securityEnabled    = [bool]$true
                    isAssignableToRole = [bool]($GroupObject | Where-Object -Property groupType -EQ 'AzureRole')
                }
                if ($GroupObject.membershipRules) {
                    $BodyParams | Add-Member -NotePropertyName 'membershipRule' -NotePropertyValue ($GroupObject.membershipRules)
                    $BodyParams | Add-Member -NotePropertyName 'membershipRuleProcessingState' -NotePropertyValue 'On'
                    if ($GroupObject.groupType -eq 'm365') {
                        $BodyParams | Add-Member -NotePropertyName 'groupTypes' -NotePropertyValue @('Unified', 'DynamicMembership')
                        $BodyParams.mailEnabled = $true
                    }
                    else {
                        $BodyParams | Add-Member -NotePropertyName 'groupTypes' -NotePropertyValue @('DynamicMembership')
                    }
                    # Skip adding static members if we're using dynamic membership
                    $SkipStaticMembers = $true
                }
                elseif ($GroupObject.groupType -eq 'm365') {
                    $BodyParams | Add-Member -NotePropertyName 'groupTypes' -NotePropertyValue @('Unified')
                    $BodyParams.mailEnabled = $true
                }
                if ($GroupObject.owners) {
                    $BodyParams | Add-Member -NotePropertyName 'owners@odata.bind' -NotePropertyValue (($GroupObject.owners) | ForEach-Object { "https://graph.microsoft.com/v1.0/users/$($_.value)" })
                    $BodyParams.'owners@odata.bind' = @($BodyParams.'owners@odata.bind')
                }
                if ($GroupObject.members -and -not $SkipStaticMembers) {
                    $BodyParams | Add-Member -NotePropertyName 'members@odata.bind' -NotePropertyValue (($GroupObject.members) | ForEach-Object { "https://graph.microsoft.com/v1.0/users/$($_.value)" })
                    $BodyParams.'members@odata.bind' = @($BodyParams.'members@odata.bind')
                }
                $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $tenant -type POST -body (ConvertTo-Json -InputObject $BodyParams -Depth 10) -Verbose
            }
            else {
                if ($GroupObject.groupType -eq 'dynamicDistribution') {
                    $ExoParams = @{
                        Name               = $GroupObject.displayName
                        RecipientFilter    = $GroupObject.membershipRules
                        PrimarySmtpAddress = $Email
                    }
                    $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'New-DynamicDistributionGroup' -cmdParams $ExoParams
                }
                else {
                    $ExoParams = @{
                        Name                               = $GroupObject.displayName
                        Alias                              = $GroupObject.username
                        Description                        = $GroupObject.description
                        PrimarySmtpAddress                 = $Email
                        Type                               = $GroupObject.groupType
                        RequireSenderAuthenticationEnabled = [bool]!$GroupObject.allowExternal
                    }
                    if ($GroupObject.owners) {
                        $ExoParams.ManagedBy = @($GroupObject.owners.value)
                    }
                    if ($GroupObject.members) {
                        $ExoParams.Members = @($GroupObject.members.value)
                    }
                    $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'New-DistributionGroup' -cmdParams $ExoParams
                }
            }

            "Successfully created group $($GroupObject.displayName) for $($tenant)"
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $tenant -message "Created group $($GroupObject.displayName) with id $($GraphRequest.id)" -Sev Info
            $StatusCode = [HttpStatusCode]::OK
        }
        catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $tenant -message "Group creation API failed. $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            "Failed to create group. $($GroupObject.displayName) for $($tenant) $($ErrorMessage.NormalizedError)"
            $StatusCode = [HttpStatusCode]::InternalServerError
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = @($Results) }
        })
}
