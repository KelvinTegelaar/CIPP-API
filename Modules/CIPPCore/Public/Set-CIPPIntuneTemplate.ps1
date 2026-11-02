function Set-CIPPIntuneTemplate {
    <#
    .SYNOPSIS
        Stores an Intune policy template.

    .PARAMETER PayloadChanged
        Set when a new policy payload is being written. Validation errors then refuse the write; otherwise
        they are only logged, so an already-broken template can still be renamed.
    #>
    param (
        [Parameter(Mandatory = $true)]
        $RawJSON,
        $GUID,
        $DisplayName,
        $Description,
        $templateType,
        $Package,
        $Headers,
        [switch]$PayloadChanged
    )
    $APIName = 'Set-CIPPIntuneTemplate'
    if (!$DisplayName) { throw 'You must enter a displayname' }

    $Validation = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType $templateType -DisplayName $DisplayName -IncludeCatalogChecks:$PayloadChanged
    if (-not $Validation.IsValid) {
        $Reason = $Validation.Errors -join ' '
        if ($PayloadChanged) {
            throw [System.ArgumentException]::new("The template was not saved because it would not deploy: $Reason")
        }
        Write-LogMessage -Headers $Headers -API $APIName -message "Saved template '$DisplayName' ($GUID) despite existing problems, because this edit did not change the policy: $Reason" -Sev 'Warning'
    }
    foreach ($Warning in $Validation.Warnings) {
        Write-LogMessage -Headers $Headers -API $APIName -message "Template '$DisplayName' ($GUID): $Warning" -Sev 'Warning'
    }

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
    Write-LogMessage -Headers $Headers -API $APIName -message "Created intune policy template named $DisplayName with GUID $GUID" -Sev 'Debug'

    return 'Successfully added template'
}
