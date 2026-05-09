Function Invoke-AddRetentionCompliancePolicy {
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

    $ReadOnlyProperties = @(
        'GUID', 'comments', 'RuleParams',
        'Workload', 'DistributionStatus', 'DistributionResults', 'LastStatusUpdate',
        'Enabled', 'Identity', 'Guid', 'Id', 'ImmutableId', 'IsValid',
        'WhenCreated', 'WhenChanged', 'WhenCreatedUTC', 'WhenChangedUTC',
        'CreatedBy', 'ModifiedBy', 'LastModifiedBy', 'ObjectState',
        'PolicyCategory', 'PolicyVersion', 'Type', 'DisplayName',
        'AssociatedRules', 'RuleCount'
    )

    $LocationProperties = @(
        'ExchangeLocation', 'ExchangeLocationException',
        'SharePointLocation', 'SharePointLocationException',
        'OneDriveLocation', 'OneDriveLocationException',
        'ModernGroupLocation', 'ModernGroupLocationException',
        'TeamsChannelLocation', 'TeamsChannelLocationException',
        'TeamsChatLocation', 'TeamsChatLocationException',
        'PublicFolderLocation',
        'SkypeLocation', 'SkypeLocationException'
    )

    function ConvertTo-LocationValue {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [string]) { return $Value }
        $items = @($Value) | ForEach-Object {
            if ($null -eq $_) { return }
            if ($_ -is [string]) { $_ }
            elseif ($_.Name) { $_.Name }
            elseif ($_.PrimarySmtpAddress) { $_.PrimarySmtpAddress }
            elseif ($_.DisplayName) { $_.DisplayName }
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($items.Count -eq 0) { return $null }
        if ($items -contains 'All') { return 'All' }
        return @($items)
    }

    $RawParams = $Request.Body.PowerShellCommand | ConvertFrom-Json
    $RuleParams = $RawParams.RuleParams

    $RequestParams = @{}
    foreach ($prop in $RawParams.PSObject.Properties) {
        if ($prop.Name -in $ReadOnlyProperties) { continue }
        $val = $prop.Value
        if ($null -eq $val) { continue }
        if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
        if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { continue }

        if ($prop.Name -in $LocationProperties) {
            $normalized = ConvertTo-LocationValue -Value $val
            if ($null -eq $normalized) { continue }
            $RequestParams[$prop.Name] = $normalized
        } else {
            $RequestParams[$prop.Name] = $val
        }
    }

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionCompliancePolicy' -cmdParams $RequestParams -Compliance -AsApp -useSystemMailbox $true

            if ($RuleParams) {
                $RuleHash = @{}
                $RuleParams.PSObject.Properties | ForEach-Object {
                    $val = $_.Value
                    if ($null -eq $val) { return }
                    if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { return }
                    if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { return }
                    $RuleHash[$_.Name] = $val
                }
                $RuleHash['Policy'] = $RequestParams.Name
                if (-not $RuleHash.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace($RuleHash['Name'])) {
                    $RuleHash['Name'] = "$($RequestParams.Name) Rule"
                }
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-RetentionComplianceRule' -cmdParams $RuleHash -Compliance -AsApp -useSystemMailbox $true
            }

            "Successfully created Retention compliance policy $($RequestParams.Name) for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created Retention compliance policy $($RequestParams.Name) for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create Retention compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create Retention compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
