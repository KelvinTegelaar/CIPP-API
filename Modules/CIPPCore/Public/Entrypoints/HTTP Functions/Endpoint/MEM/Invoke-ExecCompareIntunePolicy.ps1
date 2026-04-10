function Invoke-ExecCompareIntunePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
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
    }

    try {
        $Body = $Request.Body
        $SourceA = $Body.sourceA
        $SourceB = $Body.sourceB

        if (-not $SourceA -or -not $SourceB) {
            throw 'Both sourceA and sourceB are required'
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
                $Table = Get-CippTable -tablename 'templates'
                $Filter = "PartitionKey eq 'IntuneTemplate' and RowKey eq '$($Source.templateGuid)'"
                $TemplateEntity = Get-CIPPAzDataTableEntity @Table -Filter $Filter

                if (-not $TemplateEntity) {
                    throw "$Label : Template with GUID '$($Source.templateGuid)' not found"
                }

                $JSONData = $TemplateEntity.JSON | ConvertFrom-Json -Depth 100
                $PolicyObj = $JSONData.RAWJson | ConvertFrom-Json -Depth 100
                $TemplateType = $JSONData.Type

                return @{
                    Object       = $PolicyObj
                    TemplateType = $TemplateType
                    Label        = "$($JSONData.Displayname) (Template)"
                    RawData      = $PolicyObj
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
                throw "$Label : Invalid source type '$($Source.type)'. Must be 'template', 'tenantPolicy', or 'communityRepo'"
            }
        }

        $ResolvedA = Resolve-PolicySource -Source $SourceA -Label 'Source A'
        $ResolvedB = Resolve-PolicySource -Source $SourceB -Label 'Source B'

        # Determine compare type
        $CompareParams = @{
            ReferenceObject  = $ResolvedA.Object
            DifferenceObject = $ResolvedB.Object
        }

        if ($ResolvedA.TemplateType -eq 'Catalog' -and $ResolvedB.TemplateType -eq 'Catalog') {
            $CompareParams['CompareType'] = 'Catalog'
        }

        # Run the comparison
        $ComparisonResults = @(Compare-CIPPIntuneObject @CompareParams)

        $ResultBody = @{
            Results      = $ComparisonResults
            sourceALabel = $ResolvedA.Label
            sourceBLabel = $ResolvedB.Label
            sourceAData  = $ResolvedA.RawData
            sourceBData  = $ResolvedB.RawData
            identical    = ($ComparisonResults.Count -eq 0)
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
