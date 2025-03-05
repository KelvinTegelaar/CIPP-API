function Invoke-CIPPStandardGroupTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) GroupTemplate
    .SYNOPSIS
        (Label) Group Template
    .DESCRIPTION
        (Helptext) Deploy and manage group templates.
        (DocsDescription) Deploy and manage group templates.
    .NOTES
        MULTI
            True
        CAT
            Templates
        DISABLEDFEATURES
            
        IMPACT
            Medium Impact
        ADDEDDATE
            2023-12-30
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"groupTemplate","label":"Select Group Template","api":{"url":"/api/ListGroupTemplates","labelField":"Displayname","valueField":"GUID","queryKey":"ListGroupTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/
    #>
    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'GroupTemplate'

    If ($Settings.remediate -eq $true) {
        #Because the list name changed from TemplateList to groupTemplate by someone :@, we'll need to set it back to TemplateList
        $Settings.groupTemplate ? ($Settings | Add-Member -NotePropertyName 'TemplateList' -NotePropertyValue $Settings.groupTemplate) : $null
        Write-Host "Settings: $($Settings.TemplateList | ConvertTo-Json)"
        foreach ($Template in $Settings.TemplateList) {
            try {
                $Table = Get-CippTable -tablename 'templates'
                $Filter = "PartitionKey eq 'GroupTemplate' and RowKey eq '$($Template.value)'"
                $groupobj = (Get-AzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json
                $email = if ($groupobj.domain) { "$($groupobj.username)@$($groupobj.domain)" } else { "$($groupobj.username)@$($Tenant)" }
                $CheckExististing = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $tenant | Where-Object -Property displayName -EQ $groupobj.displayname
                $BodyToship = [pscustomobject] @{
                    'displayName'      = $groupobj.Displayname
                    'description'      = $groupobj.Description
                    'mailNickname'     = $groupobj.username
                    mailEnabled        = [bool]$false
                    securityEnabled    = [bool]$true
                }
                if ($groupobj.groupType -eq 'AzureRole') {
                    $BodyToship | Add-Member -NotePropertyName 'isAssignableToRole' -NotePropertyValue $true
                }
                if ($groupobj.membershipRules) {
                    $BodyToship | Add-Member -NotePropertyName 'membershipRule' -NotePropertyValue ($groupobj.membershipRules)
                    $BodyToship | Add-Member -NotePropertyName 'groupTypes' -NotePropertyValue @('DynamicMembership')
                    $BodyToship | Add-Member -NotePropertyName 'membershipRuleProcessingState' -NotePropertyValue 'On'
                }
                if (!$CheckExististing) {
                    $ActionType = 'create'
                    if ($groupobj.groupType -in 'Generic', 'azurerole', 'dynamic') {
                        $GraphRequest = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $tenant -type POST -body (ConvertTo-Json -InputObject $BodyToship -Depth 10) -verbose
                    } else {
                        if ($groupobj.groupType -eq 'dynamicdistribution') {
                            $Params = @{
                                Name               = $groupobj.Displayname
                                RecipientFilter    = $groupobj.membershipRules
                                PrimarySmtpAddress = $email
                            }
                            $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'New-DynamicDistributionGroup' -cmdParams $params
                        } else {
                            $Params = @{
                                Name                               = $groupobj.Displayname
                                Alias                              = $groupobj.username
                                Description                        = $groupobj.Description
                                PrimarySmtpAddress                 = $email
                                Type                               = $groupobj.groupType
                                RequireSenderAuthenticationEnabled = [bool]!$groupobj.AllowExternal
                            }
                            $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'New-DistributionGroup' -cmdParams $params
                        }
                    }
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Created group $($groupobj.displayname) with id $($GraphRequest.id) " -Sev 'Info'
                } else {
                    $ActionType = 'update'
                    if ($groupobj.groupType -in 'Generic', 'azurerole', 'dynamic') {
                        $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($CheckExististing.id)" -tenantid $tenant -type PATCH -body (ConvertTo-Json -InputObject $BodyToship -Depth 10) -verbose
                    } else {
                        if ($groupobj.groupType -eq 'dynamicdistribution') {
                            $Params = @{
                                Name               = $groupobj.Displayname
                                RecipientFilter    = $groupobj.membershipRules
                                PrimarySmtpAddress = $email
                            }
                            $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'Set-DynamicDistributionGroup' -cmdParams $params
                        } else {
                            $Params = @{
                                Identity                           = $groupobj.Displayname
                                Alias                              = $groupobj.username
                                Description                        = $groupobj.Description
                                PrimarySmtpAddress                 = $email
                                Type                               = $groupobj.groupType
                                RequireSenderAuthenticationEnabled = [bool]!$groupobj.AllowExternal
                            }
                            $GraphRequest = New-ExoRequest -tenantid $tenant -cmdlet 'Set-DistributionGroup' -cmdParams $params
                        }
                    }
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Group exists $($groupobj.displayname). Updated to latest settings." -Sev 'Info'

                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to $ActionType group $($groupobj.displayname). Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
}
