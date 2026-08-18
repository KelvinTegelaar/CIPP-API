function Invoke-ExecCompareIntunePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Compares an Intune policy against another policy or a stored template and returns the differences setting by setting. Handles device configurations, settings catalog policies, ADMX templates, compliance policies, driver/feature/quality update profiles, intents and app protection policies.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # URLName to TemplateType mapping (bridges frontend policy names to Get-CIPPIntunePolicy parameter)
    $URLNameToTemplateType = @{
        'DeviceConfigurations'         = 'Device'
        'ConfigurationPolicies'        = 'Catalog'
        'GroupPolicyConfigurations'    = 'Admin'
        'deviceCompliancePolicies'     = 'deviceCompliancePolicies'
        'WindowsDriverUpdateProfiles'  = 'windowsDriverUpdateProfiles'
        'WindowsFeatureUpdateProfiles' = 'windowsFeatureUpdateProfiles'
        'windowsQualityUpdatePolicies' = 'windowsQualityUpdatePolicies'
        'windowsQualityUpdateProfiles' = 'windowsQualityUpdateProfiles'
        'Intents'                      = 'Intents'
        'ManagedAppPolicies'           = 'AppProtection'
    }

    try {
        $Body = $Request.Body
        $SourceA = $Body.sourceA
        $SourceB = $Body.sourceB

        if (-not $SourceA -or -not $SourceB) {
            throw 'Both sourceA and sourceB are required'
        }

        # AnyTenant: source tenants must be in the caller's scope; Get-Tenants is narrowed
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            foreach ($SourceTenant in @($SourceA.tenantFilter, $SourceB.tenantFilter)) {
                if ($SourceTenant -and -not (Get-Tenants -TenantFilter $SourceTenant)) {
                    throw 'Access to this tenant is not allowed'
                }
            }
        }

        # Load a stored Intune template. When a tenant is supplied the template is put through the
        # same preparation the IntuneTemplate standard uses - nesting repair, reusable settings sync
        # and text replacement - so a comparison made here matches what drift reports for that tenant.
        function Get-ComparisonTemplate {
            param(
                [Parameter(Mandatory = $true)]
                [string]$TemplateGuid,
                [string]$TenantFilter,
                [string]$Label,
                # Set when the caller only needs the template's identity and type in order to find
                # the tenant's own copy. Skips the reusable settings sync, which writes to the
                # tenant and is the other source's job to run.
                [switch]$SkipReusableSync
            )

            $Table = Get-CippTable -tablename 'templates'
            $TemplateEntity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$TemplateGuid'"

            if (-not $TemplateEntity) {
                throw "$Label : Template with GUID '$TemplateGuid' not found"
            }

            $JSONData = $TemplateEntity.JSON | ConvertFrom-Json -Depth 100
            $JSONData = Repair-CIPPIntuneTemplateNesting -Template $JSONData -Table $Table
            $RawJSON = $JSONData.RAWJson

            if ($TenantFilter) {
                if (-not $SkipReusableSync) {
                    try {
                        $ReusableSync = Sync-CIPPReusablePolicySettings -TemplateInfo $JSONData -Tenant $TenantFilter -ErrorAction Stop
                        if ($ReusableSync.RawJSON) {
                            $RawJSON = $ReusableSync.RawJSON
                        }
                    } catch {
                        Write-Warning "$Label : Failed to sync reusable policy settings - $($_.Exception.Message)"
                    }
                }
                $RawJSON = Get-CIPPTextReplacement -Text $RawJSON -TenantFilter $TenantFilter -EscapeForJson
            }

            $TemplateType = Get-CIPPIntuneTemplateType -Type $JSONData.Type -RawJson $RawJSON
            $Object = $RawJSON | ConvertFrom-Json -Depth 100

            if ($TenantFilter -and $TemplateType) {
                # The same preparation the IntuneTemplate standard applies, so both agree on what
                # the baseline is: identity comes from the template's columns for the types
                # deployment writes them onto, and a Catalog policy loses the settings this tenant
                # cannot hold, because deployment drops those before sending it.
                $Object = Merge-CIPPIntuneTemplateIdentity -Policy $Object -TemplateType $TemplateType -DisplayName $JSONData.Displayname -Description $JSONData.Description
                if ($TemplateType -eq 'Catalog') {
                    try {
                        $Object = Select-CIPPIntuneAvailableSetting -Policy $Object -TenantFilter $TenantFilter
                    } catch {
                        Write-Warning "$Label : Could not resolve available settings, comparing against the full template - $($_.Exception.Message)"
                    }
                }
            }

            return @{
                Object       = $Object
                TemplateType = $TemplateType
                DisplayName  = $JSONData.Displayname
                # The name this template's policy is deployed under, which is not always the
                # Displayname - Catalog and the update profiles are named from their payload.
                PolicyName   = if ($TemplateType) {
                    Get-CIPPIntunePolicyName -TemplateType $TemplateType -RawJSON $RawJSON -DisplayName $JSONData.Displayname
                } else {
                    $JSONData.Displayname
                }
            }
        }

        # A standard can be configured to replace a similarly named policy on deployment rather than
        # create a new one. That setting lives on the standards template, keyed by the Intune
        # template GUID, and is stored as a string by the settings form.
        function Get-StandardFuzzyDistance {
            param(
                [string]$StandardsTemplateId,
                [string]$TemplateGuid
            )

            if (-not $StandardsTemplateId) { return 0 }

            try {
                $Table = Get-CippTable -tablename 'templates'
                $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'StandardsTemplateV2' and RowKey eq '$StandardsTemplateId'"
                if (-not $Entity) { return 0 }

                $Standards = ($Entity.JSON | ConvertFrom-Json -Depth 100).standards.IntuneTemplate
                $Match = @($Standards) | Where-Object { $_.TemplateList.value -eq $TemplateGuid } | Select-Object -First 1

                if ([string]::IsNullOrWhiteSpace($Match.levenshteinDistance)) { return 0 }
                return [int]$Match.levenshteinDistance
            } catch {
                Write-Warning "Could not read the fuzzy match distance from standards template '$StandardsTemplateId': $($_.Exception.Message)"
                return 0
            }
        }

        # Resolve a source descriptor to its policy object and metadata
        function Resolve-PolicySource {
            param(
                [Parameter(Mandatory = $true)]
                $Source,
                [string]$Label
            )

            if ($Source.type -eq 'template') {
                if (-not $Source.templateGuid) {
                    throw "$Label : templateGuid is required for template sources"
                }

                # tenantFilter is optional here - supplying it resolves the template the way the
                # standard would for that tenant instead of comparing the stored template verbatim.
                $Template = Get-ComparisonTemplate -TemplateGuid $Source.templateGuid -TenantFilter $Source.tenantFilter -Label $Label
                $LabelSuffix = if ($Source.tenantFilter) { "Template, resolved for $($Source.tenantFilter)" } else { 'Template' }

                return @{
                    Object       = $Template.Object
                    TemplateType = $Template.TemplateType
                    Label        = "$($Template.DisplayName) ($LabelSuffix)"
                    RawData      = $Template.Object
                }

            } elseif ($Source.type -eq 'tenantPolicyByTemplate') {
                # Used by the drift and standards pages, which know the template a standard points at
                # but not which policy in the tenant it landed on. Matches the standard's own lookup:
                # by the template's display name and type.
                if (-not $Source.templateGuid -or -not $Source.tenantFilter) {
                    throw "$Label : templateGuid and tenantFilter are required for tenantPolicyByTemplate sources"
                }

                # Resolved for the tenant, because the name a policy is deployed under can depend on
                # tenant variables in the payload. The reusable settings sync is skipped - it writes
                # to the tenant, and the baseline source already runs it.
                $Template = Get-ComparisonTemplate -TemplateGuid $Source.templateGuid -TenantFilter $Source.tenantFilter -SkipReusableSync -Label $Label

                if (-not $Template.TemplateType) {
                    throw "$Label : Template '$($Template.DisplayName)' has no policy type and none could be inferred. Re-import the template to fix this."
                }

                $Policy = Get-CIPPIntunePolicy -TemplateType $Template.TemplateType -DisplayName $Template.PolicyName -tenantFilter $Source.tenantFilter -Headers $Headers -APINAME $APIName
                $MatchType = 'exact'
                $MatchedName = $Template.PolicyName

                # Without this the comparison would report the policy as missing while remediation
                # would happily overwrite an existing, similarly named one. Mirrors the candidate
                # selection Set-CIPPIntunePolicy performs at deployment time.
                $MaxDistance = Get-StandardFuzzyDistance -StandardsTemplateId $Source.standardsTemplateId -TemplateGuid $Source.templateGuid

                if (-not $Policy -and $MaxDistance -gt 0) {
                    $AllPolicies = @(Get-CIPPIntunePolicy -TemplateType $Template.TemplateType -tenantFilter $Source.tenantFilter -Headers $Headers -APINAME $APIName)

                    $FuzzyParams = @{
                        DisplayName      = $Template.PolicyName
                        ExistingPolicies = $AllPolicies
                        MaxDistance      = $MaxDistance
                    }
                    # Same sub-type guards the deployment applies, so a similarly named policy of a
                    # different type is not offered as the match.
                    if ($Template.TemplateType -eq 'Catalog') {
                        $FuzzyParams.NameProperty = 'name'
                        if ($Template.Object.templateReference.templateId) {
                            $FuzzyParams.TemplateId = $Template.Object.templateReference.templateId
                        }
                    } elseif ($Template.Object.'@odata.type') {
                        $FuzzyParams.ODataType = $Template.Object.'@odata.type'
                    }

                    $FuzzyResult = Find-CIPPFuzzyPolicyMatch @FuzzyParams
                    if ($FuzzyResult) {
                        $MatchType = $FuzzyResult.MatchType
                        $MatchedName = $FuzzyResult.OriginalName
                        # Re-read by id so nested settings come back expanded the way the
                        # by-name lookup returns them.
                        $Policy = Get-CIPPIntunePolicy -TemplateType $Template.TemplateType -PolicyId $FuzzyResult.Policy.id -tenantFilter $Source.tenantFilter -Headers $Headers -APINAME $APIName
                    }
                }

                if (-not $Policy) {
                    # Not an error. A template that has just been added to a drift or standards
                    # template legitimately has no policy in the tenant yet, and the caller can still
                    # show the baseline on its own, which is more useful than a failed comparison.
                    return @{
                        Object        = $null
                        Missing       = $true
                        MissingName   = $Template.PolicyName
                        FuzzyDistance = $MaxDistance
                        TemplateType  = $Template.TemplateType
                        Label         = "$($Template.PolicyName) (not deployed to $($Source.tenantFilter))"
                        RawData       = $null
                    }
                }

                $PolicyObj = $Policy.cippconfiguration | ConvertFrom-Json -Depth 100

                return @{
                    Object       = $PolicyObj
                    TemplateType = $Template.TemplateType
                    Label        = "$MatchedName ($($Source.tenantFilter))"
                    RawData      = $PolicyObj
                    MatchType    = $MatchType
                    MatchedName  = $MatchedName
                }

            } elseif ($Source.type -eq 'tenantPolicy') {
                if (-not $Source.tenantFilter -or -not $Source.policyId -or -not $Source.urlName) {
                    throw "$Label : tenantFilter, policyId, and urlName are required for tenant policy sources"
                }

                $TemplateType = $URLNameToTemplateType[$Source.urlName]
                if (-not $TemplateType) {
                    throw "$Label : Unknown policy type '$($Source.urlName)'"
                }

                $Policy = Get-CIPPIntunePolicy -TemplateType $TemplateType -PolicyID $Source.policyId -tenantFilter $Source.tenantFilter -Headers $Headers -APINAME $APIName

                if (-not $Policy) {
                    throw "$Label : Policy '$($Source.policyId)' not found in tenant '$($Source.tenantFilter)'"
                }

                $PolicyObj = $Policy.cippconfiguration | ConvertFrom-Json -Depth 100
                $DisplayName = $Policy.displayName ?? $Policy.name ?? $Source.policyId

                return @{
                    Object       = $PolicyObj
                    TemplateType = $TemplateType
                    Label        = "$DisplayName ($($Source.tenantFilter))"
                    RawData      = $PolicyObj
                }

            } elseif ($Source.type -eq 'communityRepo') {
                if (-not $Source.fullName -or -not $Source.branch -or -not $Source.path) {
                    throw "$Label : fullName, branch, and path are required for community repo sources"
                }

                $FileContent = Get-GitHubFileContents -FullName $Source.fullName -Path $Source.path -Branch $Source.branch
                if (-not $FileContent -or -not $FileContent.content) {
                    throw "$Label : Could not retrieve file '$($Source.path)' from '$($Source.fullName)' branch '$($Source.branch)'"
                }

                $ParsedJson = $FileContent.content | ConvertFrom-Json -Depth 100

                if ($ParsedJson.RowKey -and $ParsedJson.JSON) {
                    # CIPP template format — has RowKey and JSON with RAWJson inside
                    $JSONData = if ($ParsedJson.JSON -is [string]) {
                        $ParsedJson.JSON | ConvertFrom-Json -Depth 100
                    } else {
                        $ParsedJson.JSON
                    }
                    $PolicyObj = if ($JSONData.RAWJson -is [string]) {
                        $JSONData.RAWJson | ConvertFrom-Json -Depth 100
                    } else {
                        $JSONData.RAWJson
                    }
                    $TemplateType = $JSONData.Type
                    $DisplayName = $JSONData.Displayname ?? $Source.path
                } else {
                    # Raw policy format — detect type from @odata.id
                    $TemplateType = switch -Wildcard ($ParsedJson.'@odata.id') {
                        '*CompliancePolicies*' { 'deviceCompliancePolicies' }
                        '*deviceConfigurations*' { 'Device' }
                        '*DriverUpdateProfiles*' { 'windowsDriverUpdateProfiles' }
                        '*SettingsCatalog*' { 'Catalog' }
                        '*configurationPolicies*' { 'Catalog' }
                        '*managedAppPolicies*' { 'AppProtection' }
                        '*deviceAppManagement*' { 'AppProtection' }
                        '*intents*' { 'Intents' }
                        default { 'Unknown' }
                    }
                    $PolicyObj = $ParsedJson
                    $DisplayName = $ParsedJson.displayName ?? $ParsedJson.name ?? $Source.path
                }

                return @{
                    Object       = $PolicyObj
                    TemplateType = $TemplateType
                    Label        = "$DisplayName (Repo: $($Source.fullName))"
                    RawData      = $PolicyObj
                }

            } else {
                throw "$Label : Invalid source type '$($Source.type)'. Must be 'template', 'tenantPolicy', 'tenantPolicyByTemplate', or 'communityRepo'"
            }
        }

        $ResolvedA = Resolve-PolicySource -Source $SourceA -Label 'Source A'
        $ResolvedB = Resolve-PolicySource -Source $SourceB -Label 'Source B'

        # With one side absent there is nothing to diff. Report that as its own state and hand back
        # whichever side does exist, so the caller can still show it.
        if ($ResolvedA.Missing -or $ResolvedB.Missing) {
            $MissingBody = @{
                Results           = @()
                sourceALabel      = $ResolvedA.Label
                sourceBLabel      = $ResolvedB.Label
                sourceAData       = $ResolvedA.RawData
                sourceBData       = $ResolvedB.RawData
                identical         = $false
                policyMissing     = $true
                # The name that was searched for, and which side is absent, so the caller can say
                # exactly what is missing rather than just that something is.
                missingPolicyName = $ResolvedA.Missing ? $ResolvedA.MissingName : $ResolvedB.MissingName
                missingSide       = $ResolvedA.Missing ? 'baseline' : 'tenant'
                # Tells the caller whether fuzzy matching was even in play, so a "not found" can be
                # explained as "exact name only" rather than looking like a broader search failed.
                fuzzyDistance     = $ResolvedA.Missing ? $ResolvedA.FuzzyDistance : $ResolvedB.FuzzyDistance
            }

            Write-LogMessage -headers $Headers -API $APIName -message "Compared Intune policies: $($ResolvedA.Label) vs $($ResolvedB.Label) - one side does not exist" -Sev 'Info'

            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = ConvertTo-Json -Depth 100 -InputObject $MissingBody
                })
        }

        # Determine compare type
        $CompareParams = @{
            ReferenceObject  = $ResolvedA.Object
            DifferenceObject = $ResolvedB.Object
        }

        if ($ResolvedA.TemplateType -eq 'Catalog' -and $ResolvedB.TemplateType -eq 'Catalog') {
            $CompareParams['CompareType'] = 'Catalog'
        }

        # Run the comparison
        $CompareResult = Compare-CIPPIntuneObject @CompareParams
        $ComparisonResults = @($CompareResult | Where-Object { $null -ne $_ })

        $ResultBody = @{
            Results      = $ComparisonResults
            sourceALabel = $ResolvedA.Label
            sourceBLabel = $ResolvedB.Label
            sourceAData  = $ResolvedA.RawData
            sourceBData  = $ResolvedB.RawData
            identical    = ($ComparisonResults.Count -eq 0)
            # Non-exact means the tenant policy was found under a different name, which changes how
            # the result should be read - the caller says so rather than implying a name match.
            matchType    = $ResolvedB.MatchType ?? $ResolvedA.MatchType
            matchedName  = $ResolvedB.MatchedName ?? $ResolvedA.MatchedName
        }

        Write-LogMessage -headers $Headers -API $APIName -message "Compared Intune policies: $($ResolvedA.Label) vs $($ResolvedB.Label) - $($ComparisonResults.Count) differences found" -Sev 'Info'

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = ConvertTo-Json -Depth 100 -InputObject $ResultBody
            })

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to compare Intune policies: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = ConvertTo-Json -Depth 100 -InputObject @{
                    Results = "Failed to compare policies: $($ErrorMessage.NormalizedError)"
                }
            })
    }
}
