Function Invoke-AddRetentionCompliancePolicyTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.RetentionCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $PolicyAllowedFields = @(
        'Name', 'Comment', 'Enabled', 'RestrictiveRetention',
        'ExchangeLocation', 'ExchangeLocationException',
        'SharePointLocation', 'SharePointLocationException',
        'OneDriveLocation', 'OneDriveLocationException',
        'ModernGroupLocation', 'ModernGroupLocationException',
        'TeamsChannelLocation', 'TeamsChannelLocationException',
        'TeamsChatLocation', 'TeamsChatLocationException',
        'PublicFolderLocation',
        'SkypeLocation', 'SkypeLocationException'
    )
    $RuleAllowedFields = @(
        'Name', 'Policy', 'Comment',
        'RetentionDuration', 'RetentionComplianceAction',
        'ExpirationDateOption', 'PublishComplianceTag',
        'ApplyComplianceTag', 'ContentMatchQuery',
        'ContentDateFrom', 'ContentDateTo'
    )
    $LocationFields = $PolicyAllowedFields | Where-Object { $_ -like '*Location*' }

    # Get-RetentionCompliancePolicy returns location params as empty arrays at the policy level — the actual
    # scope is encoded in the Workload comma-separated string. This is the canonical source from MS's API,
    # so we expand it into proper location params at template-build time. Templates stored this way are
    # fully deployable; the deploy endpoint and standard don't need to know anything about Workload.
    function Expand-WorkloadToLocations {
        param($Clean, $WorkloadString)
        if ([string]::IsNullOrWhiteSpace([string]$WorkloadString)) { return }
        $workloads = ($WorkloadString -split ',') | ForEach-Object { $_.Trim() }
        $map = @{
            'Exchange'            = 'ExchangeLocation'
            'SharePoint'          = 'SharePointLocation'
            'OneDriveForBusiness' = 'OneDriveLocation'
            'Skype'               = 'SkypeLocation'
            'ModernGroup'         = 'ModernGroupLocation'
            'PublicFolder'        = 'PublicFolderLocation'
        }
        foreach ($wl in $workloads) {
            if ($map.ContainsKey($wl)) { $Clean[$map[$wl]] = 'All' }
        }
        if ('Teams' -in $workloads) {
            $Clean['TeamsChatLocation'] = 'All'
            $Clean['TeamsChannelLocation'] = 'All'
        }
        # DynamicScope intentionally skipped — adaptive scope is its own parameter set.
    }

    try {
        $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
        $Identity = $Request.Body.Identity ?? $Request.Body.Name ?? $Request.Body.name
        $GUID = (New-Guid).GUID

        # Two entry paths:
        # 1) UI list-page action — we get { tenantFilter, Identity } and fetch the live policy + rule.
        # 2) Direct API/PowerShellCommand body — caller already supplied a JSON template.
        $Policy = $null
        $Rule = $null
        if ($TenantFilter -and $Identity) {
            $Policy = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionCompliancePolicy' -cmdParams @{ Identity = $Identity; DistributionDetail = $true } -Compliance -AsApp | Select-Object -First 1
            if (-not $Policy) {
                throw "Retention policy '$Identity' not found in tenant $TenantFilter."
            }
            try {
                $Rule = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RetentionComplianceRule' -cmdParams @{ Policy = $Identity } -Compliance -AsApp | Select-Object -First 1
            } catch {
                Write-Information "No retention rule found for policy '$Identity': $($_.Exception.Message)"
            }
            $Source = $Policy
        } else {
            $Source = if ($Request.Body.PowerShellCommand) {
                $Request.Body.PowerShellCommand | ConvertFrom-Json
            } else {
                [pscustomobject]$Request.Body
            }
        }

        $Clean = Format-CIPPCompliancePolicyParams -Source $Source -AllowedFields $PolicyAllowedFields -LocationFields $LocationFields

        # Locations come back empty from Get — fill them in from Workload.
        $hasAnyLocation = $false
        foreach ($loc in $LocationFields) {
            if ($Clean.ContainsKey($loc)) { $hasAnyLocation = $true; break }
        }
        if (-not $hasAnyLocation) {
            Expand-WorkloadToLocations -Clean $Clean -WorkloadString $Source.Workload
        }

        # Pull the rule's settings into RuleParams so the template carries the retention duration/action.
        if ($Rule) {
            $RuleClean = Format-CIPPCompliancePolicyParams -Source $Rule -AllowedFields $RuleAllowedFields
            $RuleClean.Remove('Policy') | Out-Null  # added at deploy time, not stored
            $Clean['RuleParams'] = [pscustomobject]$RuleClean
        } elseif ($Source.RuleParams) {
            $Clean['RuleParams'] = $Source.RuleParams
        }

        $Ordered = [ordered]@{
            name     = $Clean['Name'] ?? $Source.Name ?? $Source.name
            comments = $Source.Comment ?? $Source.comments
        }
        foreach ($k in $Clean.Keys) {
            if ($Ordered.Contains($k)) { continue }
            $Ordered[$k] = $Clean[$k]
        }

        $JSON = ([pscustomobject]$Ordered | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'RetentionCompliancePolicyTemplate'
        }
        $Result = "Successfully created Retention Compliance Policy Template: $($Ordered['name']) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Retention Compliance Policy Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
