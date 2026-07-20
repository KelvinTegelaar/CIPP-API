function Invoke-CIPPSharePointTemplateDeploy {
    <#
    .SYNOPSIS
    Deploy a SharePoint provisioning template to a single tenant

    .DESCRIPTION
    Provisions every site template in a SharePoint provisioning template against one tenant.
    When the template is marked createAsTeams the container is created as a full Microsoft
    Team first (via the Teams API, so channels and Teams functionality stay intact) and the
    document libraries are added to the backing SharePoint site afterwards. Otherwise a plain
    SharePoint site is created. Root-level and per-library permissions are applied by group
    display name, optionally creating missing groups as security groups.

    .PARAMETER TemplateData
    The deserialized template object (templateName, createAsTeams, createMissingGroups, siteTemplates)

    .PARAMETER SiteOwner
    UPN set as the owner of every site or Team the template creates

    .PARAMETER TenantFilter
    The tenant to deploy to
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TemplateData,

        [Parameter(Mandatory = $true)]
        [string]$SiteOwner,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $APIName = 'Deploy SharePoint Template',
        $Headers
    )

    # Extracts the group display name from a stored permission entry: the frontend saves plain
    # strings, but older entries may be autocomplete objects ({label,value}).
    $GetPrincipalName = { param($Principal) $Principal.value ?? $Principal }
    $CreateMissingGroups = $TemplateData.createMissingGroups -eq $true
    $SkipIfExists = $TemplateData.skipIfExists -eq $true

    $Results = [System.Collections.Generic.List[string]]::new()
    foreach ($SiteTemplate in $TemplateData.siteTemplates) {
        try {
            # Skip if exists: leave pre-existing sites/teams completely untouched — no
            # libraries or permission changes are applied to anything this run didn't create.
            if ($SkipIfExists) {
                $AlreadyExists = $false
                if ($TemplateData.createAsTeams -eq $true) {
                    $EscapedName = $SiteTemplate.displayName -replace "'", "''"
                    $ExistingGroups = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$EscapedName'&`$select=id" -tenantid $TenantFilter -AsApp $true
                    $AlreadyExists = @($ExistingGroups).Count -gt 0
                } else {
                    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
                    $SitePath = $SiteTemplate.displayName -replace ' ' -replace '[^A-Za-z0-9-]'
                    try {
                        $ExistingSite = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$($SharePointInfo.TenantName).sharepoint.com:/sites/$($SitePath)?`$select=id" -tenantid $TenantFilter -AsApp $true
                        $AlreadyExists = [bool]$ExistingSite.id
                    } catch {
                        # 404 means the site does not exist yet, which is the normal path.
                        $AlreadyExists = $false
                    }
                }
                if ($AlreadyExists) {
                    $Results.Add("[$TenantFilter] Skipped '$($SiteTemplate.displayName)': already exists and Skip if exists is enabled.")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Skipped SharePoint template site '$($SiteTemplate.displayName)': already exists." -sev Info
                    continue
                }
            }
            # Create the container first: a full Team (Teams API) so all Teams functionality
            # stays intact, or a plain SharePoint site otherwise.
            if ($TemplateData.createAsTeams -eq $true) {
                $Team = New-CIPPTeam -DisplayName $SiteTemplate.displayName -Description ($SiteTemplate.description ?? '') -Owner $SiteOwner -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                $SiteUrl = $Team.SiteUrl
                $Results.Add("[$TenantFilter] Created Team '$($SiteTemplate.displayName)' with site $SiteUrl")
            } else {
                $null = New-CIPPSharepointSite -SiteName $SiteTemplate.displayName -SiteDescription ($SiteTemplate.description ?? $SiteTemplate.displayName) -SiteOwner $SiteOwner -TemplateName 'Team' -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
                $SitePath = $SiteTemplate.displayName -replace ' ' -replace '[^A-Za-z0-9-]'
                $SiteUrl = "https://$($SharePointInfo.TenantName).sharepoint.com/sites/$SitePath"
                $Results.Add("[$TenantFilter] Created site '$($SiteTemplate.displayName)' at $SiteUrl")
            }

            # Root-level permissions, grouped per permission level.
            $RootPermGroups = @($SiteTemplate.permissions) | Group-Object -Property permissionLevel
            foreach ($PermGroup in $RootPermGroups) {
                $GroupNames = @($PermGroup.Group | ForEach-Object { & $GetPrincipalName $_.principal }) | Where-Object { $_ }
                try {
                    $PermResult = Set-CIPPSharePointObjectPermission -SiteUrl $SiteUrl -PermissionLevel $PermGroup.Name -GroupNames $GroupNames -CreateMissingGroups:$CreateMissingGroups -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): $PermResult")
                } catch {
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): root permissions failed - $($_.Exception.Message)")
                }
            }

            # Then the document libraries via the SharePoint module.
            foreach ($Library in $SiteTemplate.libraries) {
                try {
                    $NewLibrary = New-CIPPSharePointLibrary -SiteUrl $SiteUrl -LibraryName $Library.name -Description ($Library.description ?? '') -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): library '$($Library.name)' $($NewLibrary.Created ? 'created' : 'already existed')")

                    $LibPermGroups = @($Library.permissions) | Group-Object -Property permissionLevel
                    foreach ($PermGroup in $LibPermGroups) {
                        $GroupNames = @($PermGroup.Group | ForEach-Object { & $GetPrincipalName $_.principal }) | Where-Object { $_ }
                        try {
                            $PermResult = Set-CIPPSharePointObjectPermission -SiteUrl $SiteUrl -ListId $NewLibrary.ListId -PermissionLevel $PermGroup.Name -GroupNames $GroupNames -CreateMissingGroups:$CreateMissingGroups -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                            $Results.Add("[$TenantFilter] $($SiteTemplate.displayName)/$($Library.name): $PermResult")
                        } catch {
                            $Results.Add("[$TenantFilter] $($SiteTemplate.displayName)/$($Library.name): permissions failed - $($_.Exception.Message)")
                        }
                    }
                } catch {
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): library '$($Library.name)' failed - $($_.Exception.Message)")
                }
            }
        } catch {
            $Results.Add("[$TenantFilter] Failed to deploy '$($SiteTemplate.displayName)': $($_.Exception.Message)")
        }
    }
    return $Results
}
