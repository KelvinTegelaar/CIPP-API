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

    $ReadOnlyProperties = @(
        'GUID', 'comments', 'Workload', 'DistributionStatus', 'DistributionResults', 'LastStatusUpdate',
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

    try {
        $GUID = (New-Guid).GUID

        $Source = if ($Request.Body.PowerShellCommand) {
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
            [pscustomobject]$Request.Body
        }

        $Clean = [ordered]@{}
        foreach ($prop in $Source.PSObject.Properties) {
            if ($prop.Name -in $ReadOnlyProperties) { continue }
            $val = $prop.Value
            if ($null -eq $val) { continue }
            if ($val -is [string] -and [string]::IsNullOrWhiteSpace($val)) { continue }
            if (($val -is [array] -or $val -is [System.Collections.IList]) -and @($val).Count -eq 0) { continue }

            if ($prop.Name -in $LocationProperties) {
                $normalized = ConvertTo-LocationValue -Value $val
                if ($null -eq $normalized) { continue }
                $Clean[$prop.Name] = $normalized
            } else {
                $Clean[$prop.Name] = $val
            }
        }

        $Ordered = [ordered]@{
            name     = $Clean['Name'] ?? $Source.Name ?? $Source.name
            comments = $Clean['Comment'] ?? $Source.Comment ?? $Source.comments
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
