function Invoke-CIPPStandardExchangeConnectorTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ExchangeConnectorTemplate
    .SYNOPSIS
        (Label) Exchange Connector Template
    .DESCRIPTION
        (Helptext) Deploy and manage Exchange connectors.
        (DocsDescription) Deploy and manage Exchange connectors.
    .NOTES
        CAT
            Templates
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        IMPACT
            Medium Impact
        ADDEDDATE
            2023-12-30
        EXECUTIVETEXT
            Configures standardized Exchange connectors that control how email flows between your organization and external systems. These templates ensure secure and reliable email delivery while maintaining proper routing and security policies for business communications.
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"exConnectorTemplate","label":"Select Exchange Connector Template","api":{"url":"/api/ListExConnectorTemplates","labelField":"name","valueField":"GUID","queryKey":"ListExConnectorTemplates"}}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'ExConnector' -TenantFilter $Tenant -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') #No Foundation because that does not allow powershell access

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'ExConnectorTemplate'"
    $AllConnectorTemplates = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    $TemplateIds = $Settings.exConnectorTemplate.value ?? $Settings.exConnectorTemplate
    $Templates = $AllConnectorTemplates | Where-Object { $TemplateIds -contains $_.RowKey }
    $Types = $Templates.direction | Sort-Object -Unique

    $ExoBulkCommands = foreach ($Type in $Types) {
        @{
            CmdletInput = @{
                CmdletName = "Get-$($Type)connector"
                Parameters = @{}
            }
        }
    }
    $ExistingConnectors = New-ExoBulkRequest -tenantid $Tenant -cmdletArray @($ExoBulkCommands) -ReturnWithCommand $true

    if ($Settings.remediate -eq $true) {
        foreach ($Template in $Templates) {
            try {
                $ConnectorType = $Template.direction
                $RequestParams = $Template.JSON | ConvertFrom-Json
                if ($RequestParams.comment) { $RequestParams.comment = Get-CIPPTextReplacement -Text $RequestParams.comment -TenantFilter $Tenant } else { $RequestParams | Add-Member -NotePropertyValue 'no comment' -NotePropertyName comment -Force }
                $Existing = $ExistingConnectors.$("Get-$($ConnectorType)connector") | Where-Object -Property Identity -EQ $RequestParams.name
                if ($Existing) {
                    $RequestParams | Add-Member -NotePropertyValue $Existing.Identity -NotePropertyName Identity -Force
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet "Set-$($ConnectorType)connector" -cmdParams $RequestParams -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Updated transport rule $($RequestParams.name)" -sev info
                } else {
                    $null = New-ExoRequest -tenantid $Tenant -cmdlet "New-$($ConnectorType)connector" -cmdParams $RequestParams -useSystemMailbox $true
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Created transport rule $($RequestParams.name)" -sev info
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to create or update Exchange Connector Rule: $ErrorMessage" -sev 'Error'
            }
        }
    }

    if ($Settings.alert -eq $true) {
        foreach ($Template in $Templates) {
            $ConnectorType = $Template.direction
            $RequestParams = $Template.JSON | ConvertFrom-Json
            $Existing = $ExistingConnectors.$("Get-$($ConnectorType)connector") | Where-Object -Property Identity -EQ $RequestParams.name
            if (-not $Existing) {
                Write-StandardsAlert -message "Exchange Connector Template '$($RequestParams.name)' of type '$($ConnectorType)' is not deployed" -object $RequestParams -tenant $Tenant -standardName 'ExchangeConnectorTemplate' -standardId $Settings.standardId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Exchange Connector Template '$($RequestParams.name)' of type '$($ConnectorType)' is not deployed" -sev Warning
            } else {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Exchange Connector Template '$($RequestParams.name)' of type '$($ConnectorType)' is deployed" -sev Info
            }
        }
    }

    if ($Settings.report -eq $true) {
        # Extract expected connectors from templates
        $ExpectedConnectors = foreach ($Template in $Templates) {
            $TemplateParams = $Template.JSON | ConvertFrom-Json
            [PSCustomObject]@{
                Identity = $TemplateParams.name
                Type     = $Template.direction
            }
        }

        # Get matching deployed connectors
        $DeployedConnectors = foreach ($ExpectedConnector in $ExpectedConnectors) {
            $ConnectorType = $ExpectedConnector.Type
            $ExistingConnector = $ExistingConnectors.$("Get-$($ConnectorType)connector") | Where-Object -Property Identity -EQ $ExpectedConnector.Identity
            if ($ExistingConnector) {
                [PSCustomObject]@{
                    Identity = $ExistingConnector.Identity
                    Type     = $ConnectorType
                }
            }
        }

        $CurrentValue = [PSCustomObject]@{
            Connectors = @($DeployedConnectors)
        }
        $ExpectedValue = [PSCustomObject]@{
            Connectors = @($ExpectedConnectors)
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.ExchangeConnectorTemplates' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'ExchangeConnectorTemplatesDeployed' -FieldValue ($DeployedConnectors.Identity) -StoreAs StringArray -Tenant $tenant
    }
}
