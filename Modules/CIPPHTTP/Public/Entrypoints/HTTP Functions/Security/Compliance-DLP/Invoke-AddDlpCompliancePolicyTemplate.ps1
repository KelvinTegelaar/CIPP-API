Function Invoke-AddDlpCompliancePolicyTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.DlpCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Allowlists come from the single shared source so template creation, deploy, and drift comparison
    # never diverge. 'RuleParams' is template-only (added so a PowerShellCommand body that already carries
    # RuleParams passes through). 'Policy' on rules is captured then stripped below (added at deploy time).
    $Fields = Get-CIPPDlpComplianceFieldList
    $AllowedFields = @($Fields.Policy) + 'RuleParams'
    $RuleAllowedFields = $Fields.Rule
    $LocationFields = $Fields.Location

    try {
        $GUID = (New-Guid).GUID

        $Source = if ($Request.Body.PowerShellCommand) {
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
            [pscustomobject]$Request.Body
        }

        # A policy that is pending deletion can't be redeployed, so templating it would only capture an
        # undeployable snapshot - reject rather than store it.
        if (($Source.Mode ?? '') -eq 'PendingDeletion') {
            throw "DLP policy '$($Source.Name ?? $Source.name)' is pending deletion and cannot be saved as a template."
        }

        $Clean = Format-CIPPCompliancePolicyParams -Source $Source -AllowedFields $AllowedFields -LocationFields $LocationFields

        # Defensive: drop any other Mode the cmdlets won't accept as input.
        if ($Clean.ContainsKey('Mode') -and $Clean['Mode'] -notin $Fields.ValidPolicyModes) {
            $Clean.Remove('Mode') | Out-Null
        }

        # Capture the policy's detection rules into RuleParams so the template carries the actual
        # DLP logic (sensitive info types, severity, notifications) rather than just the policy shell.
        # The list endpoint surfaces these as AssociatedRules; a policy can have more than one.
        $AssociatedRules = @($Source.AssociatedRules) | Where-Object { $_ }
        if ($AssociatedRules.Count -gt 0) {
            $RuleParams = foreach ($Rule in $AssociatedRules) {
                $RuleClean = Format-CIPPCompliancePolicyParams -Source $Rule -AllowedFields $RuleAllowedFields
                $RuleClean.Remove('Policy') | Out-Null  # added at deploy time, not stored
                # Advanced-mode rules keep only the AdvancedRule JSON blob, simple-mode rules only the
                # flat condition params - the cmdlets reject a mix (see Resolve-CIPPDlpAdvancedRule).
                $RuleClean = Resolve-CIPPDlpAdvancedRule -Source $Rule -RuleParams $RuleClean
                foreach ($SitField in @('ContentContainsSensitiveInformation', 'ExceptIfContentContainsSensitiveInformation')) {
                    if ($RuleClean.ContainsKey($SitField)) {
                        $RuleClean[$SitField] = @(ConvertTo-CIPPSensitiveInformationType -SensitiveInformation $RuleClean[$SitField])
                    }
                }
                # Get-* returns IncidentReportContent as a comma-joined string; store it as the array
                # the New-/Set-* cmdlets expect (a ReportContentOption[]).
                if ($RuleClean.ContainsKey('IncidentReportContent') -and $RuleClean['IncidentReportContent'] -is [string]) {
                    $RuleClean['IncidentReportContent'] = @($RuleClean['IncidentReportContent'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                }
                [pscustomobject]$RuleClean
            }
            $Clean['RuleParams'] = @($RuleParams)
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
            PartitionKey = 'DlpCompliancePolicyTemplate'
        }
        $Result = "Successfully created DLP Compliance Policy Template: $($Ordered['name']) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create DLP Compliance Policy Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
