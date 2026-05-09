Function Invoke-AddSensitiveInfoType {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.SensitiveInfoType.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    function New-CippSitRulePackXml {
        param(
            [Parameter(Mandatory)][string]$Name,
            [string]$Description,
            [Parameter(Mandatory)][string]$Pattern,
            [int]$Confidence = 85,
            [int]$PatternsProximity = 300,
            [string]$Locale = 'en-us',
            [string]$PublisherName = 'CIPP'
        )

        $RulePackId = (New-Guid).Guid
        $PublisherId = (New-Guid).Guid
        $EntityId = (New-Guid).Guid
        $RegexId = "Regex_$(((New-Guid).Guid) -replace '-')"

        $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }

        $Xml = @"
<?xml version="1.0" encoding="UTF-8"?>
<RulePackage xmlns="http://schemas.microsoft.com/office/2018/09/search.external/rulepack">
  <RulePack id="$RulePackId">
    <Version major="1" minor="0" patch="0" build="0"/>
    <Publisher id="$PublisherId"/>
    <Details defaultLangCode="$Locale">
      <LocalizedDetails langcode="$Locale">
        <PublisherName>$(& $esc $PublisherName)</PublisherName>
        <Name>$(& $esc $Name)</Name>
        <Description>$(& $esc $Description)</Description>
      </LocalizedDetails>
    </Details>
  </RulePack>
  <Rules>
    <Entity id="$EntityId" patternsProximity="$PatternsProximity" recommendedConfidence="$Confidence">
      <Pattern confidenceLevel="$Confidence">
        <IdMatch idRef="$RegexId"/>
      </Pattern>
    </Entity>
    <Regex id="$RegexId">$(& $esc $Pattern)</Regex>
    <LocalizedStrings>
      <Resource idRef="$EntityId">
        <Name default="true" langcode="$Locale">$(& $esc $Name)</Name>
        <Description default="true" langcode="$Locale">$(& $esc $Description)</Description>
      </Resource>
    </LocalizedStrings>
  </Rules>
</RulePackage>
"@
        return $Xml
    }

    $ReadOnlyProperties = @(
        'GUID', 'comments',
        'Identity', 'Guid', 'Id', 'ImmutableId', 'IsValid',
        'WhenCreated', 'WhenChanged', 'WhenCreatedUTC', 'WhenChangedUTC',
        'CreatedBy', 'ModifiedBy', 'LastModifiedBy', 'ObjectState',
        'Type', 'State', 'RulePackId', 'RulePackVersion', 'Publisher'
    )

    # Inputs that we use to synthesize the rule pack but should NOT be passed to the cmdlet
    $SimpleModeProperties = @('Pattern', 'Confidence', 'PatternsProximity', 'Locale', 'Recommended', 'PublisherName', 'FileDataBase64')

    $RawParams = $Request.Body.PowerShellCommand | ConvertFrom-Json

    # Strip read-only and empty values
    $Params = @{}
    foreach ($prop in $RawParams.PSObject.Properties) {
        if ($prop.Name -in $ReadOnlyProperties) { continue }
        $val = $prop.Value
        if ($null -eq $val) { continue }
        if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
        if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { continue }
        $Params[$prop.Name] = $val
    }

    # Determine mode and produce FileData byte array
    $FileDataBytes = $null
    if ($Params.ContainsKey('FileDataBase64') -and $Params['FileDataBase64']) {
        # Advanced mode: caller provided the rule pack XML themselves
        try {
            $FileDataBytes = [System.Convert]::FromBase64String($Params['FileDataBase64'])
        } catch {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "FileDataBase64 is not valid base64: $($_.Exception.Message)" }
                })
        }
    } elseif ($Params.ContainsKey('Pattern') -and $Params['Pattern']) {
        # Simple mode: synthesize a minimal rule pack from Name + Pattern + Confidence
        try {
            $Xml = New-CippSitRulePackXml `
                -Name $Params['Name'] `
                -Description ($Params['Description'] ?? '') `
                -Pattern $Params['Pattern'] `
                -Confidence ([int]($Params['Confidence'] ?? 85)) `
                -PatternsProximity ([int]($Params['PatternsProximity'] ?? 300)) `
                -Locale ($Params['Locale'] ?? 'en-us') `
                -PublisherName ($Params['PublisherName'] ?? 'CIPP')
            $FileDataBytes = [System.Text.Encoding]::UTF8.GetBytes($Xml)
        } catch {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Failed to build rule pack XML: $($_.Exception.Message)" }
                })
        }
    } else {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Provide either 'Pattern' (simple mode) or 'FileDataBase64' (advanced mode)." }
            })
    }

    # Build the cmdlet param hash. Strip simple-mode helper props, keep only what New-DlpSensitiveInformationType wants.
    $CmdletParams = @{
        FileData = $FileDataBytes
    }
    foreach ($k in @('Name', 'Description', 'Locale')) {
        if ($Params.ContainsKey($k) -and -not [string]::IsNullOrWhiteSpace([string]$Params[$k])) {
            $CmdletParams[$k] = $Params[$k]
        }
    }

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpSensitiveInformationType' -cmdParams $CmdletParams -Compliance -useSystemMailbox $true
            "Successfully created Sensitive Information Type $($CmdletParams.Name) for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created Sensitive Information Type $($CmdletParams.Name) for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create Sensitive Information Type for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create Sensitive Information Type for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
