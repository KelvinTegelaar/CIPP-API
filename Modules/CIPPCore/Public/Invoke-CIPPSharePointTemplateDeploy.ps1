function Invoke-CIPPSharePointTemplateDeploy {
    <#
    .SYNOPSIS
    Deploy a SharePoint provisioning template to a single tenant

    .DESCRIPTION
    Provisions every site template in a SharePoint provisioning template against one tenant.
    Each site has a siteType (sharePoint or teams). When overrideSiteType is set, the template
    siteType is used for every site; otherwise each site's own siteType applies. Teams sites
    are created via the Teams API so channels and Teams functionality stay intact, then
    document libraries are added to the backing SharePoint site. SharePoint sites use the
    plain site-creation path. Root-level and per-library permissions are applied by group
    display name, optionally creating missing groups as security groups.

    .PARAMETER TemplateData
    The deserialized template object (templateName, siteType, overrideSiteType, createMissingGroups, siteTemplates)

    .PARAMETER SiteOwner
    UPN set as the owner of every site or Team the template creates

    .PARAMETER TenantFilter
    The tenant to deploy to

    .PARAMETER DeploymentId
    Optional async deployment job id (from New-CIPPAsyncDeployment). When provided, per-site
    progress is written to the CacheAsyncDeployments row so the frontend can poll it live.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $TemplateData,

        [Parameter(Mandatory = $true)]
        [string]$SiteOwner,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$DeploymentId,

        $APIName = 'Deploy SharePoint Template',
        $Headers
    )

    # Live status reporting via the shared async deployment functions.
    function Update-DeployStep {
        param($Index, $Status, $Message)
        if (-not $DeploymentId) { return }
        Set-CIPPAsyncDeploymentStep -JobId $DeploymentId -Name $TenantFilter -StepIndex $Index -StepStatus $Status -Message $Message
    }

    $CreateMissingGroups = $TemplateData.createMissingGroups -eq $true
    $SkipIfExists = $TemplateData.skipIfExists -eq $true

    $Results = [System.Collections.Generic.List[string]]::new()
    $SiteIndex = -1
    foreach ($SiteTemplate in $TemplateData.siteTemplates) {
        $SiteIndex++
        # Resolve site type: template override wins, otherwise the site's own siteType.
        # Select controls may persist {label,value}; unwrap to the string value.
        $RawSiteType = if ($TemplateData.overrideSiteType -eq $true) {
            $TemplateData.siteType
        } else {
            $SiteTemplate.siteType
        }
        $SiteType = [string]($RawSiteType.value ?? $RawSiteType)
        if ($SiteType -notin @('sharePoint', 'teams')) { $SiteType = 'sharePoint' }
        $IsTeams = $SiteType -eq 'teams'

        # Step counter for this site: prerequisites, create, site permissions, then one step
        # per library. Shown as 'Step x of y' in the live progress messages.
        $TotalSteps = 3 + @($SiteTemplate.libraries).Count
        try {
            Update-DeployStep -Index $SiteIndex -Status 'running' -Message "Step 1 of ${TotalSteps}: Checking prerequisites"
            # Skip if exists: leave pre-existing sites/teams completely untouched — no
            # libraries or permission changes are applied to anything this run didn't create.
            if ($SkipIfExists) {
                $AlreadyExists = $false
                if ($IsTeams) {
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
                    Update-DeployStep -Index $SiteIndex -Status 'succeeded' -Message 'Skipped: already exists'
                    continue
                }
            }
            # Create the container first: a full Team (Teams API) so all Teams functionality
            # stays intact, or a plain SharePoint site otherwise.
            if ($IsTeams) {
                Update-DeployStep -Index $SiteIndex -Status 'running' -Message "Step 2 of ${TotalSteps}: Creating Team and waiting for its SharePoint site"
                $Team = New-CIPPTeam -DisplayName $SiteTemplate.displayName -Description ($SiteTemplate.description ?? '') -Owner $SiteOwner -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                $SiteUrl = $Team.SiteUrl
                $Results.Add("[$TenantFilter] Created Team '$($SiteTemplate.displayName)' with site $SiteUrl")
                $RawLanguage = [string](($SiteTemplate.language.value ?? $SiteTemplate.language))
                if ($RawLanguage -and $RawLanguage -ne 'default') {
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): site language '$RawLanguage' was not applied — Teams sites use the tenant default SharePoint language.")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "SharePoint template site '$($SiteTemplate.displayName)': language LCID $RawLanguage skipped for Teams site (tenant default applies)." -sev Info
                }
            } else {
                Update-DeployStep -Index $SiteIndex -Status 'running' -Message "Step 2 of ${TotalSteps}: Creating SharePoint site"
                $SiteParams = @{
                    SiteName        = $SiteTemplate.displayName
                    SiteDescription = ($SiteTemplate.description ?? $SiteTemplate.displayName)
                    SiteOwner       = $SiteOwner
                    TenantFilter    = $TenantFilter
                    Headers         = $Headers
                    APIName         = $APIName
                }
                # Team site vs Communication — createAs may persist {label,value}; default Team.
                $RawCreateAs = [string]($SiteTemplate.createAs.value ?? $SiteTemplate.createAs)
                $SiteParams.TemplateName = if ($RawCreateAs -in @('Team', 'Communication')) {
                    $RawCreateAs
                } else {
                    'Team'
                }
                # language "default" (or missing) → Lcid 0 so New-CIPPSharepointSite uses tenant default.
                # A specific language → pass that LCID. Always pass Lcid so we don't fall back to the
                # helper's legacy English default used by AddSite.
                $RawLanguage = [string](($SiteTemplate.language.value ?? $SiteTemplate.language))
                $ParsedLcid = 0
                if ($RawLanguage -and $RawLanguage -ne 'default') {
                    if (-not [int]::TryParse($RawLanguage, [ref]$ParsedLcid) -or $ParsedLcid -le 0) {
                        throw "Site language '$RawLanguage' on '$($SiteTemplate.displayName)' is not a valid LCID."
                    }
                }
                $SiteParams.Lcid = $ParsedLcid
                $null = New-CIPPSharepointSite @SiteParams
                $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
                $SitePath = $SiteTemplate.displayName -replace ' ' -replace '[^A-Za-z0-9-]'
                $SiteUrl = "https://$($SharePointInfo.TenantName).sharepoint.com/sites/$SitePath"
                $Results.Add("[$TenantFilter] Created site '$($SiteTemplate.displayName)' at $SiteUrl")
            }

            # Track template-defined sub-steps (site perms, libraries, library perms). A failure
            # here must mark this site step failed — do not report succeeded after swallowing errors.
            $StepFailures = [System.Collections.Generic.List[string]]::new()

            # Root-level permissions, grouped per permission level.
            # Set-CIPPSharePointObjectPermission only throws when nothing was granted. Partial
            # outcomes (some Failed / Not found) still return a message — treat those as failures.
            Update-DeployStep -Index $SiteIndex -Status 'running' -Message "Step 3 of ${TotalSteps}: Applying site permissions"
            $RootPermGroups = @($SiteTemplate.permissions) | Group-Object -Property permissionLevel
            foreach ($PermGroup in $RootPermGroups) {
                # Frontend may store principals as plain strings or autocomplete {label,value} objects.
                $GroupNames = @($PermGroup.Group | ForEach-Object { $_.principal.value ?? $_.principal }) | Where-Object { $_ }
                try {
                    $PermResult = Set-CIPPSharePointObjectPermission -SiteUrl $SiteUrl -PermissionLevel $PermGroup.Name -GroupNames $GroupNames -CreateMissingGroups:$CreateMissingGroups -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): $PermResult")
                    if ($PermResult -match 'Failed for|Not found by display name') {
                        $FailMsg = "Root permissions ($($PermGroup.Name)): $PermResult"
                        $StepFailures.Add($FailMsg)
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "SharePoint template site '$($SiteTemplate.displayName)': $FailMsg" -sev Error
                    }
                } catch {
                    $FailMsg = "Root permissions ($($PermGroup.Name)) failed: $($_.Exception.Message)"
                    $StepFailures.Add($FailMsg)
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): $FailMsg")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "SharePoint template site '$($SiteTemplate.displayName)': $FailMsg" -sev Error
                }
            }

            # Then the document libraries via the SharePoint module.
            $LibraryStep = 3
            foreach ($Library in $SiteTemplate.libraries) {
                $LibraryStep++
                try {
                    Update-DeployStep -Index $SiteIndex -Status 'running' -Message "Step $LibraryStep of ${TotalSteps}: Creating library '$($Library.name)'"
                    $NewLibrary = New-CIPPSharePointLibrary -SiteUrl $SiteUrl -LibraryName $Library.name -Description ($Library.description ?? '') -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): library '$($Library.name)' $($NewLibrary.Created ? 'created' : 'already existed')")

                    $LibPermGroups = @($Library.permissions) | Group-Object -Property permissionLevel
                    foreach ($PermGroup in $LibPermGroups) {
                        $GroupNames = @($PermGroup.Group | ForEach-Object { $_.principal.value ?? $_.principal }) | Where-Object { $_ }
                        try {
                            $PermResult = Set-CIPPSharePointObjectPermission -SiteUrl $SiteUrl -ListId $NewLibrary.ListId -PermissionLevel $PermGroup.Name -GroupNames $GroupNames -CreateMissingGroups:$CreateMissingGroups -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
                            $Results.Add("[$TenantFilter] $($SiteTemplate.displayName)/$($Library.name): $PermResult")
                            if ($PermResult -match 'Failed for|Not found by display name') {
                                $FailMsg = "Library '$($Library.name)' permissions ($($PermGroup.Name)): $PermResult"
                                $StepFailures.Add($FailMsg)
                                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "SharePoint template site '$($SiteTemplate.displayName)': $FailMsg" -sev Error
                            }
                        } catch {
                            $FailMsg = "Library '$($Library.name)' permissions ($($PermGroup.Name)) failed: $($_.Exception.Message)"
                            $StepFailures.Add($FailMsg)
                            $Results.Add("[$TenantFilter] $($SiteTemplate.displayName)/$($Library.name): $FailMsg")
                            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "SharePoint template site '$($SiteTemplate.displayName)': $FailMsg" -sev Error
                        }
                    }
                } catch {
                    $FailMsg = "Library '$($Library.name)' failed: $($_.Exception.Message)"
                    $StepFailures.Add($FailMsg)
                    $Results.Add("[$TenantFilter] $($SiteTemplate.displayName): $FailMsg")
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "SharePoint template site '$($SiteTemplate.displayName)': $FailMsg" -sev Error
                }
            }

            if ($StepFailures.Count -gt 0) {
                $FailureSummary = $StepFailures -join '; '
                $Results.Add("[$TenantFilter] Site '$($SiteTemplate.displayName)' completed with failures at $SiteUrl")
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "SharePoint template site '$($SiteTemplate.displayName)' deployed with failures: $FailureSummary" -sev Error
                Update-DeployStep -Index $SiteIndex -Status 'failed' -Message $FailureSummary
            } else {
                Update-DeployStep -Index $SiteIndex -Status 'succeeded' -Message "Completed all $TotalSteps steps. Deployed at $SiteUrl"
            }
        } catch {
            $Results.Add("[$TenantFilter] Failed to deploy '$($SiteTemplate.displayName)': $($_.Exception.Message)")
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to deploy SharePoint template site '$($SiteTemplate.displayName)': $($_.Exception.Message)" -sev Error
            Update-DeployStep -Index $SiteIndex -Status 'failed' -Message $_.Exception.Message
        }
    }
    return $Results
}
