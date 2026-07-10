Function Invoke-ListSensitiveInfoTypeRulePackage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitiveInfoType.Read
    .DESCRIPTION
        Returns the rule pack behind a custom Sensitive Information Type - the parsed rule configuration
        (entities with confidence/proximity and their resolved regex/keyword/fingerprint detection) plus
        the raw ClassificationRuleCollection XML - so the UI can show what a SIT actually detects.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $RulePackId = $Request.Query.RulePackId ?? $Request.Body.RulePackId

    try {
        if ([string]::IsNullOrWhiteSpace($RulePackId)) { throw 'RulePackId is required.' }

        $Pack = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationTypeRulePackage' -cmdParams @{ Identity = $RulePackId } -Compliance |
            Select-Object * -ExcludeProperty *odata*, *data.type* | Select-Object -First 1
        $Xml = [string]$Pack.ClassificationRuleCollectionXml

        # Reuse the drift comparer's semantic parser to expose a friendly rule configuration.
        $Configuration = if (-not [string]::IsNullOrWhiteSpace($Xml)) { ConvertTo-CIPPSitComparable -Xml $Xml } else { @{} }

        $Result = [ordered]@{
            RulePackId         = $RulePackId
            RuleCollectionName = $Pack.RuleCollectionName
            Publisher          = $Pack.Publisher
            Version            = $Pack.Version
            Configuration      = $Configuration
            Xml                = $Xml
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Result = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Result
        })
}
