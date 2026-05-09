Function Invoke-AddDlpCompliancePolicy {
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

    # Properties that come back from Get-DlpCompliancePolicy but are not valid input for New-DlpCompliancePolicy.
    # Workload triggers AmbiguousParameterSetException because the Workload parameter set on New-* (3rd party
    # app DLP) conflicts with the location-based set.
    $ReadOnlyProperties = @(
        'GUID', 'comments', 'RuleParams',
        'Workload', 'DistributionStatus', 'DistributionResults', 'LastStatusUpdate',
        'Enabled', 'Identity', 'Guid', 'Id', 'ImmutableId', 'IsValid',
        'WhenCreated', 'WhenChanged', 'WhenCreatedUTC', 'WhenChangedUTC',
        'CreatedBy', 'ModifiedBy', 'LastModifiedBy', 'ObjectState',
        'PolicyCategory', 'PolicyVersion', 'Type', 'DisplayName',
        'ContentContainsSensitiveInformation', 'ExchangeSenderMemberOf', 'ExchangeSenderMemberOfException',
        'AssociatedRules', 'RuleCount'
    )

    # Properties that hold locations. Get returns them as arrays of complex objects, but New expects strings or
    # string arrays. We flatten objects to their Name (or identity) and collapse to 'All' if present.
    $LocationProperties = @(
        'ExchangeLocation', 'ExchangeLocationException',
        'SharePointLocation', 'SharePointLocationException',
        'OneDriveLocation', 'OneDriveLocationException',
        'TeamsLocation', 'TeamsLocationException',
        'EndpointDlpLocation', 'EndpointDlpLocationException',
        'OnPremisesScannerDlpLocation', 'OnPremisesScannerDlpLocationException',
        'ThirdPartyAppDlpLocation', 'ThirdPartyAppDlpLocationException',
        'PowerBIDlpLocation', 'PowerBIDlpLocationException',
        'ModernGroupLocation', 'ModernGroupLocationException'
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

    # Build the param hash — strip read-only fields and empty values, normalize locations
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
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpCompliancePolicy' -cmdParams $RequestParams -Compliance -useSystemMailbox $true

            if ($RuleParams) {
                # Ensure rule references the new policy
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
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpComplianceRule' -cmdParams $RuleHash -Compliance -useSystemMailbox $true
            }

            "Successfully created DLP compliance policy $($RequestParams.Name) for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created DLP compliance policy $($RequestParams.Name) for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create DLP compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create DLP compliance policy for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
