function Set-CIPPIntuneTemplate {
    param (
        [Parameter(Mandatory = $true)]
        $RawJSON,
        $GUID,
        $DisplayName,
        $Description,
        $templateType,
        $Package,
        $Headers
    )
    Write-Host "Received $DisplayName, $Description, $RawJSON, $templateType"
    if (!$DisplayName) { throw 'You must enter a displayname' }
    if ($null -eq ($RawJSON | ConvertFrom-Json)) { throw 'the JSON is invalid' }

    $object = [PSCustomObject]@{
        Displayname = $DisplayName
        Description = $Description
        RAWJson     = $RawJSON
        Type        = $templateType
        GUID        = $GUID
    } | ConvertTo-Json -Depth 10 -Compress
    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true
    Add-CIPPAzDataTableEntity @Table -Entity @{
        JSON         = "$object"
        RowKey       = "$GUID"
        GUID         = "$GUID"
        Package      = "$Package"
        PartitionKey = 'IntuneTemplate'
    }
    Write-LogMessage -Headers $Headers -API $APINAME -message "Created intune policy template named $($Request.body.displayname) with GUID $GUID" -Sev 'Debug'

    return 'Successfully added template'
}
