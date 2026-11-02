Function Invoke-AddSensitivityLabelTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitivityLabel.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Captured labels (Get-Label output) and manual JSON are stored as-is; the read shape (LabelActions etc.)
    # is normalized to deploy parameters at deploy time by Set-CIPPSensitivityLabel. We only keep the fields
    # that matter for re-deployment and drop read-only Get-Label metadata (Guid, ImmutableId, WhenCreated...).
    # The parent label name rides along because the ParentId GUID it accompanies only means something in the
    # tenant the label was captured from - Set-CIPPSensitivityLabel re-resolves the parent by name.
    $KeepFields = @(Get-CIPPSensitivityLabelField) +
    @('LabelActions', 'PolicyParams', 'Disabled', 'comments', 'ParentLabelDisplayName', 'ParentLabelName')

    try {
        $GUID = (New-Guid).GUID

        $Source = if ($Request.Body.PowerShellCommand) {
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
            [pscustomobject]$Request.Body
        }

        # A captured Get-Label object carries LabelActions; hand-authored flat JSON does not. Only the
        # captured shape gets its RMS template ids stripped, so the stored template is deploy-ready in any
        # tenant, while JSON that deliberately names a template id keeps it.
        $DropFields = if ($Source.PSObject.Properties['LabelActions']) { @(Get-CIPPSensitivityLabelField -NonPortable) } else { @() }

        $DisplayName = $Source.DisplayName ?? $Source.Name ?? $Source.name
        $Ordered = [ordered]@{
            DisplayName = $DisplayName
            Name        = $Source.Name ?? $Source.name
            Comment     = $Source.Comment ?? $Source.comments
        }
        foreach ($Prop in $Source.PSObject.Properties) {
            if ($Prop.Name -notin $KeepFields -or $Prop.Name -in $DropFields) { continue }
            if ($Ordered.Contains($Prop.Name)) { continue }
            $Ordered[$Prop.Name] = $Prop.Value
        }

        $JSON = ([pscustomobject]$Ordered | ConvertTo-Json -Depth 10)

        # Encryption rights granted to the source tenant's own domain would follow the template into every
        # other tenant. Swap them for %defaultdomain% so each deploy resolves to the target tenant instead.
        $SourceTenant = $Request.Body.tenantFilter
        if ($SourceTenant -and $Source.PSObject.Properties['LabelActions']) {
            $TenantInfo = Get-Tenants -TenantFilter $SourceTenant
            $SourceDomains = [System.Collections.Generic.List[string]]::new()
            foreach ($Domain in @($TenantInfo.defaultDomainName, $TenantInfo.initialDomainName)) {
                if ($Domain) { $SourceDomains.Add($Domain) }
            }
            try {
                $VerifiedDomains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$select=id,isVerified' -tenantid $SourceTenant
                foreach ($Domain in @($VerifiedDomains | Where-Object { $_.isVerified })) { $SourceDomains.Add($Domain.id) }
            } catch {
                Write-Information "Could not list domains for $SourceTenant, falling back to its default and initial domain: $($_.Exception.Message)"
            }
            $JSON = ConvertTo-CIPPSensitivityLabelDomainToken -Json $JSON -Domains $SourceDomains
        }

        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$JSON"
            RowKey       = "$GUID"
            PartitionKey = 'SensitivityLabelTemplate'
        }
        $Result = "Successfully created Sensitivity Label Template: $DisplayName with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Sensitivity Label Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
