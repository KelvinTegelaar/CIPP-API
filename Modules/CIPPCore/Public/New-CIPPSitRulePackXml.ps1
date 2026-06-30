function New-CIPPSitRulePackXml {
    <#
    .SYNOPSIS
        Synthesize a Microsoft Purview Sensitive Information Type rule pack XML from simple inputs.
    .DESCRIPTION
        New-DlpSensitiveInformationTypeRulePackage imports a custom SIT *rule package* (regex/keyword
        based, Type=Entity). It requires the 2011 'mce' schema namespace and UTF-16 encoded bytes - the
        2018 'search.external' namespace is rejected with a schema-validation error.

        For simple regex-based SITs this helper builds a minimal valid rule pack with fresh GUIDs so
        callers can hand it to the cmdlet without authoring XML. (NOTE: the singular
        New-DlpSensitiveInformationType cmdlet is a *document-fingerprint* primitive and must NOT be used
        for regex SITs - it stores the FileData as a fingerprint and discards the regex.)
    .NOTES
        The returned string declares encoding="utf-16"; callers must encode it with
        [System.Text.Encoding]::Unicode (UTF-16LE, no BOM) so the bytes match the declaration.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Description,
        [Parameter(Mandatory)][string]$Pattern,
        [int]$Confidence = 85,
        [int]$PatternsProximity = 300,
        [string]$Locale = 'en-US',
        [string]$PublisherName = 'CIPP'
    )

    $RulePackId = (New-Guid).Guid
    $PublisherId = (New-Guid).Guid
    $EntityId = (New-Guid).Guid
    $RegexId = "Regex_$(((New-Guid).Guid) -replace '-')"
    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }

    return @"
<?xml version="1.0" encoding="utf-16"?>
<RulePackage xmlns="http://schemas.microsoft.com/office/2011/mce">
  <RulePack id="$RulePackId">
    <Version major="1" minor="0" build="0" revision="0"/>
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
}
