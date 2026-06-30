function Invoke-ListCAtemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.ConditionalAccess.Read
    .DESCRIPTION
        Lists saved Conditional Access policy templates for deploying standardized CA configurations.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $GUID = $Request.query.id ?? $Request.query.ID ?? $Request.query.guid ?? $Request.query.GUID
    #Migrating old policies whenever you do a list
    $Table = Get-CippTable -tablename 'templates'
    $Imported = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'settings'"
    if ($Imported.CATemplate -ne $true) {
        $Templates = Get-ChildItem (Join-Path $env:CIPPRootPath 'Config\*.CATemplate.json') | ForEach-Object {
            $Entity = @{
                JSON         = "$(Get-Content $_)"
                RowKey       = "$($_.name)"
                PartitionKey = 'CATemplate'
                GUID         = "$($_.name)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        }
        Add-CIPPAzDataTableEntity @Table -Entity @{
            CATemplate   = $true
            RowKey       = 'CATemplate'
            PartitionKey = 'settings'
        } -Force
    }
    #List new policies
    $Table = Get-CippTable -tablename 'templates'

    if ($Request.query.mode -eq 'Tag') {
        $Filter = "PartitionKey eq 'CATemplate'"
        $RawTemplates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        #when the mode is tag, show all the potential tags, return the object with: label: tag, value: tag, count: number of templates with that tag, unique only
        $Templates = @($RawTemplates | Where-Object { $_.Package } | Group-Object -Property Package | ForEach-Object {
            $package = $_.Name
            $packageTemplates = @($_.Group)
            $templateCount = $packageTemplates.Count
            [pscustomobject]@{
                label         = "$($package) ($templateCount Templates)"
                value         = $package
                type          = 'tag'
                templateCount = $templateCount
                templates     = @($packageTemplates | ForEach-Object {
                        try {
                            $data = $_.JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue
                            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force
                            $data | Add-Member -NotePropertyName 'package' -NotePropertyValue $_.Package -Force
                            $data | Add-Member -NotePropertyName 'source' -NotePropertyValue $_.Source -Force
                            $data | Add-Member -NotePropertyName 'isSynced' -NotePropertyValue (![string]::IsNullOrEmpty($_.SHA)) -Force
                            $data
                        } catch {
                        }
                    })
            }
        } | Sort-Object -Property label)
    } else {
        if ($GUID) {
            $SafeGUID = ConvertTo-CIPPODataFilterValue -Value $GUID -Type Guid
            $Filter = "PartitionKey eq 'CATemplate' and GUID eq '$SafeGUID'"
            $RawTemplates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        }
        else {
            $RawTemplates = (Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate'")
        }
        $Templates = $RawTemplates | ForEach-Object {
            try {
                $row = $_
                $data = $row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $row.GUID -Force
                $data | Add-Member -NotePropertyName 'source' -NotePropertyValue $row.Source -Force
                $data | Add-Member -NotePropertyName 'isSynced' -NotePropertyValue (![string]::IsNullOrEmpty($row.SHA)) -Force
                $data | Add-Member -NotePropertyName 'package' -NotePropertyValue $row.Package -Force
                $data
            } catch {
                Write-Warning "Failed to process CA template: $($row.RowKey) - $($_.Exception.Message)"
            }
        } | Sort-Object -Property displayName
    }

    $Templates = ConvertTo-Json -InputObject @($Templates) -Depth 100
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Templates
        })

}
