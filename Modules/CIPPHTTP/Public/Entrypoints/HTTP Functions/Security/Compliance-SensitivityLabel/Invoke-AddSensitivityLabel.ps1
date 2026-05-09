Function Invoke-AddSensitivityLabel {
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

    $ReadOnlyProperties = @(
        'GUID', 'comments', 'PolicyParams',
        'Identity', 'Guid', 'Id', 'ImmutableId', 'IsValid',
        'WhenCreated', 'WhenChanged', 'WhenCreatedUTC', 'WhenChangedUTC',
        'CreatedBy', 'ModifiedBy', 'LastModifiedBy', 'ObjectState',
        'Type', 'PublishedInPolicies', 'Disabled'
    )

    $RawParams = $Request.Body.PowerShellCommand | ConvertFrom-Json
    $PolicyParams = $RawParams.PolicyParams

    $LabelParams = @{}
    foreach ($prop in $RawParams.PSObject.Properties) {
        if ($prop.Name -in $ReadOnlyProperties) { continue }
        $val = $prop.Value
        if ($null -eq $val) { continue }
        if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
        if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { continue }
        $LabelParams[$prop.Name] = $val
    }

    $Tenants = ($Request.Body.selectedTenants).value
    $Result = foreach ($TenantFilter in $Tenants) {
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-Label' -cmdParams $LabelParams -Compliance -useSystemMailbox $true

            if ($PolicyParams) {
                $PolicyHash = @{}
                $PolicyParams.PSObject.Properties | ForEach-Object {
                    $val = $_.Value
                    if ($null -eq $val) { return }
                    if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { return }
                    if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { return }
                    $PolicyHash[$_.Name] = $val
                }
                if (-not $PolicyHash.ContainsKey('Labels') -or -not $PolicyHash['Labels']) {
                    $PolicyHash['Labels'] = @($LabelParams.Name)
                }
                if (-not $PolicyHash.ContainsKey('Name') -or [string]::IsNullOrWhiteSpace($PolicyHash['Name'])) {
                    $PolicyHash['Name'] = "$($LabelParams.Name) Policy"
                }
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-LabelPolicy' -cmdParams $PolicyHash -Compliance -useSystemMailbox $true
            }

            "Successfully created sensitivity label $($LabelParams.Name) for $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created sensitivity label $($LabelParams.Name) for $TenantFilter." -sev Info
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            "Could not create sensitivity label for $($TenantFilter): $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Could not create sensitivity label for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{Results = @($Result) }
        })

}
